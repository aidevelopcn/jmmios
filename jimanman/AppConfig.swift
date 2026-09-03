import Foundation
import SwiftUI

/// API 基础配置 - 与 Android 端完全一致
enum ApiConfig {
    static let baseURL = "https://ad.91jmm.com"
    static let wxAppID = "wx25240f7addf5c344"
    /// 微信 Universal Link，需与开放平台及服务器 apple-app-site-association 配置一致
    static let wxUniversalLink = "https://ad.91jmm.com/jimanman/"
    /// 未安装微信时，网页 OAuth 回调 Scheme（需与后端 wxAuthCallback 一致）
    static let wxWebCallbackScheme = "com.gaoshub.jimanman"
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

    static var showRecharge: Bool { showMembership }
}

/// 用户协议链接
enum AgreementURL {
    static let userAgreement = "https://ad.91jmm.com/api/article/user"
    static let privacyPolicy = "https://ad.91jmm.com/api/article/ysxy"
}

/// 主题颜色
enum AppColors {
    static let primary = Color(hex: "00AFA4")
    static let primaryLight = Color(hex: "00D7CD")
    static let primaryDark = Color(hex: "007A74")
    static let background = Color(hex: "F5F7FA")
    static let textPrimary = Color(hex: "111111")
    static let textSecondary = Color(hex: "6B7280")
    static let textMuted = Color(hex: "9CA3AF")
    static let divider = Color(hex: "E5E5E5")
    static let white = Color.white
}
