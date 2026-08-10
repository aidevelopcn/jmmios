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

    var body: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image("back")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
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
        .background(Color.white)
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
                ProfileMenuRow(title: "储值", action: onOpenRecharge)
                ProfileMenuRow(title: "我的订单", action: onOpenOrders)
                Spacer(minLength: 0)
            }
        }
    }
}
