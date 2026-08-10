import SwiftUI

// MARK: - 账号管理（对齐 Android AccountManageScreen）
struct AccountManageView: View {
    let onBack: () -> Void
    let onLogout: () -> Void
    let onOpenApplyClose: () -> Void

    @State private var showLogoutConfirm = false
    @State private var checkingVersion = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @StateObject private var apiService = ApiService.shared

    private let customerServiceURL = URL(string: "https://work.weixin.qq.com/kfid/kfcb8e8bcd4fd690dae")!

    private enum AccountMenuItem: CaseIterable {
        case customerService, userAgreement, privacyPolicy, clearCache, versionCheck, logout, closeAccount

        var title: String {
            switch self {
            case .customerService: return "联系客服"
            case .userAgreement: return "用户协议"
            case .privacyPolicy: return "隐私协议"
            case .clearCache: return "清除缓存"
            case .versionCheck: return "版本更新"
            case .logout: return "退出登录"
            case .closeAccount: return "注销账号"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            VStack(spacing: 0) {
                ForEach(Array(AccountMenuItem.allCases.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 16)
                    }
                    menuRow(title: item.title) { handleMenu(item) }
                }
            }
            .background(Color.white)

            if checkingVersion {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("检查中...")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "666666"))
                }
                .padding(16)
            }

            Spacer()
        }
        .background(Color.white)
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                apiService.token = nil
                onLogout()
            }
        } message: {
            Text("确定要退出登录吗？")
        }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
    }

    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("账号管理")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color(hex: "2D3748"))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.white)
        .overlay(Divider(), alignment: .bottom)
    }

    private func handleMenu(_ item: AccountMenuItem) {
        switch item {
        case .customerService:
            openURL(customerServiceURL)
        case .userAgreement:
            openURL(URL(string: AgreementURL.userAgreement)!)
        case .privacyPolicy:
            openURL(URL(string: AgreementURL.privacyPolicy)!)
        case .clearCache:
            clearCache()
        case .versionCheck:
            checkVersion()
        case .logout:
            showLogoutConfirm = true
        case .closeAccount:
            onOpenApplyClose()
        }
    }

    private func menuRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "CCCCCC"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                .forEach { try? FileManager.default.removeItem(at: $0) }
        }
        toastMessage = "缓存清理完成"
        showToast = true
    }

    private func checkVersion() {
        checkingVersion = true
        Task {
            let tip = await apiService.checkAppVersion()
            await MainActor.run {
                checkingVersion = false
                toastMessage = tip
                showToast = true
            }
        }
    }
}
