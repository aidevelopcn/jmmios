import SwiftUI

// MARK: - 申请注销账号（对齐 Android ApplyCloseAccountScreen）
struct ApplyCloseAccountView: View {
    let onBack: () -> Void
    let onNext: () -> Void

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
                Text("注销账号")
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
                    Text("为保证你的账户安全，提交账户注销申请生效前需满足以下条件：")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "333333"))
                        .padding(.top, 8)

                    Text("1、账号为本人官方注册并符合平台规范。\n2、账号无任何安全风险。\n3、无未了结合同关系与争议。\n4、账号内无未完成订单或交易。")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "333333"))
                        .lineSpacing(6)

                    HStack(spacing: 12) {
                        Button(action: onNext) {
                            Text("申请注销")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 8).fill(AppColors.primary))
                        }

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
    }
}
