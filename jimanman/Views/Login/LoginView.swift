import SwiftUI
import UIKit

struct LoginScreen: View {
    var onBack: () -> Void
    var onLoginSuccess: () -> Void

    var body: some View {
        LoginView(onDismiss: onBack, onLoginSuccess: onLoginSuccess)
    }
}

private enum LoginDialCode: String, CaseIterable, Identifiable {
    case china = "86"
    case usa = "1"

    var id: String { rawValue }
    var prefix: String { "+\(rawValue)" }
    var title: String {
        switch self {
        case .china: return "中国 +86"
        case .usa: return "美国 +1"
        }
    }
    var maxDigits: Int {
        switch self {
        case .china: return 11
        case .usa: return 10
        }
    }
    var errorText: String {
        switch self {
        case .china: return "请输入正确的 11 位手机号"
        case .usa: return "请输入正确的 10 位美国手机号"
        }
    }

    func isValid(_ value: String) -> Bool {
        switch self {
        case .china:
            return value.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil
        case .usa:
            return value.range(of: "^[2-9]\\d{9}$", options: .regularExpression) != nil
        }
    }
}

/// 对齐 Android LoginPoster：薄荷底 + login_bg 顶图 + 白卡片。
/// iOS 不展示微信登录，默认手机号 + 验证码；账号密码为备选。
struct LoginView: View {
    var onDismiss: () -> Void
    var onLoginSuccess: () -> Void

    private enum LoginMode: String {
        case code
        case password
    }

    @State private var loginMode: LoginMode = .code
    @State private var phone = ""
    @State private var account = ""
    @State private var verifyCode = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var agreed = false
    @State private var showAgreeHint = false
    @State private var phoneError = ""
    @State private var codeError = ""
    @State private var accountError = ""
    @State private var passwordError = ""
    @State private var isLoading = false
    @State private var countdown = 0
    @State private var timer: Timer?
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var showReset = false
    @State private var dialCode: LoginDialCode = .china

    private let mint = Color(hex: "E7F2EA")
    private let ink = Color(hex: "17181A")
    private let teal = Color(hex: "11B5AC")
    private let posterLink = Color(hex: "5661E0")
    private let fieldBorder = Color(hex: "768A80")

    var body: some View {
        ZStack(alignment: .top) {
            mint.ignoresSafeArea()

            Image("login_bg")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                modeChip("验证码登录", active: loginMode == .code) {
                                    loginMode = .code
                                    clearFieldErrors()
                                }
                                modeChip("账号密码登录", active: loginMode == .password) {
                                    loginMode = .password
                                    clearFieldErrors()
                                }
                            }

                            if loginMode == .code {
                                fieldLabel("手机号").padding(.top, 16)
                                posterField(
                                    text: $phone,
                                    placeholder: "请输入手机号",
                                    prefix: dialCode.prefix,
                                    showDialMenu: true,
                                    keyboard: .phonePad,
                                    error: !phoneError.isEmpty
                                ) { value in
                                    phone = String(value.filter(\.isNumber).prefix(dialCode.maxDigits))
                                    phoneError = ""
                                }
                                fieldError(phoneError)

                                fieldLabel("验证码").padding(.top, 12)
                                posterField(
                                    text: $verifyCode,
                                    placeholder: "6 位验证码",
                                    keyboard: .numberPad,
                                    letterSpacing: 4,
                                    error: !codeError.isEmpty,
                                    trailing: AnyView(verifyAction)
                                ) { value in
                                    verifyCode = String(value.filter(\.isNumber).prefix(6))
                                    codeError = ""
                                }
                                fieldError(codeError)

                                pillButton(title: isLoading ? "登录中" : "登录 / 注册") {
                                    submitLogin()
                                }
                                .padding(.top, 16)
                                .disabled(isLoading)
                            }

                            if loginMode == .password {
                                fieldLabel("手机号").padding(.top, 16)
                                posterField(
                                    text: $account,
                                    placeholder: "请输入手机号",
                                    prefix: dialCode.prefix,
                                    showDialMenu: true,
                                    keyboard: .phonePad,
                                    error: !accountError.isEmpty
                                ) { value in
                                    account = String(value.filter(\.isNumber).prefix(dialCode.maxDigits))
                                    accountError = ""
                                }
                                fieldError(accountError)

                                HStack {
                                    Text("密码")
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(Color(hex: "374151"))
                                    Spacer()
                                    Button("忘记密码？") { showReset = true }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color(hex: "0B7A72"))
                                }
                                .padding(.top, 12)
                                .padding(.bottom, 6)

                                posterField(
                                    text: $password,
                                    placeholder: "请输入登录密码",
                                    keyboard: .default,
                                    isSecure: !showPassword,
                                    error: !passwordError.isEmpty,
                                    trailing: AnyView(
                                        Button(showPassword ? "隐藏" : "显示") {
                                            showPassword.toggle()
                                        }
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(showPassword ? Color(hex: "1A6B64") : Color(hex: "5F6F66"))
                                    )
                                ) { value in
                                    password = String(value.prefix(20))
                                    passwordError = ""
                                }
                                fieldError(passwordError)

                                pillButton(title: isLoading ? "登录中" : "登录") {
                                    submitLogin()
                                }
                                .padding(.top, 16)
                                .disabled(isLoading)
                            }

                            agreementRow
                                .padding(.top, 18)
                            if showAgreeHint {
                                Text("请先勾选协议后再登录")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "DC2626"))
                                    .padding(.top, 8)
                            }

                            #if DEBUG
                            Button("测试登录") { debugLogin() }
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "8A9C92"))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 10)
                            #endif

                            Button("返回") { onDismiss() }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(posterLink)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                        }
                        .padding(.leading, 22)
                        .padding(.top, 24)
                        .padding(.trailing, 22)
                        .padding(.bottom, 16)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
        }
        .onDisappear { timer?.invalidate() }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            }
        }
        .overlay {
            if showReset {
                ResetPasswordSheet(
                    initialPhone: account.isEmpty ? phone : account,
                    dialCode: $dialCode,
                    onDismiss: { showReset = false },
                    onReset: { message in
                        showReset = false
                        loginMode = .password
                        toast(message)
                    }
                )
            }
        }
        .onChange(of: dialCode) { code in
            phone = String(phone.filter(\.isNumber).prefix(code.maxDigits))
            account = String(account.filter(\.isNumber).prefix(code.maxDigits))
            phoneError = ""
            accountError = ""
        }
    }

    private var verifyAction: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(hex: "E5E7EB"))
                .frame(width: 1, height: 22)
            Button(countdown > 0 ? "\(countdown)s 后重发" : "获取验证码") {
                sendCode(type: "member_phone_login")
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundColor(countdown == 0 && !isLoading ? Color(hex: "0C7A72") : Color(hex: "8A9C92"))
            .disabled(isLoading || countdown > 0)
        }
    }

    private var agreementRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                agreed.toggle()
                if agreed { showAgreeHint = false }
            } label: {
                ZStack {
                    Circle()
                        .fill(agreed ? Color(hex: "0C9280") : Color.white)
                        .frame(width: 20, height: 20)
                    Circle()
                        .stroke(agreed ? Color(hex: "076B5C") : Color(hex: "D5E0DA"), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if agreed {
                        Text("✓")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Button("我已阅读并同意") { agreed.toggle() }
                    .foregroundColor(Color(hex: "4B5563"))
                Button("《用户协议》") { SafariOpen.page(AgreementURL.userAgreement) }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(posterLink)
                Text("与")
                    .foregroundColor(Color(hex: "4B5563"))
                Button("《隐私政策》") { SafariOpen.page(AgreementURL.privacyPolicy) }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(posterLink)
            }
            .font(.system(size: 11.5))
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .bold : .semibold))
                .foregroundColor(active ? .white : Color(hex: "4B5563"))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(active ? teal : Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(active ? teal : fieldBorder, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundColor(Color(hex: "374151"))
            .padding(.bottom, 6)
    }

    private func fieldError(_ text: String) -> some View {
        Group {
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "DC2626"))
                    .padding(.top, 6)
            }
        }
    }

    private func posterField(
        text: Binding<String>,
        placeholder: String,
        prefix: String? = nil,
        showDialMenu: Bool = false,
        keyboard: UIKeyboardType,
        letterSpacing: CGFloat = 0.3,
        isSecure: Bool = false,
        error: Bool,
        trailing: AnyView? = nil,
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            if let prefix {
                if showDialMenu {
                    Menu {
                        ForEach(LoginDialCode.allCases) { item in
                            Button(item.title) { dialCode = item }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(prefix)
                                .font(.system(size: 14, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "374151"))
                    }
                } else {
                    Text(prefix)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "374151"))
                }
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15, weight: letterSpacing > 1 ? .semibold : .regular))
            .foregroundColor(ink)
            .keyboardType(keyboard)
            .textContentType(isSecure ? .password : (keyboard == .phonePad ? .telephoneNumber : (letterSpacing > 1 ? .oneTimeCode : .username)))
            .disableAutocorrection(true)
            .autocapitalization(.none)
            .onChange(of: text.wrappedValue, perform: onChange)

            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
                .background(error ? Color(hex: "FEF2F2") : Color(hex: "F7FAF8"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(error ? Color(hex: "DC2626") : fieldBorder, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pillButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color(hex: "11B5AC"))
                .clipShape(Capsule())
                .shadow(color: Color(hex: "0C9280").opacity(0.28), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func clearFieldErrors() {
        phoneError = ""
        codeError = ""
        accountError = ""
        passwordError = ""
        hideKeyboard()
    }

    private func validPhone(_ value: String) -> Bool {
        dialCode.isValid(value)
    }

    private func sendCode(type: String) {
        hideKeyboard()
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard validPhone(trimmed) else {
            phoneError = dialCode.errorText
            return
        }
        isLoading = true
        Task {
            let result = await ApiService.shared.sendVerifyCode(phone: trimmed, type: type, countryCode: dialCode.rawValue)
            await MainActor.run {
                isLoading = false
                if result.success {
                    startCountdown()
                    toast("验证码已发送")
                } else {
                    toast(result.message)
                }
            }
        }
    }

    private func submitLogin() {
        hideKeyboard()
        if loginMode == .code {
            let trimmed = phone.trimmingCharacters(in: .whitespaces)
            let phoneOk = validPhone(trimmed)
            let codeOk = verifyCode.range(of: "^\\d{6}$", options: .regularExpression) != nil
            phoneError = phoneOk ? "" : dialCode.errorText
            codeError = codeOk ? "" : "请输入 6 位数字验证码"
            guard phoneOk, codeOk else { return }
        } else {
            let trimmed = account.trimmingCharacters(in: .whitespaces)
            let phoneOk = validPhone(trimmed)
            accountError = phoneOk ? "" : dialCode.errorText
            passwordError = password.count >= 6 ? "" : "密码至少 6 位"
            guard phoneOk, passwordError.isEmpty else { return }
        }
        guard agreed else {
            showAgreeHint = true
            toast("请先勾选协议")
            return
        }
        showAgreeHint = false
        isLoading = true
        Task {
            let result: LoginResult
            if loginMode == .code {
                result = await ApiService.shared.phoneLogin(
                    phone: phone.trimmingCharacters(in: .whitespaces),
                    verifyCode: verifyCode,
                    countryCode: dialCode.rawValue
                )
            } else {
                result = await ApiService.shared.phoneLogin(
                    phone: account.trimmingCharacters(in: .whitespaces),
                    password: password,
                    countryCode: dialCode.rawValue
                )
            }
            await MainActor.run {
                isLoading = false
                if result.success {
                    if !result.token.isEmpty {
                        ApiService.shared.token = result.token
                    }
                    onLoginSuccess()
                } else {
                    toast(result.message)
                }
            }
        }
    }

    private func startCountdown() {
        countdown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown > 0 {
                countdown -= 1
            } else {
                t.invalidate()
            }
        }
    }

    private func toast(_ message: String) {
        toastMessage = message
        showToast = true
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    #if DEBUG
    private func debugLogin() {
        ApiService.shared.token = DebugLoginConfig.testToken
        onLoginSuccess()
    }
    #endif
}

private struct ResetPasswordSheet: View {
    let initialPhone: String
    @Binding var dialCode: LoginDialCode
    let onDismiss: () -> Void
    let onReset: (String) -> Void

    @State private var step = 1
    @State private var phone = ""
    @State private var verifyCode = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var showPassword = false
    @State private var showPassword2 = false
    @State private var phoneError = ""
    @State private var codeError = ""
    @State private var passwordError = ""
    @State private var password2Error = ""
    @State private var secondsLeft = 0
    @State private var loading = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var timer: Timer?

    private let strongPassword = "^(?=.*[A-Za-z])(?=.*\\d).{8,20}$"

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    if !loading { onDismiss() }
                }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("重置密码")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(Color(hex: "141A1F"))
                        Text("通过手机号验证后设置新密码")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "5F6F66"))
                    }
                    Spacer()
                    Button {
                        if !loading { onDismiss() }
                    } label: {
                        Text("✕")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "6B7280"))
                            .frame(width: 38, height: 38)
                            .background(Color(hex: "F5F7F8"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 6)

                HStack {
                    resetStep(1, "验证手机号", state: step == 1 ? "on" : "done")
                    Rectangle()
                        .fill(Color(hex: "D5E2DE"))
                        .frame(width: 18, height: 1.5)
                    resetStep(2, "设置新密码", state: step == 2 ? "on" : "")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if step == 1 {
                            labeled("手机号")
                            inputField(text: $phone, placeholder: "请输入注册手机号", prefix: dialCode.prefix, showDialMenu: true, keyboard: .phonePad, error: !phoneError.isEmpty) {
                                phone = String($0.filter(\.isNumber).prefix(dialCode.maxDigits))
                                phoneError = ""
                            }
                            errorText(phoneError)
                            labeled("验证码").padding(.top, 12)
                            inputField(
                                text: $verifyCode,
                                placeholder: "6 位验证码",
                                keyboard: .numberPad,
                                letterSpacing: 4,
                                error: !codeError.isEmpty,
                                trailing: AnyView(
                                    HStack(spacing: 12) {
                                        Rectangle().fill(Color(hex: "E5E7EB")).frame(width: 1, height: 22)
                                        Button(secondsLeft > 0 ? "\(secondsLeft)s 后重发" : "获取验证码") {
                                            sendCode()
                                        }
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(secondsLeft == 0 && !loading ? Color(hex: "0C7A72") : Color(hex: "8A9C92"))
                                        .disabled(loading || secondsLeft > 0)
                                    }
                                )
                            ) {
                                verifyCode = String($0.filter(\.isNumber).prefix(6))
                                codeError = ""
                            }
                            errorText(codeError)
                        } else {
                            labeled("新密码")
                            inputField(
                                text: $password,
                                placeholder: "8-20 位，需含字母和数字",
                                keyboard: .default,
                                isSecure: !showPassword,
                                error: !passwordError.isEmpty,
                                trailing: AnyView(eye($showPassword))
                            ) {
                                password = String($0.prefix(20))
                                passwordError = ""
                            }
                            strengthBar
                            errorText(passwordError)
                            labeled("确认新密码").padding(.top, 12)
                            inputField(
                                text: $password2,
                                placeholder: "请再次输入新密码",
                                keyboard: .default,
                                isSecure: !showPassword2,
                                error: !password2Error.isEmpty,
                                trailing: AnyView(eye($showPassword2))
                            ) {
                                password2 = String($0.prefix(20))
                                password2Error = ""
                            }
                            errorText(password2Error)
                            Text("重置成功后需用新密码重新登录，学习记录不受影响")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(hex: "1A6B64"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: "E8FAF7"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .stroke(Color(hex: "4ECDC4").opacity(0.22), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .frame(maxHeight: 360)

                VStack(spacing: 8) {
                    if step == 1 {
                        pill("下一步") {
                            let phoneOk = dialCode.isValid(phone)
                            let codeOk = verifyCode.range(of: "^\\d{6}$", options: .regularExpression) != nil
                            phoneError = phoneOk ? "" : dialCode.errorText
                            codeError = codeOk ? "" : "请输入 6 位数字验证码"
                            if phoneOk && codeOk { step = 2 }
                        }
                        Button("取消") { if !loading { onDismiss() } }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Color(hex: "2A9D95"))
                    } else {
                        HStack(spacing: 10) {
                            Button("上一步") { step = 1 }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(hex: "374151"))
                                .padding(.horizontal, 20)
                                .frame(height: 46)
                                .overlay(Capsule().stroke(Color(hex: "D5E0DA"), lineWidth: 1.5))
                            Button {
                                submitReset()
                            } label: {
                                Text(loading ? "重置中" : "完成重置")
                                    .font(.system(size: 17, weight: .heavy))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(Color(hex: "11B5AC"))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(loading)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .onAppear {
            phone = String(initialPhone.filter(\.isNumber).prefix(dialCode.maxDigits))
        }
        .onDisappear { timer?.invalidate() }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
    }

    private func resetStep(_ index: Int, _ label: String, state: String) -> some View {
        let bg: Color = state == "on" ? Color(hex: "2A9D95") : (state == "done" ? Color(hex: "0F7A4A") : Color(hex: "EEF2F0"))
        let fg: Color = state.isEmpty ? Color(hex: "5F6F66") : .white
        return HStack(spacing: 6) {
            Text("\(index)")
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundColor(fg)
                .frame(width: 22, height: 22)
                .background(bg)
                .clipShape(Circle())
            Text(label)
                .font(.system(size: 11.5, weight: state == "on" ? .bold : .semibold))
                .foregroundColor(state == "on" ? Color(hex: "1A6B64") : Color(hex: "5F6F66"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeled(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundColor(Color(hex: "374151"))
            .padding(.bottom, 6)
    }

    private func errorText(_ text: String) -> some View {
        Group {
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "DC2626"))
                    .padding(.top, 6)
            }
        }
    }

    private func eye(_ visible: Binding<Bool>) -> some View {
        Button(visible.wrappedValue ? "隐藏" : "显示") {
            visible.wrappedValue.toggle()
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(visible.wrappedValue ? Color(hex: "1A6B64") : Color(hex: "5F6F66"))
    }

    private var strengthBar: some View {
        let level = passwordStrength(password)
        let active: Color = level == 1 ? Color(hex: "DC2626") : (level == 2 ? Color(hex: "F59E0B") : (level == 3 ? Color(hex: "2A9D95") : Color(hex: "E4EAE6")))
        let label = level == 1 ? "弱" : (level == 2 ? "中" : (level == 3 ? "强" : ""))
        return VStack(spacing: 7) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(level > index ? active : Color(hex: "E4EAE6"))
                        .frame(height: 4)
                }
            }
            .padding(.top, 10)
            HStack {
                Text("8-20 位，含字母与数字")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "5F6F66"))
                Spacer()
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(active)
            }
        }
    }

    private func passwordStrength(_ value: String) -> Int {
        if value.isEmpty { return 0 }
        var score = 0
        if value.count >= 8 { score += 1 }
        if value.contains(where: { $0.isLetter }) && value.contains(where: { $0.isNumber }) { score += 1 }
        if value.contains(where: { !$0.isLetter && !$0.isNumber }) && value.count >= 10 { score += 1 }
        return min(max(score, 1), 3)
    }

    private func inputField(
        text: Binding<String>,
        placeholder: String,
        prefix: String? = nil,
        showDialMenu: Bool = false,
        keyboard: UIKeyboardType,
        letterSpacing: CGFloat = 0.3,
        isSecure: Bool = false,
        error: Bool,
        trailing: AnyView? = nil,
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            if let prefix {
                if showDialMenu {
                    Menu {
                        ForEach(LoginDialCode.allCases) { item in
                            Button(item.title) { dialCode = item }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(prefix)
                                .font(.system(size: 14, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "374151"))
                    }
                } else {
                    Text(prefix)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "374151"))
                }
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15, weight: letterSpacing > 1 ? .semibold : .regular))
            .keyboardType(keyboard)
            .disableAutocorrection(true)
            .autocapitalization(.none)
            .onChange(of: text.wrappedValue, perform: onChange)
            if let trailing { trailing }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(error ? Color(hex: "FEF2F2") : Color(hex: "F7FAF8"))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(error ? Color(hex: "DC2626") : Color(hex: "D5E0DA"), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color(hex: "11B5AC"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    private func sendCode() {
        guard dialCode.isValid(phone) else {
            phoneError = dialCode.errorText
            return
        }
        loading = true
        Task {
            let result = await ApiService.shared.sendVerifyCode(phone: phone, type: "member_forget_pwd", countryCode: dialCode.rawValue)
            await MainActor.run {
                loading = false
                if result.success {
                    startCountdown()
                    toastMessage = "验证码已发送"
                    showToast = true
                } else {
                    toastMessage = result.message
                    showToast = true
                }
            }
        }
    }

    private func startCountdown() {
        secondsLeft = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if secondsLeft > 0 {
                secondsLeft -= 1
            } else {
                t.invalidate()
            }
        }
    }

    private func submitReset() {
        let pwdOk = password.range(of: strongPassword, options: .regularExpression) != nil
        passwordError = pwdOk ? "" : "新密码需 8-20 位且同时包含字母和数字"
        if password2.isEmpty {
            password2Error = "请再次输入新密码"
        } else if password2 != password {
            password2Error = "两次输入的密码不一致"
        } else {
            password2Error = ""
        }
        guard pwdOk, password2Error.isEmpty else { return }
        loading = true
        Task {
            let result = await ApiService.shared.forgetPassword(phone: phone, verifyCode: verifyCode, password: password, countryCode: dialCode.rawValue)
            await MainActor.run {
                loading = false
                if result.success {
                    onReset(result.message)
                } else {
                    toastMessage = result.message
                    showToast = true
                }
            }
        }
    }
}
