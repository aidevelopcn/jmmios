import SwiftUI
import UIKit

struct AccountManageView: View {
    let onBack: () -> Void
    let onLogout: () -> Void
    let onOpenApplyClose: () -> Void

    @StateObject private var apiService = ApiService.shared
    @State private var boundPhone = ""
    @State private var passwordSet = true
    @State private var phoneReady = false
    @State private var cacheLabel = "计算中…"
    @State private var showPhoneForm = false
    @State private var showPasswordSheet = false
    @State private var confirmKind = ""
    @State private var toastMessage = ""
    @State private var showToast = false

    var body: some View {
        ZStack {
            Color(hex: "F5F7F8").ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        group("账号与安全") {
                            row("绑定手机号", value: phoneText) {
                                if phoneReady { showPhoneForm = true }
                            }
                            divider
                            row(passwordSet ? "修改密码" : "设置密码", value: passwordSet ? "" : "未设置") {
                                if phoneReady { showPasswordSheet = true }
                            }
                        }
                        group("协议") {
                            row("用户协议") { SafariOpen.page(AgreementURL.userAgreement) }
                            divider
                            row("隐私政策") { SafariOpen.page(AgreementURL.privacyPolicy) }
                        }
                        group("通用") {
                            row("清除缓存", value: cacheLabel) { clearCache() }
                        }
                        Button {
                            confirmKind = "logout"
                        } label: {
                            Text("退出登录")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "B91C1C"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                        Button("注销账号") { onOpenApplyClose() }
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "5F6F66"))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                            .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            if showPhoneForm {
                AccountPhoneForm(
                    currentPhone: boundPhone,
                    onBack: { showPhoneForm = false },
                    onSaved: { phone in
                        boundPhone = phone
                        showPhoneForm = false
                        toast("绑定成功")
                    }
                )
            }
            if showPasswordSheet {
                ChangePasswordSheet(
                    phone: boundPhone,
                    passwordSet: passwordSet,
                    onClose: { showPasswordSheet = false },
                    onChanged: { message, relogin in
                        showPasswordSheet = false
                        if relogin {
                            toast(message)
                            apiService.token = nil
                            onLogout()
                        } else {
                            passwordSet = true
                            toast(message)
                        }
                    }
                )
            }
            if confirmKind == "logout" {
                confirmLayer(
                    title: "退出登录？",
                    desc: "退出后需重新登录才能继续打卡",
                    okText: "确认退出",
                    onCancel: { confirmKind = "" },
                    onOk: {
                        confirmKind = ""
                        apiService.token = nil
                        onLogout()
                    }
                )
            }
        }
        .task { await loadAuth() }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
    }

    private var phoneText: String {
        if !phoneReady { return "" }
        let digits = boundPhone.filter(\.isNumber)
        if digits.count == 11 {
            return String(digits.prefix(3)) + "****" + String(digits.suffix(4))
        }
        return "未绑定"
    }

    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(hex: "1A1F26"))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("账号管理")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(hex: "1A1F26"))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .background(Color(hex: "F5F7F8"))
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "5F6F66"))
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
        .padding(.bottom, 14)
    }

    private func row(_ title: String, value: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "1A1F26"))
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "5F6F66"))
                }
                Text("›")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "8A9C92"))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Color(hex: "F1F4F2").frame(height: 1).padding(.horizontal, 16)
    }

    private func confirmLayer(title: String, desc: String, okText: String, onCancel: @escaping () -> Void, onOk: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 12) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "4B5563"))
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("取消", action: onCancel)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(Color(hex: "374151"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(hex: "F1F4F2"))
                        .clipShape(Capsule())
                    Button(okText, action: onOk)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(hex: "DC2626"))
                        .clipShape(Capsule())
                }
            }
            .padding(20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 36)
        }
    }

    private func loadAuth() async {
        cacheLabel = cacheSizeLabel()
        let auth = await ApiService.shared.fetchAccountAuth()
        let phone = auth.phone.filter(\.isNumber)
        let parent = auth.parentPhone.filter(\.isNumber)
        await MainActor.run {
            passwordSet = auth.passwordSet
            if phone.count == 11 {
                boundPhone = phone
            } else if parent.count == 11 {
                boundPhone = parent
            }
            phoneReady = true
        }
        if phone.count != 11, parent.count == 11 {
            let result = await ApiService.shared.bindPhone(phone: parent)
            if result.success {
                await MainActor.run { boundPhone = parent }
            }
        }
    }

    private func clearCache() {
        if cacheLabel == "0 KB" || cacheLabel == "清理中…" {
            toast("缓存已是空的")
            return
        }
        let cleared = cacheLabel
        cacheLabel = "清理中…"
        URLCache.shared.removeAllCachedResponses()
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                .forEach { try? FileManager.default.removeItem(at: $0) }
        }
        cacheLabel = "0 KB"
        toast("已清除 \(cleared) 缓存")
    }

    private func cacheSizeLabel() -> String {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }
        let bytes = files.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
        if bytes < 1024 { return "0 KB" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private func toast(_ message: String) {
        toastMessage = message
        showToast = true
    }
}

private struct AccountPhoneForm: View {
    let currentPhone: String
    let onBack: () -> Void
    let onSaved: (String) -> Void

    @State private var phone = ""
    @State private var verifyCode = ""
    @State private var secondsLeft = 0
    @State private var loading = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var timer: Timer?

    private var changing: Bool { currentPhone.filter(\.isNumber).count == 11 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回", action: onBack).foregroundColor(Color(hex: "1A1F26"))
                Spacer()
                Text(changing ? "修改手机号" : "绑定手机号")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Color.clear.frame(width: 44)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("手机号").font(.system(size: 14)).padding(.top, 16)
                    TextField(changing ? "请输入新手机号" : "请输入手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .padding(12)
                        .background(Color(hex: "F7FAF8"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if changing {
                        Text("验证码").font(.system(size: 14)).padding(.top, 8)
                        HStack {
                            TextField("6 位验证码", text: $verifyCode).keyboardType(.numberPad)
                            Button(secondsLeft > 0 ? "\(secondsLeft)s" : "获取验证码") { sendCode() }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(secondsLeft == 0 ? Color(hex: "11B5AC") : Color(hex: "8A9C92"))
                        }
                        .padding(12)
                        .background(Color(hex: "F7FAF8"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("验证码将发送到新手机号").font(.system(size: 12)).foregroundColor(Color(hex: "9CA3AF"))
                    } else {
                        Text("首次绑定无需验证码").font(.system(size: 12)).foregroundColor(Color(hex: "9CA3AF"))
                    }
                    Button(loading ? "提交中" : (changing ? "确认修改" : "确认绑定")) { submit() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(hex: "11B5AC"))
                        .clipShape(Capsule())
                        .padding(.top, 20)
                        .disabled(loading)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .onAppear { phone = currentPhone.filter(\.isNumber) }
        .onDisappear { timer?.invalidate() }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: { Text(toastMessage) }
    }

    private func sendCode() {
        let next = phone.filter(\.isNumber)
        guard next.count == 11 else { toastMessage = "请输入正确的 11 位手机号"; showToast = true; return }
        if next == currentPhone.filter(\.isNumber) {
            toastMessage = "请输入新的手机号"; showToast = true; return
        }
        Task {
            let result = await ApiService.shared.sendVerifyCode(phone: next, type: "member_bind_phone")
            await MainActor.run {
                if result.success {
                    secondsLeft = 60
                    timer?.invalidate()
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                        if secondsLeft > 0 { secondsLeft -= 1 } else { t.invalidate() }
                    }
                    toastMessage = "验证码已发送"; showToast = true
                } else {
                    toastMessage = result.message; showToast = true
                }
            }
        }
    }

    private func submit() {
        let next = phone.filter(\.isNumber)
        guard next.count == 11 else { toastMessage = "请输入正确的 11 位手机号"; showToast = true; return }
        if changing && next == currentPhone.filter(\.isNumber) {
            toastMessage = "请输入新的手机号"; showToast = true; return
        }
        if changing && verifyCode.count != 6 {
            toastMessage = "请输入 6 位验证码"; showToast = true; return
        }
        loading = true
        Task {
            let result = await ApiService.shared.bindPhone(phone: next, verifyCode: changing ? verifyCode : "")
            await MainActor.run {
                loading = false
                if result.success {
                    if !result.token.isEmpty { ApiService.shared.token = result.token }
                    onSaved(next)
                } else {
                    toastMessage = result.message
                    showToast = true
                }
            }
        }
    }
}

private struct ChangePasswordSheet: View {
    let phone: String
    let passwordSet: Bool
    let onClose: () -> Void
    let onChanged: (String, Bool) -> Void

    @State private var resetMode = false
    @State private var oldPassword = ""
    @State private var verifyCode = ""
    @State private var newPassword = ""
    @State private var newPassword2 = ""
    @State private var showOld = false
    @State private var showNew = false
    @State private var showNew2 = false
    @State private var oldError = ""
    @State private var codeError = ""
    @State private var newError = ""
    @State private var new2Error = ""
    @State private var secondsLeft = 0
    @State private var loading = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var timer: Timer?

    private let strong = "^(?=.*[A-Za-z])(?=.*\\d).{8,20}$"
    private var setMode: Bool { !passwordSet }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { if !loading { onClose() } }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(setMode ? "设置密码" : "修改密码")
                        .font(.system(size: 16, weight: .heavy))
                    Spacer()
                    Button("✕") { if !loading { onClose() } }.foregroundColor(Color(hex: "6B7280"))
                }
                if !setMode && !resetMode {
                    field("当前密码", $oldPassword, "请输入当前密码", secure: !showOld, error: oldError) {
                        Button(showOld ? "隐藏" : "显示") { showOld.toggle() }
                    }
                    Button("忘记密码，用短信验证") { resetMode = true }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "0B7A72"))
                }
                if resetMode {
                    HStack {
                        TextField("6 位验证码", text: $verifyCode).keyboardType(.numberPad)
                        Button(secondsLeft > 0 ? "\(secondsLeft)s" : "获取验证码") { sendCode() }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "11B5AC"))
                    }
                    .padding(12)
                    .background(Color(hex: "F7FAF8"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    if !codeError.isEmpty { Text(codeError).font(.system(size: 11)).foregroundColor(Color(hex: "DC2626")) }
                }
                field(setMode ? "密码" : "新密码", $newPassword, "8-20 位，需含字母和数字", secure: !showNew, error: newError) {
                    Button(showNew ? "隐藏" : "显示") { showNew.toggle() }
                }
                field("再次输入", $newPassword2, setMode ? "请再次输入密码" : "请再次输入新密码", secure: !showNew2, error: new2Error) {
                    Button(showNew2 ? "隐藏" : "显示") { showNew2.toggle() }
                }
                Button(loading ? "提交中" : (setMode ? "确认设置" : (resetMode ? "确认重置" : "确认修改"))) { submit() }
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: "11B5AC"))
                    .clipShape(Capsule())
                    .disabled(loading)
            }
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .onDisappear { timer?.invalidate() }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: { Text(toastMessage) }
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String, secure: Bool, error: String, trailing: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12.5, weight: .bold)).foregroundColor(Color(hex: "374151"))
            HStack {
                if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
                trailing()
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "5F6F66"))
            }
            .padding(12)
            .background(Color(hex: "F7FAF8"))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(error.isEmpty ? Color(hex: "D5E0DA") : Color(hex: "DC2626"), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundColor(Color(hex: "DC2626")) }
        }
    }

    private func sendCode() {
        let digits = phone.filter(\.isNumber)
        guard digits.count == 11 else { toastMessage = "请先绑定手机号"; showToast = true; return }
        Task {
            let result = await ApiService.shared.sendVerifyCode(phone: digits, type: "member_modify_pwd")
            await MainActor.run {
                if result.success {
                    secondsLeft = 60
                    timer?.invalidate()
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                        if secondsLeft > 0 { secondsLeft -= 1 } else { t.invalidate() }
                    }
                    toastMessage = "验证码已发送"; showToast = true
                } else {
                    toastMessage = result.message; showToast = true
                }
            }
        }
    }

    private func submit() {
        var ok = true
        if !setMode {
            if resetMode {
                codeError = verifyCode.count == 6 ? "" : "请输入 6 位短信验证码"
                if !codeError.isEmpty { ok = false }
            } else {
                oldError = oldPassword.count >= 6 ? "" : "请输入当前密码"
                if !oldError.isEmpty { ok = false }
            }
        }
        if newPassword.range(of: strong, options: .regularExpression) == nil {
            newError = "密码需 8-20 位且同时包含字母和数字"; ok = false
        } else if !setMode && !resetMode && oldPassword == newPassword && !oldPassword.isEmpty {
            newError = "新密码不能与原密码相同"; ok = false
        } else { newError = "" }
        if newPassword2.isEmpty {
            new2Error = setMode ? "请再次输入密码" : "请再次输入新密码"; ok = false
        } else if newPassword2 != newPassword {
            new2Error = "两次输入的密码不一致"; ok = false
        } else { new2Error = "" }
        guard ok else { toastMessage = "请检查输入内容"; showToast = true; return }
        loading = true
        Task {
            let result = await ApiService.shared.changePassword(
                oldPassword: setMode ? "" : oldPassword,
                verifyCode: resetMode ? verifyCode : "",
                newPassword: newPassword
            )
            await MainActor.run {
                loading = false
                if result.success {
                    if setMode {
                        onChanged("密码已设置，可用手机号和密码登录", false)
                    } else if resetMode {
                        onChanged("密码已重置，请用新密码登录", true)
                    } else {
                        onChanged("密码已修改，请用新密码重新登录", true)
                    }
                } else {
                    toastMessage = result.message
                    showToast = true
                }
            }
        }
    }
}
