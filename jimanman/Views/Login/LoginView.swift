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
        case password
        case code
    }

    @State private var mode: Mode = .login
    @State private var loginWay: LoginWay = .password
    @State private var phone = ""
    @State private var verifyCode = ""
    @State private var password = ""
    @State private var checked = false
    @State private var loading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @FocusState private var focusedField: LoginField?

    private enum LoginField {
        case phone, code, password
    }

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    formCard
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay {
            if loading {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            }
        }
        .alert("提示", isPresented: $showError) {
            Button("确定") {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: loginWay) { _ in
            verifyCode = ""
            password = ""
        }
        .onDisappear {
            countdownTask?.cancel()
        }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Text("绩满满")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text(mode == .login ? "用手机号登录，继续学习" : "注册账号，开启学习")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.88))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(height: 188)
    }

    private var formCard: some View {
        VStack(spacing: 16) {
            if mode == .login {
                HStack(spacing: 0) {
                    wayTab("密码登录", selected: loginWay == .password) { loginWay = .password }
                    wayTab("验证码登录", selected: loginWay == .code) { loginWay = .code }
                }
                .background(Color(hex: "EEF2F6"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            labeledField("手机号") {
                TextField("请输入手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($focusedField, equals: .phone)
            }

            if mode == .register || loginWay == .code {
                labeledField("验证码") {
                    HStack(spacing: 8) {
                        TextField("请输入验证码", text: $verifyCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .code)
                        Button(action: sendCode) {
                            Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(countdown > 0 ? AppColors.textMuted : AppColors.primary)
                                .padding(.horizontal, 4)
                        }
                        .disabled(countdown > 0 || loading)
                        .buttonStyle(.plain)
                    }
                }
            }

            if mode == .register || loginWay == .password {
                labeledField(mode == .register ? "设置密码" : "密码") {
                    SecureField(mode == .register ? "6-32 位密码" : "请输入密码", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Button(action: { checked.toggle() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(checked ? AppColors.primary : Color.white)
                            .frame(width: 18, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(checked ? AppColors.primary : Color(hex: "CCCCCC"), lineWidth: 1)
                            )
                        if checked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                agreementText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)

            Button(action: submit) {
                Text(mode == .login ? "登录" : "注册")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(loading)
            .padding(.top, 4)

            Button(action: switchMode) {
                Text(mode == .login ? "没有账号？立即注册" : "已有账号？去登录")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func wayTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? AppColors.primary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
            content()
                .font(.system(size: 16))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private func switchMode() {
        mode = mode == .login ? .register : .login
        verifyCode = ""
        password = ""
        loginWay = .password
        hideKeyboard()
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
