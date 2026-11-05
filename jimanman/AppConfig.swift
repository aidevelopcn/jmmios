import Foundation
import SwiftUI
import UIKit

/// API 基础配置 - 与 Android 端完全一致
enum ApiConfig {
    /// 全站唯一域名。改这里即可，其余地址都用 path 拼接。
    //static let baseURL = "https://ad.91jmm.com"
    static let baseURL = "https://jmm.aidevelop.cn"

    static func url(_ path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        if path.hasPrefix("/") { return baseURL + path }
        return baseURL + "/" + path
    }

    static let wxAppID = "wx25240f7addf5c344"
    /// 微信 Universal Link，需与开放平台及服务器 apple-app-site-association 配置一致
    static let wxUniversalLink = url("/jimanman/")
    /// 未安装微信时，网页 OAuth 回调 Scheme（需与后端 wxAuthCallback 一致）
    static let wxWebCallbackScheme = "com.gaoshub.jimanman"
    /// 网站应用 AppID（网页 OAuth 兜底，与后端 wxmp.production.AppID 一致）
    static let wxWebAppID = "wxf4107846851b3593"
    static let wxWebAuthCallback = url("/api/user/wxAuthCallback")
}

#if DEBUG
/// 调试登录（对齐 jmmv2 login.uvue testhandleLogin，仅 Debug 包可用）
enum DebugLoginConfig {
    static let testToken = "76347edcaad2ca482c230121afb058e91e8455a2"
    static let testUserId = 1
}
#endif

/// App Store 功能开关
enum AppFeatures {
    /// iOS App Store 版隐藏会员/储值相关入口，避免 Guideline 3.1.1
    static let showMembership = false
    /// 隐藏外部小鹅通课程入口，避免 Guideline 3.1.1
    static let showExternalCourses = false

    /// iOS 暂隐藏微信/Apple 登录，改用手机号登录（不影响 Android 微信登录接口）
    static let showWechatLogin = false
    static let showAppleLogin = false

    static var showRecharge: Bool { showMembership }
}

/// App Store Connect 元数据 URL（须为可打开的独立支持页，勿填官网 SPA 首页）
enum AppStoreURL {
    static let support = ApiConfig.url("/api/article/support")
}

enum SafariOpen {
    static func page(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

/// 用户协议链接
enum AgreementURL {
    static let userAgreement = ApiConfig.url("/api/article/user")
    static let privacyPolicy = ApiConfig.url("/api/article/ysxy")
}

/// 主题颜色
enum AppColors {
    static let primary = Color(hex: "4ECDC4")
    static let primaryLight = Color(hex: "6FE0D8")
    static let primaryDark = Color(hex: "00695A")
    static let background = Color(hex: "F5F7FA")
    static let textPrimary = Color(hex: "1A1F26")
    static let textSecondary = Color(hex: "4B5563")
    static let textMuted = Color(hex: "9CA3AF")
    static let divider = Color(hex: "EEF1F3")
    static let white = Color.white
}
