import SwiftUI

// MARK: - 登录页面（对齐 Android LoginScreen）
struct LoginScreen: View {
    let onBack: () -> Void
    let onLoginSuccess: () -> Void

    @State private var checked = false
    @State private var loading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var loginWatchdog: Task<Void, Never>?
    @State private var loginTask: Task<Void, Never>?
    @State private var loginSession = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("login_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    loginControls
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 16, 32))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                if loading {
                    Color.black.opacity(0.33)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .alert("提示", isPresented: $showError) {
            Button("确定") {}
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            cancelLoginFlow()
        }
    }

    private var loginControls: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let buttonWidth = (geo.size.width - LoginButtonMetrics.spacing) / 2
                HStack(spacing: LoginButtonMetrics.spacing) {
                    SocialLoginButton(
                        title: "Apple 登录",
                        background: Color.black,
                        foreground: .white,
                        action: handleAppleLogin
                    )
                    .frame(width: buttonWidth, height: LoginButtonMetrics.height)

                    SocialLoginButton(
                        title: "微信登录",
                        background: Color(hex: "07C160"),
                        foreground: .white,
                        action: handleWechatLogin
                    )
                    .frame(width: buttonWidth, height: LoginButtonMetrics.height)
                }
                .frame(width: geo.size.width, height: LoginButtonMetrics.height)
            }
            .frame(height: LoginButtonMetrics.height)
            .disabled(loading)
            .opacity(loading ? 0.6 : (checked ? 1 : 0.6))

            Spacer().frame(height: 16)

            HStack(spacing: 8) {
                Button(action: { checked.toggle() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(checked ? AppColors.primaryLight : Color.white)
                            .frame(width: 18, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(checked ? AppColors.primaryLight : Color(hex: "CCCCCC"), lineWidth: 1)
                            )
                        if checked {
                            Text("✓")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                agreementText
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(height: 20)

            Button(action: onBack) {
                Text("返回")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }

    private var agreementText: some View {
        HStack(spacing: 0) {
            Text("阅读并同意")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "333333"))
            Link("《用户协议》", destination: URL(string: AgreementURL.userAgreement)!)
                .font(.system(size: 13))
            Text("与")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "333333"))
            Link("《隐私协议》", destination: URL(string: AgreementURL.privacyPolicy)!)
                .font(.system(size: 13))
        }
    }

    private func handleAppleLogin() {
        guard checked else {
            presentError("请阅读并同意用户协议和隐私协议")
            return
        }

        cancelLoginFlow()
        loading = true
        let session = loginSession
        startApiWatchdog(session: session)

        AppleSignInService.shared.signIn { result in
            Task { @MainActor in
                stopLoginWatchdog()

                guard session == loginSession else { return }

                switch result {
                case .failure(let error):
                    finishLoading()
                    if let appleError = error as? AppleSignInError, case .cancelled = appleError {
                        return
                    }
                    presentError(error.localizedDescription)
                case .success(let credential):
                    startApiWatchdog(session: session)
                    let loginResult = await ApiService.shared.appleLogin(credential: credential)
                    stopLoginWatchdog()

                    guard session == loginSession, !Task.isCancelled else { return }
                    finishLoading()

                    if loginResult.success {
                        ApiService.shared.token = loginResult.token
                        onLoginSuccess()
                    } else {
                        presentError(loginResult.message)
                    }
                }
            }
        }
    }

    private func handleWechatLogin() {
        guard checked else {
            presentError("请阅读并同意用户协议和隐私协议")
            return
        }

        cancelLoginFlow()
        loading = true
        let session = loginSession
        let useWebSource = !WechatLoginBridge.isWxInstalled()
        startLoginWatchdog(session: session)

        WechatLoginBridge.startLogin { code, errCode, errMsg in
            loginTask?.cancel()
            loginTask = Task { @MainActor in
                stopLoginWatchdog()

                guard session == loginSession else { return }

                guard let code, !code.isEmpty else {
                    finishLoading()
                    if errCode == -2 { return }
                    presentError(errMsg.isEmpty ? "微信登录失败(\(errCode))" : errMsg)
                    return
                }

                startApiWatchdog(session: session)
                let result = await ApiService.shared.wxLoginByCode(
                    code: code,
                    source: useWebSource ? "web" : "app"
                )
                stopLoginWatchdog()

                guard session == loginSession, !Task.isCancelled else { return }
                finishLoading()

                if result.success {
                    ApiService.shared.token = result.token
                    onLoginSuccess()
                } else {
                    presentError(result.message)
                }
            }
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func finishLoading() {
        loading = false
    }

    private func cancelLoginFlow() {
        loginSession += 1
        loginTask?.cancel()
        loginTask = nil
        stopLoginWatchdog()
        WechatLoginBridge.cancelPendingLogin()
        AppleSignInService.shared.cancel()
    }

    /// 等待微信授权回调（跳转微信或网页授权阶段）
    private func startLoginWatchdog(session: Int) {
        loginWatchdog?.cancel()
        loginWatchdog = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 90_000_000_000)
            } catch {
                return
            }
            guard session == loginSession, !Task.isCancelled, loading else { return }
            cancelLoginFlow()
            finishLoading()
            presentError("微信登录超时，请重试")
        }
    }

    /// 等待服务端登录接口（网络阶段）
    private func startApiWatchdog(session: Int) {
        loginWatchdog?.cancel()
        loginWatchdog = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 35_000_000_000)
            } catch {
                return
            }
            guard session == loginSession, !Task.isCancelled, loading else { return }
            loginTask?.cancel()
            cancelLoginFlow()
            finishLoading()
            presentError("连接服务器超时，请检查网络后重试")
        }
    }

    private func stopLoginWatchdog() {
        loginWatchdog?.cancel()
        loginWatchdog = nil
    }
}

private enum LoginButtonMetrics {
    static let height: CGFloat = 50
    static let spacing: CGFloat = 12
}

/// 左右等宽、等高的统一登录按钮（满足 App Store 4.8 同等突出要求）
private struct SocialLoginButton: View {
    let title: String
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .multilineTextAlignment(.center)
                .background(background)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
