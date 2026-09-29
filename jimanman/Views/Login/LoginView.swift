import SwiftUI
import UIKit

// MARK: - 登录 / 注册（手机号 + 验证码 / 密码）
struct LoginScreen: View {
    let onBack: () -> Void
    let onLoginSuccess: () -> Void

    private enum Mode {
        case login
        case register
    }

    private enum LoginWay {
        case code
        case password
    }

    @State private var mode: Mode = .login
    @State private var loginWay: LoginWay = .code
    @State private var phone = ""
    @State private var verifyCode = ""
    @State private var password = ""
    @State private var checked = false
    @State private var loading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("login_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .onTapGesture { hideKeyboard() }

                VStack {
                    Spacer(minLength: 0)
                    formCard
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 16, 28))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                if loading {
                    Color.black.opacity(0.33).ignoresSafeArea()
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
            countdownTask?.cancel()
        }
    }

    private var formCard: some View {
        VStack(spacing: 14) {
            Text(mode == .login ? "登录绩满满" : "注册账号")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if mode == .login {
                HStack(spacing: 0) {
                    wayTab("验证码登录", selected: loginWay == .code) { loginWay = .code }
                    wayTab("密码登录", selected: loginWay == .password) { loginWay = .password }
                }
                .background(Color(hex: "F3F4F6"))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            fieldRow {
                TextField("请输入手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
            }

            if mode == .register || loginWay == .code {
                HStack(spacing: 8) {
                    fieldRow {
                        TextField("请输入验证码", text: $verifyCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                    Button(action: sendCode) {
                        Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(countdown > 0 ? AppColors.textMuted : .white)
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(countdown > 0 ? Color(hex: "E5E7EB") : AppColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(countdown > 0 || loading)
                    .buttonStyle(.plain)
                }
            }

            if mode == .register || loginWay == .password {
                fieldRow {
                    SecureField(mode == .register ? "设置密码（6-32位）" : "请输入密码", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                }
            }

            HStack(alignment: .top, spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: submit) {
                Text(mode == .login ? "登录" : "注册")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(loading)

            Button(action: switchMode) {
                Text(mode == .login ? "没有账号？立即注册" : "已有账号？去登录")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.primary)
            }
            .buttonStyle(.plain)

            Button(action: onBack) {
                Text("返回")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func wayTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .medium : .regular))
                .foregroundColor(selected ? .white : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? AppColors.primary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func fieldRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(hex: "F8FAFB"))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8)
            )
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private func switchMode() {
        mode = mode == .login ? .register : .login
        verifyCode = ""
        password = ""
    }

    private func sendCode() {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil else {
            presentError("请输入正确的手机号")
            return
        }
        let type = mode == .register ? "member_register" : "member_phone_login"
        loading = true
        Task { @MainActor in
            let result = await ApiService.shared.sendVerifyCode(phone: trimmed, type: type)
            loading = false
            if result.success {
                startCountdown()
            } else {
                presentError(result.message)
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task { @MainActor in
            while countdown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }

    private func submit() {
        guard checked else {
            presentError("请阅读并同意用户协议和隐私协议")
            return
        }
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        guard trimmedPhone.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil else {
            presentError("请输入正确的手机号")
            return
        }

        loading = true
        Task { @MainActor in
            let result: LoginResult
            if mode == .register {
                if verifyCode.trimmingCharacters(in: .whitespaces).isEmpty {
                    loading = false
                    presentError("请输入验证码")
                    return
                }
                if password.count < 6 || password.count > 32 {
                    loading = false
                    presentError("密码长度需为 6-32 位")
                    return
                }
                result = await ApiService.shared.phoneRegister(
                    phone: trimmedPhone,
                    verifyCode: verifyCode.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } else if loginWay == .code {
                if verifyCode.trimmingCharacters(in: .whitespaces).isEmpty {
                    loading = false
                    presentError("请输入验证码")
                    return
                }
                result = await ApiService.shared.phoneLogin(
                    phone: trimmedPhone,
                    verifyCode: verifyCode.trimmingCharacters(in: .whitespaces)
                )
            } else {
                if password.isEmpty {
                    loading = false
                    presentError("请输入密码")
                    return
                }
                result = await ApiService.shared.phoneLogin(
                    phone: trimmedPhone,
                    password: password
                )
            }

            loading = false
            if result.success {
                ApiService.shared.token = result.token
                onLoginSuccess()
            } else {
                presentError(result.message)
            }
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
