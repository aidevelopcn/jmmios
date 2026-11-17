import SwiftUI

// MARK: - 全屏页面容器（对齐 Android fillMaxSize + statusBarsPadding）
struct ProfileScreenScaffold<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 通用导航栏（对齐 Android SimpleTopBar）
struct ProfileSimpleTopBar: View {
    let title: String
    let onBack: () -> Void
    var barBackground: Color = .white

    var body: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image("back")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "111111"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(barBackground)
    }
}

// MARK: - 通用菜单行（对齐 Android MenuRow）
struct ProfileMenuRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "111111"))
                Spacer()
                Text("›")
                    .font(.system(size: 19))
                    .foregroundColor(Color(hex: "999999"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 会员中心（对齐 Android VipCenterScreen）
struct VipCenterView: View {
    let onBack: () -> Void
    let onOpenRecharge: () -> Void
    let onOpenOrders: () -> Void

    var body: some View {
        ProfileScreenScaffold(background: Color.white) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "会员中心", onBack: onBack)
                if AppFeatures.showRecharge {
                    ProfileMenuRow(title: "开通会员", action: onOpenRecharge)
                }
                ProfileMenuRow(title: "我的订单", action: onOpenOrders)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 会员服务协议（对齐 Android VipAgreementScreen）
struct VipAgreementView: View {
    let onBack: () -> Void

    private let lines: [String] = {
        guard let url = Bundle.main.url(forResource: "vip_agreement", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }()

    var body: some View {
        ProfileScreenScaffold(background: Color.white) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "会员服务协议", onBack: onBack, barBackground: Color.clear)
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            if isHeading(line) {
                                Text(line)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color(hex: "17181A"))
                                    .padding(.top, index == 0 ? 0 : 18)
                                    .padding(.bottom, 6)
                            } else {
                                Text(line)
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "4B5563"))
                                    .lineSpacing(6)
                                    .padding(.bottom, 6)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
                Button(action: onBack) {
                    Text("我知道了")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(hex: "00AFA4"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
    }

    private func isHeading(_ line: String) -> Bool {
        line.range(of: "^(第[一二三四五六七八九十]+条|附件)", options: .regularExpression) != nil
    }
}
