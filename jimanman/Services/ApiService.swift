import Foundation

/// 网络服务 - 所有API接口与Android端完全一致
class ApiService: ObservableObject {
    static let shared = ApiService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        // 审核网络下 waitsForConnectivity 可能长时间挂起，登录页表现为错误弹窗
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    private let baseURL = ApiConfig.baseURL
    private let timeout: TimeInterval = 15
    private var wxLoginInFlightCodes = Set<String>()
    
    /// 获取Token
    var token: String? {
        get { UserDefaults.standard.string(forKey: "jmm_token") }
        set { UserDefaults.standard.set(newValue, forKey: "jmm_token") }
    }
    
    /// 通用请求方法
    private func request(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async -> [String: Any]? {
        guard let url = URL(string: url) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        
        if let token = self.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                print("API HTTP \(httpResponse.statusCode): \(preview)")
            }
            guard !data.isEmpty else {
                print("API empty response: \(url)")
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            print("Network error (\(url)): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// POST form-body（对齐 Android URLEncoder.encode）
    private func postForm(url: String, params: [String: String]) async -> [String: Any]? {
        let body = params
            .map { "\(formURLEncode($0.key))=\(formURLEncode($0.value))" }
            .joined(separator: "&")
        return await request(url: url, method: "POST",
                             headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"],
                             body: body.data(using: .utf8))
    }

    private func formURLEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
    
    /// POST JSON body
    private func postJSON(url: String, dict: [String: Any]) async -> [String: Any]? {
        let body = try? JSONSerialization.data(withJSONObject: dict)
        return await request(url: url, method: "POST",
                             headers: ["Content-Type": "application/json"],
                             body: body)
    }
    
    // MARK: - 首页轮播图
    /// GET /api/index/index
    func fetchBannerUrls() async -> [String] {
        guard let json = await request(url: "\(baseURL)/api/index/index"),
              let code = json["code"] as? Int, code == 200 else { return [] }
        guard let data = json["data"] as? [String: Any],
              let adList = data["ad_list1"] as? [[String: Any]] else { return [] }
        return adList.compactMap { item in
            (item["filepath"] as? String)?.replacingOccurrences(of: "/{2,}", with: "/", options: .regularExpression)
        }
    }
    
    // MARK: - 微信登录
    /// POST /api/user/wxLogin
    /// 微信 code 只能使用一次；仅对瞬时网络错误自动重试，避免 "code been used"
    func wxLoginByCode(code: String, source: String = "app") async -> LoginResult {
        if wxLoginInFlightCodes.contains(code) {
            return LoginResult(success: false, token: "", message: "登录处理中，请稍候")
        }
        wxLoginInFlightCodes.insert(code)
        defer { wxLoginInFlightCodes.remove(code) }

        var lastResult = LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        for attempt in 0..<3 {
            if Task.isCancelled {
                return lastResult
            }
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 600_000_000)
            }
            lastResult = await wxLoginByCodeOnce(code: code, source: source)
            if lastResult.success || !shouldRetryWxLogin(lastResult) {
                return lastResult
            }
        }
        return lastResult
    }

    private func wxLoginByCodeOnce(code: String, source: String) async -> LoginResult {
        guard let url = URL(string: "\(baseURL)/api/user/wxLogin") else {
            return LoginResult(success: false, token: "", message: "网络错误")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = "code=\(formURLEncode(code))&source=\(formURLEncode(source))"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                print("wxLogin HTTP \(httpResponse.statusCode): \(preview)")
                if (500...599).contains(httpResponse.statusCode) {
                    return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
                }
            }
            guard !data.isEmpty,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
            }
            guard let statusCode = jsonIntValue(json["code"]) else {
                print("wxLogin unexpected response: \(json)")
                return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
            }
            if statusCode == 200 {
                let token = (json["data"] as? [String: Any])?["token"] as? String ?? ""
                return LoginResult(success: !token.isEmpty, token: token, message: token.isEmpty ? "登录失败：token为空" : "登录成功")
            }
            let msg = json["msg"] as? String ?? "登录失败"
            if msg.lowercased().contains("code been used") {
                return LoginResult(success: false, token: "", message: "微信授权已失效，请重新点击登录")
            }
            return LoginResult(success: false, token: "", message: msg)
        } catch {
            print("wxLogin network error: \(error.localizedDescription)")
            let nsError = error as NSError
            if nsError.code == NSURLErrorTimedOut {
                return LoginResult(success: false, token: "", message: "连接服务器超时，请检查网络后重试")
            }
            return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        }
    }

    private func shouldRetryWxLogin(_ result: LoginResult) -> Bool {
        if result.message.contains("code been used") || result.message.contains("授权已失效") {
            return false
        }
        if result.message.contains("登录失败") && !result.message.contains("网络") && !result.message.contains("超时") {
            return false
        }
        return result.message.contains("网络") || result.message.contains("超时") || result.message.contains("处理中")
    }

    /// GET/POST /api/user/wechatOauthUrl（带重试；服务端不可用时返回 nil）
    func fetchWechatOauthURL() async -> URL? {
        for attempt in 0..<3 {
            if let url = await fetchWechatOauthURLOnce(method: "GET") {
                return url
            }
            if let url = await fetchWechatOauthURLOnce(method: "POST") {
                return url
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        return nil
    }

    private func fetchWechatOauthURLOnce(method: String) async -> URL? {
        let endpoint = "\(baseURL)/api/user/wechatOauthUrl"
        let json: [String: Any]?
        if method == "POST" {
            json = await postForm(url: endpoint, params: [:])
        } else {
            json = await request(url: endpoint)
        }
        return parseWechatOauthURL(from: json)
    }

    private func parseWechatOauthURL(from json: [String: Any]?) -> URL? {
        guard let json,
              let code = jsonIntValue(json["code"]),
              code == 200 || code == 0,
              let data = json["data"] as? [String: Any],
              let urlString = data["url"] as? String,
              let url = URL(string: urlString),
              !urlString.isEmpty else {
            if let json {
                print("wechatOauthUrl unexpected response: \(json)")
            }
            return nil
        }
        return url
    }

    /// POST /api/user/appleLogin
    func appleLogin(credential: AppleSignInCredential) async -> LoginResult {
        var lastResult = LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        for attempt in 0..<3 {
            if Task.isCancelled {
                return lastResult
            }
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000)
            }
            lastResult = await appleLoginOnce(credential: credential)
            if lastResult.success {
                return lastResult
            }
            let retryable = lastResult.message.contains("网络") || lastResult.message.contains("超时")
            if !retryable {
                return lastResult
            }
        }
        return lastResult
    }

    private func appleLoginOnce(credential: AppleSignInCredential) async -> LoginResult {
        let params: [String: String] = [
            "identity_token": credential.identityToken,
            "authorization_code": credential.authorizationCode ?? "",
            "user_identifier": credential.userIdentifier,
            "email": credential.email ?? "",
            "given_name": credential.givenName ?? "",
            "family_name": credential.familyName ?? "",
        ]

        guard let url = URL(string: "\(baseURL)/api/user/appleLogin") else {
            return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: params)

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                print("appleLogin HTTP \(httpResponse.statusCode): \(preview)")
            }
            guard !data.isEmpty,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let statusCode = jsonIntValue(json["code"]) else {
                return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
            }

            if statusCode == 200 {
                let token = (json["data"] as? [String: Any])?["token"] as? String ?? ""
                return LoginResult(
                    success: !token.isEmpty,
                    token: token,
                    message: token.isEmpty ? "登录失败：token为空" : "登录成功"
                )
            }

            return LoginResult(success: false, token: "", message: json["msg"] as? String ?? "Apple 登录失败")
        } catch {
            print("appleLogin network error: \(error.localizedDescription)")
            let nsError = error as NSError
            if nsError.code == NSURLErrorTimedOut {
                return LoginResult(success: false, token: "", message: "连接服务器超时，请检查网络后重试")
            }
            return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        }
    }

    /// POST /api/user/sendVerifyCode
    func sendVerifyCode(phone: String, type: String) async -> (success: Bool, message: String) {
        guard let json = await postForm(url: "\(baseURL)/api/user/sendVerifyCode", params: [
            "phone": phone,
            "type": type
        ]), let statusCode = jsonIntValue(json["code"]) else {
            return (false, "网络错误，请稍后重试")
        }
        if statusCode == 200 {
            return (true, json["msg"] as? String ?? "验证码已发送")
        }
        return (false, json["msg"] as? String ?? "发送失败")
    }

    /// POST /api/user/phoneLogin
    func phoneLogin(phone: String, password: String = "", verifyCode: String = "") async -> LoginResult {
        var params = ["phone": phone]
        if !verifyCode.isEmpty {
            params["verify_code"] = verifyCode
        } else {
            params["password"] = password
        }
        return parseLoginJSON(await postForm(url: "\(baseURL)/api/user/phoneLogin", params: params))
    }

    /// POST /api/user/phoneRegister
    func phoneRegister(phone: String, verifyCode: String, password: String) async -> LoginResult {
        parseLoginJSON(await postForm(url: "\(baseURL)/api/user/phoneRegister", params: [
            "phone": phone,
            "verify_code": verifyCode,
            "password": password
        ]))
    }

    private func parseLoginJSON(_ json: [String: Any]?) -> LoginResult {
        guard let json, let statusCode = jsonIntValue(json["code"]) else {
            return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        }
        if statusCode == 200 {
            let token = (json["data"] as? [String: Any])?["token"] as? String ?? ""
            return LoginResult(
                success: !token.isEmpty,
                token: token,
                message: token.isEmpty ? "登录失败：token为空" : (json["msg"] as? String ?? "登录成功")
            )
        }
        return LoginResult(success: false, token: "", message: json["msg"] as? String ?? "登录失败")
    }

    // MARK: - 获取用户信息
    /// GET /api/user/getInfo
    func fetchUserProfile() async -> UserProfile? {
        guard let json = await request(url: "\(baseURL)/api/user/getInfo"),
              let code = json["code"] as? Int, code == 200 else { return nil }
        guard let data = json["data"] as? [String: Any] else { return nil }
        return UserProfile(
            id: data["id"] as? Int ?? 0,
            nickname: data["nickname"] as? String ?? "",
            avatarUrl: data["avatarUrl"] as? String ?? "",
            isVip: data["is_vip"] as? Bool ?? false,
            vipTime: data["vip_expire_time_text"] as? String ?? "",
            school: data["school"] as? String ?? "",
            major: data["major"] as? String ?? "",
            schoolYear: {
                if let y = data["schoolyear"] as? Int { return String(y) }
                return data["schoolyear"] as? String ?? ""
            }(),
            invitationCode: data["invitation_code"] as? String ?? ""
        )
    }

    func fetchAcademicAssessmentLocked() async -> Bool {
        let local = AssessmentStore.isLocked
        guard let json = await request(url: "\(baseURL)/api/user/getInfo"),
              let code = json["code"] as? Int, code == 200,
              let data = json["data"] as? [String: Any] else { return local }
        let locked: Bool
        if let flag = data["academic_assessment_locked"] as? Bool {
            locked = flag
        } else if let flag = data["academic_assessment_locked"] as? Int {
            locked = flag == 1
        } else {
            locked = (data["academic_assessment"] as? String) == "已确认"
        }
        AssessmentStore.setLocked(locked)
        return locked
    }
    
    // MARK: - 更新用户信息
    /// POST /api/user/updateInfo (JSON)
    func updateProfileInfo(nickname: String, school: String, major: String) async -> Bool {
        let dict: [String: Any] = [
            "nickname": nickname,
            "school": school,
            "major": major
        ]
        guard let json = await postJSON(url: "\(baseURL)/api/user/updateInfo", dict: dict),
              let code = json["code"] as? Int else { return false }
        return code == 0 || code == 200
    }
    
    // MARK: - 更新用户信息（form）
    /// POST /api/user/updateInfo (form)
    func updateUserInfo(params: [String: String]) async -> Bool {
        guard let json = await postForm(url: "\(baseURL)/api/user/updateInfo", params: params),
              let code = json["code"] as? Int else { return false }
        return code == 0 || code == 200
    }

    /// POST /api/user/saveAssessment 学习能力测评完成 → 教务学员档案
    func saveAcademicAssessment(progress: [Int: Int], reportJSON: String = "{}") async {
        let progressDict = Dictionary(uniqueKeysWithValues: progress.map { (String($0.key), $0.value) })
        let progressJson: String
        if let data = try? JSONSerialization.data(withJSONObject: progressDict),
           let text = String(data: data, encoding: .utf8) {
            progressJson = text
        } else {
            progressJson = "{}"
        }
        _ = await postForm(url: "\(baseURL)/api/user/saveAssessment", params: [
            "status": "已测评",
            "completed": "1",
            "progress": progressJson,
            "report": reportJSON
        ])
    }
    
    // MARK: - 上传文件
    /// POST /api/index/upload
    func uploadFile(imageData: Data, fileName: String, mimeType: String) async -> String? {
        let boundary = "----JMMBoundary\(Int(Date().timeIntervalSince1970 * 1000))"
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        guard let json = await request(url: "\(baseURL)/api/index/upload", method: "POST",
                                       headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                                       body: body),
              let code = json["code"] as? Int, code == 200 else { return nil }
        return (json["data"] as? [String: Any])?["filepath"] as? String
    }
    
    // MARK: - VIP商品列表
    /// GET /api/vip_order/goods_list
    func fetchVipGoodsList() async -> [VipGoods] {
        guard let json = await request(url: "\(baseURL)/api/vip_order/goods_list"),
              let code = json["code"] as? Int, code == 200,
              let arr = json["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let id = jsonIntValue(item["id"]) else { return nil }
            return VipGoods(
                id: id,
                name: item["goods_name"] as? String ?? "",
                tip: item["goods_tip"] as? String ?? "",
                desc: item["goods_desc"] as? String ?? "",
                price: jsonStringValue(item["price"]),
                oldPrice: jsonStringValue(item["old_price"])
            )
        }
    }
    
    // MARK: - 创建VIP订单
    /// POST /api/vip_order/order_create
    func createVipOrder(goodsId: Int) async -> WechatPayParams? {
        guard let json = await postForm(url: "\(baseURL)/api/vip_order/order_create", params: [
            "goods_id": String(goodsId),
            "platform": "app-plus"
        ]), let code = json["code"] as? Int, code == 200 else { return nil }
        
        let payParams = (json["data"] as? [String: Any])?["pay_params"] as? [String: Any] ?? [:]
        guard let appId = payParams["appid"] as? String ?? payParams["appId"] as? String,
              let partnerId = payParams["partnerid"] as? String ?? payParams["partnerId"] as? String,
              let prepayId = payParams["prepayid"] as? String ?? payParams["prepayId"] as? String,
              let nonceStr = payParams["noncestr"] as? String ?? payParams["nonceStr"] as? String,
              let timeStamp = payParams["timestamp"] as? String ?? payParams["timeStamp"] as? String,
              let sign = payParams["sign"] as? String ?? payParams["paySign"] as? String else {
            return nil
        }
        return WechatPayParams(
            appId: appId, partnerId: partnerId, prepayId: prepayId,
            nonceStr: nonceStr, timeStamp: timeStamp, sign: sign,
            packageValue: payParams["package"] as? String ?? "Sign=WXPay"
        )
    }
    
    // MARK: - 订单列表
    /// GET /api/vipOrder/order_list
    func fetchOrderList(page: Int = 1, pageSize: Int = 20) async -> [OrderItem] {
        guard let json = await request(url: "\(baseURL)/api/vipOrder/order_list?page=\(page)&page_size=\(pageSize)"),
              let code = json["code"] as? Int, code == 200 else { return [] }
        guard let data = json["data"] as? [String: Any],
              let list = data["data"] as? [[String: Any]] else { return [] }
        return list.map { item in
            OrderItem(
                orderSn: item["order_sn"] as? String ?? "",
                goodsName: item["goods_name"] as? String ?? "",
                activeMoney: item["active_money"] as? String ?? "",
                stateText: item["state_text"] as? String ?? "",
                paytimeText: item["paytime_text"] as? String ?? "",
                createTimeText: item["create_time_text"] as? String ?? ""
            )
        }
    }
    
    // MARK: - 收藏/错题本列表
    /// GET /api/favorite/list
    func fetchFavoriteRecords(type: String, page: Int = 1, limit: Int = 40) async -> [AskRecordItem] {
        guard let json = await request(url: "\(baseURL)/api/favorite/list?page=\(page)&limit=\(limit)&type=\(type)&keyword="),
              let code = json["code"] as? Int, code == 200 else { return [] }
        guard let data = json["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] ?? (json["data"] as? [[String: Any]]) else { return [] }
        return list.compactMap { item in
            let title = item["title"] as? String ?? ""
            let createTime = item["create_time"] as? String ?? item["update_time"] as? String ?? ""
            var image = normalizeOptionalImage(item["image"] as? String)
            let contentPreview = item["content_preview"] as? String ?? ""
            let itemsArray = item["items"] as? [[String: Any]] ?? []
            
            var question = ""
            var _answer = ""
            for sub in itemsArray {
                let subContent = sub["content"] as? String ?? ""
                let contentType = sub["content_type"] as? String ?? ""
                let subImage = normalizeOptionalImage(sub["image"] as? String)
                
                if image.isEmpty && !subImage.isEmpty { image = subImage }
                if image.isEmpty && (contentType == "image" || subContent.hasPrefix("http")) {
                    image = normalizeOptionalImage(subContent)
                }
                if question.isEmpty && (contentType == "user" || contentType == "question") {
                    question = subContent
                }
                if _answer.isEmpty && contentType == "assistant" {
                    _answer = subContent
                }
            }
            if question.isEmpty { question = title.isEmpty ? contentPreview : title }
            return AskRecordItem(
                id: {
                    let raw = jsonStringValue(item["id"], default: "")
                    return raw.isEmpty ? UUID().uuidString : raw
                }(),
                title: title,
                questionText: question,
                answerSummary: String(_answer.prefix(140)),
                answerText: _answer,
                imageUrl: image,
                timeText: createTime
            )
        }
    }
    
    /// POST /api/favorite/add
    func addFavorite(type: String, title: String, image: String, items: [[String: Any]], sessionId: String = "", subject: String = "") async -> Bool {
        var dict: [String: Any] = ["type": type, "title": title, "image": image, "items": items]
        if !sessionId.isEmpty {
            dict["session_id"] = sessionId
        }
        if !subject.isEmpty {
            dict["subject"] = subject
        }
        guard let json = await postJSON(url: "\(baseURL)/api/favorite/add", dict: dict),
              let code = json["code"] as? Int else { return false }
        return code == 0 || code == 200
    }
    
    // MARK: - 注销账号
    /// POST /api/favorite/add - 图片错题本
    func addWrongBookFromImage(imageUrl: String) async -> Bool {
        let items: [[String: Any]] = [["content": "图片错题", "content_type": "user", "sort": 0]]
        return await addFavorite(type: "1", title: "图片错题", image: imageUrl, items: items)
    }

    /// POST /api/user/cancelAccount
    func cancelAccount() async -> Bool {
        guard let json = await postJSON(url: "\(baseURL)/api/user/cancelAccount", dict: [:]),
              let code = json["code"] as? Int else { return false }
        return code == 200
    }
    
    // MARK: - 版本检查
    /// POST /api/index/version
    func checkAppVersion() async -> String {
        guard let json = await postForm(url: "\(baseURL)/api/index/version", params: [:]),
              let code = json["code"] as? Int, code == 200 else { return "检查失败" }
        let data = json["data"] as? [String: Any] ?? [:]
        let verCode = data["vercode"] as? Int ?? 0
        if verCode > 115 {
            return "发现新版本：\(data["version"] as? String ?? "")"
        }
        return "当前已是最新版本"
    }
    
    // MARK: - AI对话 - 流式请求（对齐 Android cozeStream）
    func streamChat(
        token: String,
        prompt: String,
        sessionId: String,
        agentId: Int = 1,
        fileURL: String = "",
        subject: String = "",
        provider: String = "qwen",
        mode: String = "答案模式",
        history: [[String: String]] = [],
        onSubject: @escaping (String) -> Void = { _ in },
        onChunk: @escaping (String) -> Void
    ) async {
        guard let url = URL(string: "\(baseURL)/api/cozeStream/chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "prompt": prompt,
            "session_id": sessionId,
            "agent_id": agentId,
            "file_url": fileURL,
            "provider": provider,
            "mode": mode
        ]
        if !subject.isEmpty { body["subject"] = subject }
        if !history.isEmpty { body["history"] = history }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (bytes, _) = try await session.bytes(for: request)
            var pending = ""
            var lastFlush = Date.distantPast

            func flushPending(force: Bool = false) {
                guard !pending.isEmpty else { return }
                let now = Date()
                if !force && now.timeIntervalSince(lastFlush) < 0.1 { return }
                let out = pending
                pending = ""
                lastFlush = now
                onChunk(out)
            }

            for try await line in bytes.lines {
                try Task.checkCancellation()
                let value = line.trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix("data:") else { continue }
                let jsonStr = String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if jsonStr.isEmpty || jsonStr == "[]" || jsonStr == "[DONE]" || jsonStr.hasPrefix("[") { continue }
                guard let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                let eventType = ((obj["event"] as? String) ?? (obj["type"] as? String) ?? "").lowercased()
                let status = (obj["status"] as? String ?? "").lowercased()
                if eventType.contains("thinking") || status.contains("thinking") { continue }

                let subjectName = jsonStringValue(obj["subject"], default: "").isEmpty
                    ? jsonStringValue((obj["content"] as? [String: Any])?["subject"], default: "")
                    : jsonStringValue(obj["subject"], default: "")
                let chunkPreview = extractStreamChunk(from: obj)
                if chunkPreview.isEmpty && (eventType == "subject" || !subjectName.isEmpty) {
                    let name = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        onSubject(name)
                    }
                    continue
                }

                let chunk = chunkPreview
                if !chunk.isEmpty {
                    let isFirst = pending.isEmpty
                    pending += chunk
                    flushPending(force: isFirst)
                }
            }
            flushPending(force: true)
        } catch is CancellationError {
            return
        } catch {
            onChunk("\n\n请求失败，请稍后重试。")
        }
    }

    private func extractStreamChunk(from data: [String: Any]) -> String {
        if let content = data["content"] as? [String: Any] {
            if let answer = content["answer"] as? String, !answer.isEmpty { return sanitizeStreamChunk(answer) }
            if let text = content["content"] as? String, !text.isEmpty { return sanitizeStreamChunk(text) }
        }
        if let answer = data["answer"] as? String, !answer.isEmpty { return sanitizeStreamChunk(answer) }
        if let content = data["content"] as? String, !content.isEmpty, content != "{}" { return sanitizeStreamChunk(content) }
        if let text = data["text"] as? String, !text.isEmpty { return sanitizeStreamChunk(text) }
        if let output = data["output_text"] as? String, !output.isEmpty { return sanitizeStreamChunk(output) }
        if let delta = data["delta"] as? [String: Any] {
            if let answer = delta["answer"] as? String, !answer.isEmpty { return sanitizeStreamChunk(answer) }
            if let content = delta["content"] as? String, !content.isEmpty { return sanitizeStreamChunk(content) }
        }
        if let choices = data["choices"] as? [[String: Any]], let first = choices.first {
            let msg = (first["delta"] as? [String: Any]) ?? (first["message"] as? [String: Any]) ?? [:]
            if let content = msg["content"] as? String, !content.isEmpty { return sanitizeStreamChunk(content) }
            if let answer = msg["answer"] as? String, !answer.isEmpty { return sanitizeStreamChunk(answer) }
        }
        return ""
    }

    private func sanitizeStreamChunk(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("\"status\"") && lower.contains("thinking") { return "" }
        return raw
    }

    // MARK: - 会话历史（对齐 Android cozeStream）
    func fetchConversationList() async -> [ConversationItem] {
        guard let json = await request(url: "\(baseURL)/api/cozeStream/conversationList"),
              let code = jsonIntValue(json["code"]), code == 200,
              let arr = json["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let id = item["id"] as? String ?? (item["id"] as? NSNumber).map({ $0.stringValue }), !id.isEmpty else { return nil }
            let title = item["title"] as? String ?? ""
            let subject = jsonStringValue(item["subjectName"], default: "").isEmpty
                ? jsonStringValue(item["subject"], default: "")
                : jsonStringValue(item["subjectName"], default: "")
            let titleSubject: String = {
                if !subject.isEmpty { return subject }
                if let regex = try? NSRegularExpression(pattern: #"^【([^】]{1,20})】"#),
                   let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: title) {
                    return String(title[range])
                }
                return ""
            }()
            let preview = jsonStringValue(item["preview"], default: "")
            let fileUrl = jsonStringValue(item["fileUrl"], default: "")
            let hasImage = jsonBoolValue(item["hasImage"]) || !fileUrl.isEmpty || preview.contains("[图片]")
            let startedAt = jsonInt64Value(item["startedAt"]) ?? jsonInt64Value(item["started_at"]) ?? 0
            let startedRaw = jsonStringValue(item["startedAt"], default: "")
            return ConversationItem(
                id: id,
                title: title,
                messageCount: jsonIntValue(item["messageCount"]) ?? 0,
                sessionId: jsonStringValue(item["sessionId"], default: ""),
                agentId: jsonIntValue(item["agentId"]) ?? 0,
                subjectName: titleSubject,
                knowledgePoint: jsonStringValue(item["knowledgePoint"], default: "").isEmpty
                    ? jsonStringValue(item["knowledge_point"], default: "")
                    : jsonStringValue(item["knowledgePoint"], default: ""),
                agentName: jsonStringValue(item["agentName"], default: ""),
                startedAt: startedAt,
                startedAtText: startedRaw,
                preview: preview,
                hasImage: hasImage
            )
        }
    }

    func fetchConversationDetail(conversationId: String) async -> ConversationDetailResult {
        guard let json = await postJSON(url: "\(baseURL)/api/cozeStream/conversationDetail",
                                        dict: ["conversation_id": conversationId]),
              let code = jsonIntValue(json["code"]), code == 200 else {
            return ConversationDetailResult(messages: [], sessionId: "", agentId: 0, favoriteId: 0, wrongId: 0)
        }
        let data = json["data"] as? [String: Any] ?? [:]
        let conversation = data["conversation"] as? [String: Any] ?? [:]
        let sessionId = jsonStringValue(conversation["sessionId"], default: "")
        let agentId = jsonIntValue(conversation["agentId"]) ?? 0
        let favoriteId = jsonIntValue(data["favoriteId"]) ?? 0
        let wrongId = jsonIntValue(data["wrongId"]) ?? 0
        let msgArray = data["messages"] as? [[String: Any]] ?? []
        var result: [ChatMessage] = []
        var pendingQuestion = ""
        var pendingImage = ""
        var lastRole = ""
        var lastContent = ""

        for msg in msgArray {
            let senderType = jsonIntValue(msg["senderType"]) ?? 1
            let content = jsonStringValue(msg["content"], default: "")
            let role = senderType == 1 ? "user" : "assistant"
            if role == lastRole, content == lastContent, !content.isEmpty { continue }
            lastRole = role
            lastContent = content
            if senderType == 1 {
                pendingQuestion = content
                pendingImage = normalizeChatImageUrl(parseHistoryMessageImageUrl(from: msg))
                result.append(ChatMessage(
                    role: "user",
                    content: content,
                    imageLocalURL: pendingImage.isEmpty ? nil : pendingImage
                ))
            } else {
                result.append(ChatMessage(
                    role: "assistant",
                    content: content,
                    relatedQuestion: pendingQuestion,
                    relatedImageUrl: pendingImage
                ))
            }
        }
        return ConversationDetailResult(messages: result, sessionId: sessionId, agentId: agentId, favoriteId: favoriteId, wrongId: wrongId)
    }

    func persistConversation(
        sessionId: String,
        agentId: Int,
        prompt: String,
        answer: String,
        fileUrl: String = "",
        mode: String = "答案模式",
        subject: String = ""
    ) async -> Bool {
        var dict: [String: Any] = [
            "session_id": sessionId,
            "agent_id": agentId,
            "prompt": prompt,
            "answer": answer,
            "mode": mode,
            "file_url": fileUrl
        ]
        if !subject.isEmpty { dict["subject"] = subject }
        guard let json = await postJSON(url: "\(baseURL)/api/cozeStream/saveConversation", dict: dict),
              let code = jsonIntValue(json["code"]) else { return false }
        return code == 200
    }

    func deleteConversation(conversationId: String) async -> Bool {
        guard let json = await postJSON(
            url: "\(baseURL)/api/cozeStream/deleteConversation",
            dict: ["conversation_id": conversationId]
        ), let code = jsonIntValue(json["code"]) else { return false }
        return code == 200
    }

    func fetchQaAgentList() async -> QaAgentListResult {
        let fallback = QaAgentListResult(
            agents: [QaAgentItem(id: 1, name: "通义千问", welcomeMessage: "")],
            subjects: [],
            unmatched: [],
            qaConfig: QaChatConfig()
        )
        guard let json = await request(url: "\(baseURL)/api/agents/qaList") else { return fallback }
        let code = jsonIntValue(json["code"]) ?? -1
        guard code == 200 || code == 0 else { return fallback }
        let data = json["data"] as? [String: Any] ?? [:]
        let agentsRaw = data["agents"] as? [[String: Any]] ?? []
        let agents: [QaAgentItem] = agentsRaw.compactMap { item in
            let id = jsonIntValue(item["id"]) ?? 0
            guard id > 0 else { return nil }
            return QaAgentItem(
                id: id,
                name: jsonStringValue(item["name"], default: "通义千问"),
                welcomeMessage: jsonStringValue(item["welcomeMessage"], default: "")
            )
        }
        var config = parseQaChatConfig(data)
        if config.providers.count <= 1, config.modes.count <= 1 {
            if let extra = await fetchQaChatConfig() { config = extra }
        }
        let hintSubjects = parseQaListSubjects(data, key: "subjects")
        let unmatched = parseQaListSubjects(data, key: "unmatched")
        return QaAgentListResult(
            agents: agents.isEmpty ? fallback.agents : agents,
            subjects: hintSubjects,
            unmatched: unmatched,
            qaConfig: config
        )
    }

    func fetchQaChatConfig() async -> QaChatConfig? {
        guard let json = await request(url: "\(baseURL)/api/agents/qaConfig") else { return nil }
        let code = jsonIntValue(json["code"]) ?? -1
        guard code == 200 || code == 0 else { return nil }
        let data = (json["data"] as? [String: Any]) ?? json
        return parseQaChatConfig(data)
    }

    func deleteFavorite(id: Int) async -> Bool {
        guard id > 0,
              let json = await postJSON(url: "\(baseURL)/api/favorite/delete", dict: ["id": id]),
              let code = jsonIntValue(json["code"]) else { return false }
        return code == 0 || code == 200
    }

    func toggleFavorite(
        question: String,
        answer: String,
        imageUrl: String,
        type: String,
        subject: String,
        sessionId: String,
        alreadyActive: Bool,
        existingId: Int
    ) async -> FavoriteToggleResult {
        if alreadyActive, existingId > 0 {
            if await deleteFavorite(id: existingId) {
                return FavoriteToggleResult(ok: true, active: false, id: 0)
            }
        }
        let ok = await addFavorite(
            type: type,
            title: favoriteTitle(question: question, answer: answer, imageUrl: imageUrl, type: type, subject: subject),
            image: imageUrl,
            items: favoriteItems(question: question, answer: answer, type: type),
            sessionId: sessionId,
            subject: subject
        )
        return FavoriteToggleResult(ok: ok, active: ok, id: ok ? 1 : 0)
    }

    private func favoriteTitle(question: String, answer: String, imageUrl: String, type: String, subject: String) -> String {
        var q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if q == "[图片]" { q = type == "1" ? "图片错题" : "图片题目" }
        let base = !q.isEmpty ? q : (imageUrl.isEmpty ? answer : "图片题目")
        let titled = (!subject.isEmpty && !base.contains(subject)) ? "【\(subject)】\(base)" : base
        return String(titled.prefix(50))
    }

    private func favoriteItems(question: String, answer: String, type: String) -> [[String: Any]] {
        var q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if q == "[图片]" { q = type == "1" ? "图片错题" : "图片题目" }
        var items: [[String: Any]] = []
        if !q.isEmpty {
            items.append(["content": q, "content_type": "user", "sort": 0])
        }
        items.append(["content": answer, "content_type": "assistant", "sort": q.isEmpty ? 0 : 1])
        return items
    }

    private func parseQaListSubjects(_ data: [String: Any], key: String) -> [String] {
        var out: [String] = []
        if let arr = data[key] as? [Any] {
            for item in arr {
                if let obj = item as? [String: Any] {
                    let n = jsonStringValue(obj["name"], default: "").trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty, !out.contains(n) { out.append(n) }
                } else {
                    let n = jsonStringValue(item, default: "").trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty, !out.contains(n) { out.append(n) }
                }
            }
        }
        return out
    }

    private func parseQaChatConfig(_ data: [String: Any]) -> QaChatConfig {
        let cfg = (data["qaConfig"] as? [String: Any])
            ?? (data["qa_config"] as? [String: Any])
            ?? (data["providers"] != nil || data["modes"] != nil ? data : nil)
        guard let cfg else { return QaChatConfig() }
        let providers = parseQaChoiceField(cfg, key: "providers", fallbackKey: "qwen", fallbackLabel: "通义千问")
        let modes = parseQaChoiceField(cfg, key: "modes", fallbackKey: "answer", fallbackLabel: "答案模式")
        let defaultProvider = jsonStringValue(cfg["default_provider"], default: "").isEmpty
            ? jsonStringValue(cfg["defaultProvider"], default: providers.first?.key ?? "qwen")
            : jsonStringValue(cfg["default_provider"], default: "qwen")
        let defaultMode = jsonStringValue(cfg["default_mode"], default: "").isEmpty
            ? jsonStringValue(cfg["defaultMode"], default: modes.first?.key ?? "answer")
            : jsonStringValue(cfg["default_mode"], default: "answer")
        var modeProviders: [String: String] = [:]
        let raw = cfg["mode_providers"] ?? cfg["modeProviders"]
        if let obj = raw as? [String: Any] {
            for (k, v) in obj {
                let bound = jsonStringValue(v, default: "").trimmingCharacters(in: .whitespaces)
                if !k.isEmpty, !bound.isEmpty { modeProviders[k] = bound }
            }
        }
        for mode in modes where modeProviders[mode.key] == nil {
            modeProviders[mode.key] = defaultProvider
        }
        return QaChatConfig(
            providers: providers,
            modes: modes,
            defaultProvider: defaultProvider,
            defaultMode: defaultMode,
            modeProviders: modeProviders
        )
    }

    private func parseQaChoiceField(_ parent: [String: Any], key: String, fallbackKey: String, fallbackLabel: String) -> [QaChoice] {
        var out: [String: QaChoice] = [:]
        func add(_ choice: QaChoice?) {
            guard let choice, !choice.key.isEmpty, out[choice.key] == nil else { return }
            out[choice.key] = choice
        }
        if let arr = parent[key] as? [Any] {
            arr.forEach { add(parseQaChoiceItem($0)) }
        } else if let obj = parent[key] as? [String: Any] {
            for (itemKey, value) in obj {
                add(parseQaChoiceItem(value) ?? QaChoice(key: itemKey, label: jsonStringValue(value, default: itemKey)))
            }
        }
        return out.isEmpty ? [QaChoice(key: fallbackKey, label: fallbackLabel)] : Array(out.values)
    }

    private func parseQaChoiceItem(_ raw: Any?) -> QaChoice? {
        if let obj = raw as? [String: Any] {
            let key = jsonStringValue(obj["key"], default: "").isEmpty
                ? jsonStringValue(obj["id"], default: "")
                : jsonStringValue(obj["key"], default: "")
            let label = jsonStringValue(obj["label"], default: "").isEmpty
                ? jsonStringValue(obj["name"], default: key)
                : jsonStringValue(obj["label"], default: key)
            if key.isEmpty { return nil }
            return QaChoice(key: key.trimmingCharacters(in: .whitespaces), label: label)
        }
        if let s = raw as? String, !s.isEmpty {
            return QaChoice(key: s, label: s)
        }
        return nil
    }

    private func parseHistoryMessageImageUrl(from msg: [String: Any]) -> String {
        let keys = ["fileUrl", "file_url", "imageUrl", "image"]
        for key in keys {
            if let value = msg[key] as? String, !value.isEmpty { return value }
        }
        if let coze = msg["cozeResponseData"] as? String ?? msg["coze_response_data"] as? String {
            if let data = coze.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let url = obj["file_url"] as? String, !url.isEmpty {
                return url
            }
        }
        return ""
    }

    private func normalizeChatImageUrl(_ raw: String) -> String {
        let text = normalizeOptionalImage(raw)
        guard !text.isEmpty else { return "" }
        return text.replacingOccurrences(of: "(?<!:)/{2,}", with: "/", options: .regularExpression)
    }

    // MARK: - 工具方法
    private func jsonIntValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func jsonInt64Value(_ value: Any?) -> Int64? {
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    private func jsonBoolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue || n.intValue == 1 }
        if let s = value as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    /// 兼容 API 返回字符串或数字（对齐 Android JSONObject.optString）
    private func jsonStringValue(_ value: Any?, default defaultValue: String = "0") -> String {
        guard let value = value else { return defaultValue }
        if let s = value as? String { return s.isEmpty ? defaultValue : s }
        if let n = value as? NSNumber { return n.stringValue }
        return defaultValue
    }

    private func normalizeOptionalImage(_ raw: String?) -> String {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return "" }
        if text.isEmpty || text.lowercased() == "null" || text.lowercased() == "undefined" || text == "[]" { return "" }
        return text
    }
}
