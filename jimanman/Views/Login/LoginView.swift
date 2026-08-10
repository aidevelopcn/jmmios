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
        ZStack {
            Image("login_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Button(action: handleLogin) {
                    Image("wxbtn")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 235, height: 50)
                }
                .disabled(loading)
                .opacity(loading ? 0.6 : (checked ? 1 : 0.6))

                #if DEBUG
                Spacer().frame(height: 12)

                Button(action: handleTestLogin) {
                    Text("测试登录")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 235, height: 44)
                        .background(AppColors.primaryLight)
                        .cornerRadius(8)
                }
                .disabled(loading)
                .opacity(loading ? 0.6 : (checked ? 1 : 0.6))
                #endif

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

                Spacer().frame(height: 20)

                Button(action: onBack) {
                    Text("返回")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.primary)
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 40)
            }

            if loading {
                Color.black.opacity(0.33)
                    .ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
        .alert("提示", isPresented: $showError) {
            Button("确定") {}
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            cancelLoginFlow()
        }
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

    private func handleLogin() {
        guard checked else {
            presentError("请阅读并同意用户协议和隐私协议")
            return
        }

        guard WechatLoginBridge.isWxInstalled() else {
            presentError("请先安装微信")
            return
        }

        cancelLoginFlow()
        loading = true
        let session = loginSession
        startLoginWatchdog(session: session)

        WechatLoginBridge.startLogin { code, errCode, errMsg in
            loginTask?.cancel()
            loginTask = Task { @MainActor in
                stopLoginWatchdog()

                guard session == loginSession else { return }

                guard let code, !code.isEmpty else {
                    finishLoading()
                    presentError(errMsg.isEmpty ? "微信登录失败(\(errCode))" : errMsg)
                    return
                }

                startApiWatchdog(session: session)
                let result = await ApiService.shared.wxLoginByCode(code: code)
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
    }

    /// 等待微信授权回调（跳转微信阶段）
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

    #if DEBUG
    private func handleTestLogin() {
        guard checked else {
            presentError("请阅读并同意用户协议和隐私协议")
            return
        }
        ApiService.shared.token = DebugLoginConfig.testToken
        UserDefaults.standard.set(DebugLoginConfig.testUserId, forKey: "jmm_user_id")
        onLoginSuccess()
    }
    #endif
}
