import Foundation

/// 网络服务 - 所有API接口与Android端完全一致
class ApiService: ObservableObject {
    static let shared = ApiService()
    private init() {}

    private let session = URLSession.shared
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
    /// 微信 code 只能使用一次，禁止自动重试，避免 "code been used"
    func wxLoginByCode(code: String, source: String = "app") async -> LoginResult {
        if wxLoginInFlightCodes.contains(code) {
            return LoginResult(success: false, token: "", message: "登录处理中，请稍候")
        }
        wxLoginInFlightCodes.insert(code)
        defer { wxLoginInFlightCodes.remove(code) }

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
            if (error as NSError).code == NSURLErrorTimedOut {
                return LoginResult(success: false, token: "", message: "连接服务器超时，请检查网络后重试")
            }
            return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        }
    }

    /// GET /api/user/wechatOauthUrl
    func fetchWechatOauthURL() async -> URL? {
        guard let json = await request(url: "\(baseURL)/api/user/wechatOauthUrl"),
              let code = jsonIntValue(json["code"]), code == 200,
              let data = json["data"] as? [String: Any],
              let urlString = data["url"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    /// POST /api/user/appleLogin
    func appleLogin(credential: AppleSignInCredential) async -> LoginResult {
        let params: [String: String] = [
            "identity_token": credential.identityToken,
            "authorization_code": credential.authorizationCode ?? "",
            "user_identifier": credential.userIdentifier,
            "email": credential.email ?? "",
            "given_name": credential.givenName ?? "",
            "family_name": credential.familyName ?? "",
        ]

        guard let json = await postForm(url: "\(baseURL)/api/user/appleLogin", params: params),
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
                questionText: String(question.prefix(120)),
                answerSummary: String(_answer.prefix(140)),
                imageUrl: image,
                timeText: createTime
            )
        }
    }
    
    /// POST /api/favorite/add
    func addFavorite(type: String, title: String, image: String, items: [[String: Any]]) async -> Bool {
        let dict: [String: Any] = ["type": type, "title": title, "image": image, "items": items]
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
    func streamChat(token: String, prompt: String, sessionId: String, fileURL: String = "",
                    onChunk: @escaping (String) -> Void) async {
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
            "agent_id": 1,
            "mode": "answer"
        ]
        if !fileURL.isEmpty { body["file_url"] = fileURL }
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

                let chunk = extractStreamChunk(from: obj)
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
              let code = json["code"] as? Int, code == 200,
              let arr = json["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let id = item["id"] as? String ?? (item["id"] as? NSNumber).map({ $0.stringValue }), !id.isEmpty else { return nil }
            let count = jsonIntValue(item["messageCount"]) ?? 0
            return ConversationItem(
                id: id,
                title: item["title"] as? String ?? "",
                messageCount: count
            )
        }
    }

    func fetchConversationDetail(conversationId: String) async -> [ChatMessage] {
        guard let json = await postJSON(url: "\(baseURL)/api/cozeStream/conversationDetail",
                                        dict: ["conversation_id": conversationId]),
              let code = json["code"] as? Int, code == 200 else { return [] }
        let msgArray = (json["data"] as? [String: Any])?["messages"] as? [[String: Any]] ?? []
        var result: [ChatMessage] = []
        var pendingQuestion = ""
        var pendingImage = ""

        for msg in msgArray {
            let senderType = msg["senderType"] as? Int ?? 1
            let content = msg["content"] as? String ?? ""
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
        return result
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
