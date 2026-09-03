import AuthenticationServices
import Foundation
import UIKit

/// 微信登录/支付桥接，逻辑对齐 Android WechatLoginBridge
final class WechatLoginBridge: NSObject, WXApiDelegate {
    static let shared = WechatLoginBridge()

    private var loginCallback: ((String?, Int, String) -> Void)?
    private var payCallback: ((Int, String) -> Void)?
    private var deliveredAuthCodes = Set<String>()
    private var webAuthSession: ASWebAuthenticationSession?
    private var webAuthContextProvider = WebAuthContextProvider()

    private override init() {
        super.init()
    }

    static func registerApp() {
        WXApi.registerApp(ApiConfig.wxAppID, universalLink: ApiConfig.wxUniversalLink)
    }

    static func isWxInstalled() -> Bool {
        WXApi.isWXAppInstalled()
    }

    /// 统一处理 URL Scheme 回调（AppDelegate + SwiftUI 均可调用）
    @discardableResult
    static func handleOpenURL(_ url: URL) -> Bool {
        WXApi.handleOpen(url, delegate: shared)
    }

    /// 统一处理 Universal Link 回调
    @discardableResult
    static func handleUniversalLink(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              userActivity.webpageURL != nil else { return false }
        return WXApi.handleOpenUniversalLink(userActivity, delegate: shared)
    }

    static func cancelPendingLogin() {
        shared.loginCallback = nil
        shared.webAuthSession?.cancel()
        shared.webAuthSession = nil
    }

    static func startLogin(result: @escaping (String?, Int, String) -> Void) {
        shared.deliveredAuthCodes.removeAll()
        shared.loginCallback = result

        if !isWxInstalled() {
            startWebLogin(result: result)
            return
        }

        guard let rootVC = topViewController() else {
            result(nil, -1, "无法获取当前页面")
            return
        }

        let req = SendAuthReq()
        req.scope = "snsapi_userinfo"
        req.state = "ios_wechat_login"

        WXApi.sendAuthReq(req, viewController: rootVC, delegate: shared) { success in
            if !success {
                DispatchQueue.main.async {
                    shared.loginCallback?(nil, -1, "调起微信失败")
                    shared.loginCallback = nil
                }
            }
        }
    }

    /// 未安装微信时，通过 ASWebAuthenticationSession 完成网页授权（Guideline 4.2.3）
    static func startWebLogin(result: @escaping (String?, Int, String) -> Void) {
        Task { @MainActor in
            guard let oauthURL = await ApiService.shared.fetchWechatOauthURL() else {
                result(nil, -1, "无法获取微信登录地址")
                return
            }

            shared.webAuthSession?.cancel()
            let session = ASWebAuthenticationSession(
                url: oauthURL,
                callbackURLScheme: ApiConfig.wxWebCallbackScheme
            ) { callbackURL, error in
                shared.webAuthSession = nil
                let callback = shared.loginCallback
                shared.loginCallback = nil

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    DispatchQueue.main.async {
                        callback?(nil, -2, "用户取消授权")
                    }
                    return
                }

                if let error {
                    DispatchQueue.main.async {
                        callback?(nil, -1, error.localizedDescription)
                    }
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      !code.isEmpty else {
                    let message = callbackURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "message" })?.value } ?? "微信授权失败"
                    DispatchQueue.main.async {
                        callback?(nil, -1, message)
                    }
                    return
                }

                DispatchQueue.main.async {
                    callback?(code, 0, "success")
                }
            }

            session.presentationContextProvider = shared.webAuthContextProvider
            session.prefersEphemeralWebBrowserSession = false
            shared.webAuthSession = session

            if !session.start() {
                shared.loginCallback = nil
                result(nil, -1, "无法打开微信登录页面")
            }
        }
    }

    static func startPay(params: WechatPayParams, result: @escaping (Int, String) -> Void) -> Bool {
        guard isWxInstalled() else {
            result(-1, "请先安装微信")
            return false
        }

        shared.payCallback = result

        let req = PayReq()
        req.partnerId = params.partnerId
        req.prepayId = params.prepayId
        req.nonceStr = params.nonceStr
        req.timeStamp = UInt32(params.timeStamp) ?? 0
        req.sign = params.sign
        req.package = params.packageValue

        WXApi.send(req) { success in
            if !success {
                DispatchQueue.main.async {
                    shared.payCallback?(Int(WXErrCodeCommon.rawValue), "调起微信支付失败")
                    shared.payCallback = nil
                }
            }
        }
        return true
    }

    func onResp(_ resp: BaseResp) {
        if let authResp = resp as? SendAuthResp {
            let callback = loginCallback
            loginCallback = nil

            switch authResp.errCode {
            case WXSuccess.rawValue:
                guard let code = authResp.code, !code.isEmpty else {
                    dispatchLogin(callback: callback, code: nil, errCode: -4, errMsg: "微信授权码为空")
                    return
                }
                // 防止 URL Scheme + Universal Link 双通道重复回调，导致 code 被用两次
                guard !deliveredAuthCodes.contains(code) else {
                    print("WeChat auth duplicate ignored: \(code.prefix(8))...")
                    return
                }
                deliveredAuthCodes.insert(code)
                dispatchLogin(callback: callback, code: code, errCode: 0, errMsg: "success")
            case WXErrCodeUserCancel.rawValue:
                dispatchLogin(callback: callback, code: nil, errCode: -2, errMsg: "用户取消授权")
            case WXErrCodeAuthDeny.rawValue:
                dispatchLogin(callback: callback, code: nil, errCode: -3, errMsg: "用户拒绝授权")
            default:
                dispatchLogin(callback: callback, code: nil, errCode: Int(authResp.errCode), errMsg: authResp.errStr)
            }
            return
        }

        if let payResp = resp as? PayResp {
            let callback = payCallback
            payCallback = nil
            DispatchQueue.main.async {
                switch payResp.errCode {
                case WXSuccess.rawValue:
                    callback?(0, "支付成功")
                case WXErrCodeUserCancel.rawValue:
                    callback?(-2, "支付已取消")
                default:
                    callback?(Int(payResp.errCode), payResp.errStr)
                }
            }
        }
    }

    private func dispatchLogin(callback: ((String?, Int, String) -> Void)?, code: String?, errCode: Int, errMsg: String) {
        DispatchQueue.main.async {
            callback?(code, errCode, errMsg)
        }
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
