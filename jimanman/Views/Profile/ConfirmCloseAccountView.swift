import SwiftUI

// MARK: - 确认注销账号（对齐 Android ConfirmCloseAccountScreen）
struct ConfirmCloseAccountView: View {
    let onBack: () -> Void
    let onSuccess: () -> Void

    @State private var agreed = false
    @State private var confirming = false
    @State private var showError = false
    @StateObject private var apiService = ApiService.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Text("确认注销")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.black)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(Color.white)
            .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("重要提示")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "333333"))
                        .padding(.top, 8)

                    Text("注销账号是不可恢复操作，账号数据、权益与历史信息将被清除。")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "333333"))
                        .lineSpacing(6)

                    Button(action: { agreed.toggle() }) {
                        HStack(alignment: .top, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(agreed ? AppColors.primaryLight : Color.white)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(agreed ? AppColors.primaryLight : Color(hex: "CCCCCC"), lineWidth: 1)
                                    )
                                if agreed {
                                    Text("✓").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                                }
                            }
                            Text("我已阅读并同意上方注销协议")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "333333"))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        Button(action: confirmCloseAccount) {
                            Text(confirming ? "提交中..." : "确认注销")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 8).fill(agreed && !confirming ? Color.red : Color.gray))
                        }
                        .disabled(!agreed || confirming)

                        Button(action: onBack) {
                            Text("取消")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "E5E5E5"), lineWidth: 1))
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(14)
            }
            .background(Color.white)
        }
        .navigationBarHidden(true)
        .alert("注销失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("提交失败，请稍后重试")
        }
    }

    private func confirmCloseAccount() {
        confirming = true
        Task {
            let ok = await apiService.cancelAccount()
            await MainActor.run {
                confirming = false
                if ok {
                    apiService.token = nil
                    onSuccess()
                } else {
                    showError = true
                }
            }
        }
    }
}
