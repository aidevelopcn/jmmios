import Foundation
import UIKit

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
    
    /// 获取Token（写入后通知界面，对齐 Android saveToken）
    var token: String? {
        get { UserDefaults.standard.string(forKey: "jmm_token") }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: "jmm_token")
                AcademicApi.prefetchSubjectRegister()
                AcademicApi.prefetchMyCourses()
            } else {
                UserDefaults.standard.removeObject(forKey: "jmm_token")
                AcademicApi.clearSubjectRegisterCache()
                MyCoursesCache.clear()
            }
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    
    /// 通用请求方法
    private func request(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async -> [String: Any]? {
        guard let url = URL(string: url) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval ?? timeout
        
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
    /// GET /api/index/index。失败返回 nil，避免把已有轮播图清空。
    func fetchBannerUrls() async -> [String]? {
        guard let json = await request(url: "\(baseURL)/api/index/index"),
              let code = json["code"] as? Int, code == 200 else { return nil }
        guard let data = json["data"] as? [String: Any],
              let adList = data["ad_list1"] as? [[String: Any]] else { return nil }
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
    func sendVerifyCode(phone: String, type: String, countryCode: String = "86") async -> (success: Bool, message: String) {
        guard let json = await postForm(url: "\(baseURL)/api/user/sendVerifyCode", params: [
            "phone": phone,
            "type": type,
            "country_code": countryCode
        ]), let statusCode = jsonIntValue(json["code"]) else {
            return (false, "网络错误，请稍后重试")
        }
        if statusCode == 200 {
            return (true, json["msg"] as? String ?? "验证码已发送")
        }
        return (false, json["msg"] as? String ?? "发送失败")
    }

    /// POST /api/user/phoneLogin
    func phoneLogin(phone: String, password: String = "", verifyCode: String = "", countryCode: String = "86") async -> LoginResult {
        var params = ["phone": phone, "country_code": countryCode]
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

    /// POST /api/user/forgetPassword
    func forgetPassword(phone: String, verifyCode: String, password: String, countryCode: String = "86") async -> (success: Bool, message: String) {
        guard let json = await postForm(url: "\(baseURL)/api/user/forgetPassword", params: [
            "phone": phone,
            "verify_code": verifyCode,
            "password": password,
            "country_code": countryCode
        ]), let statusCode = jsonIntValue(json["code"]) else {
            return (false, "网络错误，请稍后重试")
        }
        let message = json["msg"] as? String ?? (statusCode == 200 ? "密码已重置，请用新密码登录" : "重置失败")
        return (statusCode == 200, message)
    }

    private func parseLoginJSON(_ json: [String: Any]?) -> LoginResult {
        guard let json, let statusCode = jsonIntValue(json["code"]) else {
            return LoginResult(success: false, token: "", message: "网络错误，请稍后重试")
        }
        if statusCode == 200 {
            let token = (json["data"] as? [String: Any])?["token"] as? String ?? ""
            if !token.isEmpty { self.token = token }
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
    func fetchUserInfoData() async -> [String: Any]? {
        guard let json = await request(url: "\(baseURL)/api/user/getInfo"),
              let code = json["code"] as? Int, code == 200 else { return nil }
        return json["data"] as? [String: Any]
    }

    func fetchUserProfile() async -> UserProfile? {
        guard let data = await fetchUserInfoData() else { return nil }
        let yearRaw = jsonStringValue(data["schoolyear"], default: "")
        let year = (Int(yearRaw) ?? 0) >= 2023 ? yearRaw : ""
        return UserProfile(
            id: data["id"] as? Int ?? 0,
            nickname: jsonStringValue(data["nickname"], default: ""),
            avatarUrl: jsonStringValue(data["avatarUrl"], default: ""),
            isVip: jsonBoolValue(data["is_vip"]),
            vipTime: jsonStringValue(data["vip_expire_time_text"], default: ""),
            school: jsonStringValue(data["school"], default: ""),
            major: jsonStringValue(data["major"], default: ""),
            schoolYear: year,
            invitationCode: jsonStringValue(data["invitation_code"], default: ""),
            isStudent: jsonBoolValue(data["is_student"])
        )
    }

    /// POST /api/feedback/submit
    func submitFeedback(content: String, contact: String, images: [String]) async -> Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let platform = "iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let imagesJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: images),
           let text = String(data: data, encoding: .utf8) {
            imagesJSON = text
        } else {
            imagesJSON = "[]"
        }
        guard let json = await postForm(url: "\(baseURL)/api/feedback/submit", params: [
            "content": content,
            "contact": contact,
            "images": imagesJSON,
            "app_version": version,
            "platform": platform
        ]), let code = json["code"] as? Int else { return false }
        return code == 0 || code == 200
    }

    /// POST /api/cozeStream/setConversationSubject
    func setConversationSubject(sessionId: String, subject: String) async -> Bool {
        guard let json = await postJSON(url: "\(baseURL)/api/cozeStream/setConversationSubject", dict: [
            "session_id": sessionId,
            "subject": subject
        ]), let code = json["code"] as? Int else { return false }
        return code == 0 || code == 200
    }

    func fetchAccountAuth() async -> (phone: String, parentPhone: String, passwordSet: Bool) {
        guard let json = await request(url: "\(baseURL)/api/user/getInfo"),
              let code = json["code"] as? Int, code == 200,
              let data = json["data"] as? [String: Any] else {
            return ("", "", true)
        }
        let phone = data["phone"] as? String ?? ""
        let parent = data["parent_phone"] as? String ?? ""
        let passwordSet: Bool
        if let n = data["password_set"] as? Int {
            passwordSet = n == 1
        } else if let n = data["password_set"] as? NSNumber {
            passwordSet = n.intValue == 1
        } else {
            passwordSet = true
        }
        return (phone, parent, passwordSet)
    }

    func bindPhone(phone: String, verifyCode: String = "") async -> (success: Bool, message: String, token: String) {
        var params = ["phone": phone]
        if !verifyCode.isEmpty { params["verify_code"] = verifyCode }
        guard let json = await postForm(url: "\(baseURL)/api/user/bindPhone", params: params),
              let statusCode = jsonIntValue(json["code"]) else {
            return (false, "网络错误，请稍后重试", "")
        }
        let message = json["msg"] as? String ?? (statusCode == 200 ? "绑定成功" : "绑定失败")
        let token = (json["data"] as? [String: Any])?["token"] as? String ?? ""
        return (statusCode == 200, message, token)
    }

    func changePassword(oldPassword: String, verifyCode: String, newPassword: String) async -> (success: Bool, message: String) {
        var params = ["new_password": newPassword]
        if !verifyCode.isEmpty { params["verify_code"] = verifyCode }
        if !oldPassword.isEmpty { params["old_password"] = oldPassword }
        guard let json = await postForm(url: "\(baseURL)/api/user/changePassword", params: params),
              let statusCode = jsonIntValue(json["code"]) else {
            return (false, "网络错误，请稍后重试")
        }
        return (statusCode == 200, json["msg"] as? String ?? (statusCode == 200 ? "修改成功" : "修改失败"))
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
        } else if let flag = data["academic_assessment_locked"] as? String {
            locked = flag == "1" || flag.lowercased() == "true" || flag == "已确认"
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
        await updateUserInfoDetailed(params: params).ok
    }

    func updateUserInfoDetailed(params: [String: String]) async -> (ok: Bool, message: String) {
        guard let json = await postForm(url: "\(baseURL)/api/user/updateInfo", params: params) else {
            return (false, "网络异常，请稍后重试")
        }
        let code = json["code"] as? Int ?? -1
        let msg = jsonStringValue(json["msg"], default: "")
        if code == 0 || code == 200 {
            return (true, msg.isEmpty ? "保存成功" : msg)
        }
        return (false, msg.isEmpty ? "保存失败" : msg)
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
        await uploadFileMeta(imageData: imageData, fileName: fileName, mimeType: mimeType)?.url
    }

    func uploadFileMeta(imageData: Data, fileName: String, mimeType: String) async -> UploadedImageMeta? {
        let boundary = "----JMMBoundary\(Int(Date().timeIntervalSince1970 * 1000))"
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        guard let json = await request(url: "\(baseURL)/api/index/upload", method: "POST",
                                       headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                                       body: body,
                                       timeoutInterval: 120),
              let code = json["code"] as? Int, code == 200,
              let data = json["data"] as? [String: Any] else { return nil }
        let url = data["filepath"] as? String ?? ""
        guard !url.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy-MM-dd"
        let now = fmt.string(from: Date())
        let expires = fmt.string(from: Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date())
        return UploadedImageMeta(
            fileId: jsonIntValue(data["id"]) ?? 0,
            url: url,
            name: data["name"] as? String ?? fileName,
            uploadedAt: now,
            expiresAt: expires
        )
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
    /// GET /api/favorite/list?brief=1
    func fetchFavoriteRecords(type: String, page: Int = 1, limit: Int = 40) async -> [AskRecordItem] {
        guard let json = await request(url: "\(baseURL)/api/favorite/list?page=\(page)&limit=\(limit)&type=\(type)&keyword=&brief=1"),
              let code = json["code"] as? Int, code == 200 else { return [] }
        guard let data = json["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] ?? (json["data"] as? [[String: Any]]) else { return [] }
        let briefResponse = list.first.map { $0["question_preview"] != nil || $0["answer_preview"] != nil } ?? false
        return list.compactMap { parseFavoriteItem($0, brief: briefResponse) }
    }

    /// GET /api/favorite/detail?id=
    func fetchFavoriteDetail(id: String) async -> AskRecordItem? {
        guard let numeric = Int(id), numeric > 0 else { return nil }
        guard let json = await request(url: "\(baseURL)/api/favorite/detail?id=\(numeric)"),
              let code = json["code"] as? Int, code == 200,
              let data = json["data"] as? [String: Any] else { return nil }
        return parseFavoriteItem(data, brief: false)
    }

    private func parseFavoriteItem(_ item: [String: Any], brief: Bool) -> AskRecordItem? {
        let title = item["title"] as? String ?? ""
        let createTime = item["create_time"] as? String ?? item["update_time"] as? String ?? ""
        var image = normalizeOptionalImage(item["image"] as? String)
        let contentPreview = item["content_preview"] as? String ?? ""
        let itemsArray = item["items"] as? [[String: Any]] ?? []
        var question = brief ? ((item["question_preview"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
        var answer = brief ? ((item["answer_preview"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
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
            if answer.isEmpty && contentType == "assistant" {
                answer = subContent
            }
        }
        if question.isEmpty { question = title.isEmpty ? contentPreview : title }
        let subject = {
            let raw = (item["subject"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { return raw }
            if let match = title.range(of: #"【([^】]+)】"#, options: .regularExpression) {
                let inner = title[match].dropFirst().dropLast()
                return String(inner)
            }
            return ""
        }()
        func cleanId(_ raw: String) -> String {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasSuffix(".0") { value = String(value.dropLast(2)) }
            if value.isEmpty || value == "0" || value.lowercased() == "null" { return "" }
            return value
        }
        return AskRecordItem(
            id: {
                let raw = jsonStringValue(item["id"], default: "")
                return raw.isEmpty ? UUID().uuidString : raw
            }(),
            title: title,
            questionText: question,
            answerSummary: String(answer.prefix(140)),
            answerText: brief ? "" : answer,
            imageUrl: image,
            timeText: createTime,
            subjectName: subject,
            knowledgePoint: (item["knowledgePoint"] as? String ?? item["knowledge_point"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            conversationId: cleanId(jsonStringValue(item["conversation_id"], default: "")),
            sessionId: cleanId(item["session_id"] as? String ?? ""),
            mastered: jsonIntValue(item["mastered"]) == 1 || jsonBoolValue(item["mastered"]),
            previewOnly: brief
        )
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

    /// POST /api/favorite/master 错题本标记已掌握 / 撤销
    func setFavoriteMastered(id: Int, mastered: Bool) async -> (ok: Bool, message: String) {
        guard id > 0 else { return (false, "记录 ID 无效") }
        guard let json = await postJSON(url: "\(baseURL)/api/favorite/master", dict: [
            "id": id,
            "mastered": mastered ? 1 : 0
        ]) else {
            return (false, "网络异常，请检查网络后重试")
        }
        let code = json["code"] as? Int ?? -1
        let msg = jsonStringValue(json["msg"], default: "")
        if code == 0 || code == 200 {
            return (true, msg)
        }
        return (false, msg.isEmpty ? "操作失败，请稍后重试" : msg)
    }

    /// POST /api/favorite/setSubject 错题/收藏归类
    func setFavoriteSubject(id: Int, subject: String) async -> (ok: Bool, message: String, subject: String) {
        guard id > 0 else { return (false, "记录 ID 无效", "") }
        guard let json = await postJSON(url: "\(baseURL)/api/favorite/setSubject", dict: [
            "id": id,
            "subject": subject
        ]) else {
            return (false, "网络异常，请稍后重试", "")
        }
        let code = json["code"] as? Int ?? -1
        let msg = jsonStringValue(json["msg"], default: "")
        if code == 0 || code == 200 {
            let data = json["data"] as? [String: Any]
            let stored = jsonStringValue(data?["subject"], default: subject)
            return (true, msg, stored)
        }
        return (false, msg.isEmpty ? "归类失败，请稍后重试" : msg, "")
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
        onSubject: @escaping @MainActor (String) -> Void = { _ in },
        onNewSubject: @escaping @MainActor (String) -> Void = { _ in },
        onChunk: @escaping @MainActor (String) -> Void
    ) async {
        guard let url = URL(string: "\(baseURL)/api/cozeStream/chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
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

        let client = SSEByteClient()
        var pending = ""
        var lastFlush = Date.distantPast
        var receivedContentLength = 0
        var lastEvent = ""
        var statusCode = 0

        func flushPending(force: Bool = false) async {
            guard !pending.isEmpty else { return }
            let now = Date()
            if !force && now.timeIntervalSince(lastFlush) < 0.05 { return }
            let out = pending
            pending = ""
            lastFlush = now
            await MainActor.run { onChunk(out) }
        }

        func handleLine(_ line: String) async {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                lastEvent = ""
                return
            }
            if value.hasPrefix("event:") {
                lastEvent = String(value.dropFirst(6)).trimmingCharacters(in: .whitespaces).lowercased()
                return
            }
            guard value.hasPrefix("data:") else { return }
            let jsonStr = String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if jsonStr.isEmpty || jsonStr == "[]" || jsonStr == "[DONE]" || jsonStr.hasPrefix("[") { return }
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let eventType = ((obj["event"] as? String) ?? (obj["type"] as? String) ?? lastEvent).lowercased()
            let status = (obj["status"] as? String ?? "").lowercased()
            if eventType.contains("thinking") || status.contains("thinking") { return }

            let subjectName = jsonStringValue(obj["subject"], default: "").isEmpty
                ? jsonStringValue((obj["content"] as? [String: Any])?["subject"], default: "")
                : jsonStringValue(obj["subject"], default: "")
            let hasAnswerPayload = obj["content"] is [String: Any] || obj["answer"] != nil
            let chunkPreview = extractStreamChunk(from: obj)
            if chunkPreview.isEmpty && !hasAnswerPayload && (eventType == "subject" || !subjectName.isEmpty) {
                let name = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    await MainActor.run {
                        if streamFlagTrue(obj["is_new"]) {
                            onNewSubject(name)
                        } else {
                            onSubject(name)
                        }
                    }
                }
                lastEvent = ""
                return
            }

            if !chunkPreview.isEmpty {
                if receivedContentLength > 0 && QaHelpers.isStreamErrorChunk(chunkPreview) {
                    lastEvent = ""
                    return
                }
                let isFirst = pending.isEmpty
                pending += chunkPreview
                receivedContentLength += chunkPreview.count
                await flushPending(force: isFirst)
            } else if eventType == "error" && receivedContentLength == 0 {
                let err = jsonStringValue(obj["message"], default: "").isEmpty
                    ? jsonStringValue(obj["msg"], default: "")
                    : jsonStringValue(obj["message"], default: "")
                if !err.isEmpty && !QaHelpers.isStreamErrorChunk(err) {
                    pending += err
                    receivedContentLength += err.count
                    await flushPending(force: true)
                }
            }
            lastEvent = ""
        }

        let outcome = await withTaskCancellationHandler {
            await client.start(request) { line in
                await handleLine(line)
            }
        } onCancel: {
            client.cancel()
        }

        if Task.isCancelled { return }
        await flushPending(force: true)
        statusCode = outcome.status
        if let error = outcome.error, (error as NSError).code == NSURLErrorCancelled {
            return
        }
        if receivedContentLength == 0 {
            let fallback: String
            if outcome.error != nil {
                fallback = "未收到回复，请确认网络正常或稍后重试"
            } else if (200...299).contains(statusCode) {
                fallback = "答疑服务已连接，但没有返回内容，请再试一次"
            } else if statusCode > 0 {
                fallback = "答疑服务异常(\(statusCode))，请稍后重试"
            } else {
                fallback = "未收到回复，请确认网络正常或稍后重试"
            }
            await MainActor.run { onChunk(fallback) }
        }
    }

    private func streamFlagTrue(_ raw: Any?) -> Bool {
        if let value = raw as? Bool { return value }
        if let value = raw as? Int { return value != 0 }
        if let value = raw as? String {
            let n = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return n == "1" || n == "true" || n == "yes"
        }
        return false
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
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return raw }
        let lower = text.lowercased()
        if ["thinking", "thinking...", "thinking…", "思考中", "思考中..."].contains(lower) { return "" }
        if text.hasPrefix("{"), text.hasSuffix("}"),
           let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let nested = jsonStringValue(obj["answer"], default: "").isEmpty
                ? (jsonStringValue(obj["content"], default: "").isEmpty
                   ? jsonStringValue(obj["text"], default: "")
                   : jsonStringValue(obj["content"], default: ""))
                : jsonStringValue(obj["answer"], default: "")
            if !nested.isEmpty { return nested }
        }
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
            let qaMode = jsonStringValue(msg["mode"], default: "答案模式")
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
                    relatedImageUrl: pendingImage,
                    qaMode: qaMode.isEmpty ? "答案模式" : qaMode,
                    favoriteId: favoriteId,
                    wrongId: wrongId
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
        if config.modes.count <= 1 || config.providers.count <= 1 {
            if let extra = await fetchQaChatConfig() { config = extra }
        }
        if config.modes.count <= 1 {
            config.modes = QaChatConfig.defaultModes
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
        var out: [QaChoice] = []
        var seen = Set<String>()
        func add(_ choice: QaChoice?) {
            guard let choice, !choice.key.isEmpty, !seen.contains(choice.key) else { return }
            seen.insert(choice.key)
            out.append(choice)
        }
        if let arr = parent[key] as? [Any] {
            arr.forEach { add(parseQaChoiceItem($0)) }
        } else if let obj = parent[key] as? [String: Any] {
            for (itemKey, value) in obj {
                add(parseQaChoiceItem(value) ?? QaChoice(key: itemKey, label: jsonStringValue(value, default: itemKey)))
            }
        }
        if out.isEmpty {
            if key == "modes" { return QaChatConfig.defaultModes }
            return [QaChoice(key: fallbackKey, label: fallbackLabel)]
        }
        return out
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

/// 按到达字节立刻拆 SSE 行，避免 URLSession.bytes 等到整段缓冲才出第一句。
private final class SSEByteClient: NSObject, URLSessionDataDelegate {
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var statusCode = 0
    private var finishedError: Error?
    private var lineBox: AsyncStream<String>.Continuation?
    private var finished = false

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "jmm.sse"
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    func start(_ request: URLRequest, onLine: @escaping (String) async -> Void) async -> (status: Int, error: Error?) {
        let lines = AsyncStream<String> { continuation in
            self.lineBox = continuation
            let task = self.session.dataTask(with: request)
            self.task = task
            task.resume()
        }
        for await line in lines {
            if Task.isCancelled {
                cancel()
                break
            }
            await onLine(line)
        }
        return (statusCode, finishedError)
    }

    func cancel() {
        task?.cancel()
        finish(URLError(.cancelled))
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        finishedError = error
        lineBox?.finish()
        lineBox = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        let newline = Data([0x0A])
        while let range = buffer.range(of: newline) {
            let piece = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            var line = String(data: piece, encoding: .utf8) ?? ""
            if line.hasSuffix("\r") { line.removeLast() }
            lineBox?.yield(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !buffer.isEmpty {
            var line = String(data: buffer, encoding: .utf8) ?? ""
            if line.hasSuffix("\r") { line.removeLast() }
            if !line.isEmpty { lineBox?.yield(line) }
            buffer.removeAll()
        }
        finish(error)
    }
}
