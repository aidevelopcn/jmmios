import SwiftUI

// MARK: - 开通会员（对齐 Android RechargeScreen）
struct RechargeView: View {
    let onBack: () -> Void

    private let vipPrimary = Color(hex: "00AFA4")
    private let vipInk = Color(hex: "17181A")
    private let vipCardBorder = Color(hex: "E5E7EB")

    @State private var goodsList: [VipGoods] = []
    @State private var selectedIndex = 0
    @State private var loading = true
    @State private var placingOrder = false
    @State private var agreed = false
    @State private var showAgreement = false
    @State private var showPayError = false
    @State private var payErrorMessage = ""
    @State private var showPayResult = false
    @State private var payResultMessage = ""

    var body: some View {
        Group {
            if showAgreement {
                VipAgreementView(onBack: { showAgreement = false })
            } else {
                rechargeBody
            }
        }
        .alert("提示", isPresented: $showPayError) { Button("确定") {} } message: { Text(payErrorMessage) }
        .alert("提示", isPresented: $showPayResult) { Button("确定") {} } message: { Text(payResultMessage) }
        .onAppear { loadGoods() }
    }

    private var rechargeBody: some View {
        ProfileScreenScaffold(background: Color(hex: "F5F7FA")) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "开通会员", onBack: onBack, barBackground: Color.clear)

                if loading {
                    Spacer(minLength: 0)
                    ProgressView().tint(vipPrimary)
                    Spacer(minLength: 0)
                } else if goodsList.isEmpty {
                    Spacer(minLength: 0)
                    Text("暂无可购买的套餐")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "6B7280"))
                    Spacer(minLength: 0)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(goodsList.enumerated()), id: \.element.id) { index, item in
                                goodsCard(item: item, selected: index == selectedIndex)
                                    .onTapGesture { selectedIndex = index }
                            }
                            Text("购买后立即生效。支付由微信支付提供，退款规则见《绩满满会员服务协议》。")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "94A3B8"))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                                .padding(.bottom, 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 10) {
                        agreementRow
                        Button(action: tapPay) {
                            HStack(spacing: 8) {
                                if placingOrder {
                                    ProgressView().tint(.white)
                                }
                                Text(placingOrder ? "正在唤起微信支付…" : "立即开通")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(vipPrimary.opacity(placingOrder ? 0.45 : 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(placingOrder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(Color.white)
                }
            }
        }
    }

    private var agreementRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: { agreed.toggle() }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(agreed ? vipPrimary : Color.white)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(agreed ? vipPrimary : Color(hex: "D0D5DD"), lineWidth: 1)
                    if agreed {
                        Text("✓")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Button("我已阅读并同意") { agreed.toggle() }
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "4B5563"))
                    .buttonStyle(.plain)
                Button("《绩满满会员服务协议》") { showAgreement = true }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(vipPrimary)
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func goodsCard(item: VipGoods, selected: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(vipInk)
                    if !item.tip.isEmpty {
                        Text(item.tip)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "0F766E"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "E6F9F8"))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                if !item.desc.isEmpty {
                    Text(item.desc)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "6B7280"))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("¥\(item.price)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(vipPrimary)
                if (Double(item.oldPrice) ?? 0) > (Double(item.price) ?? 0) {
                    Text("¥\(item.oldPrice)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "94A3B8"))
                        .strikethrough()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? vipPrimary : vipCardBorder, lineWidth: selected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadGoods() {
        Task {
            await MainActor.run { loading = true }
            let list = await ApiService.shared.fetchVipGoodsList()
            await MainActor.run {
                goodsList = list
                if selectedIndex >= list.count { selectedIndex = 0 }
                loading = false
            }
        }
    }

    private func tapPay() {
        guard !placingOrder else { return }
        guard agreed else {
            payErrorMessage = "请先阅读并同意《绩满满会员服务协议》"
            showPayError = true
            return
        }
        guard let token = ApiService.shared.token, !token.isEmpty else {
            payErrorMessage = "请先登录"
            showPayError = true
            return
        }
        guard goodsList.indices.contains(selectedIndex) else { return }
        placeOrder(item: goodsList[selectedIndex])
    }

    private func placeOrder(item: VipGoods) {
        Task {
            await MainActor.run { placingOrder = true }
            let result = await ApiService.shared.createVipOrder(goodsId: item.id)
            await MainActor.run {
                placingOrder = false
                if let params = result.params {
                    let started = WechatLoginBridge.startPay(params: params) { errCode, errMsg in
                        Task { @MainActor in
                            if errCode == 0 {
                                payResultMessage = "支付成功"
                            } else if errCode == -2 {
                                payResultMessage = "支付已取消"
                            } else {
                                payResultMessage = errMsg.isEmpty ? "支付失败" : errMsg
                            }
                            showPayResult = true
                        }
                    }
                    if !started {
                        payErrorMessage = "无法调起微信支付"
                        showPayError = true
                    }
                } else {
                    payErrorMessage = result.error.isEmpty ? "下单失败" : result.error
                    showPayError = true
                }
            }
        }
    }
}

// MARK: - 我的订单（对齐 Android MyOrderScreen）
struct MyOrderView: View {
    let onBack: () -> Void

    @StateObject private var apiService = ApiService.shared
    @State private var orders: [OrderItem] = []
    @State private var loading = true

    var body: some View {
        ProfileScreenScaffold(background: Color(hex: "EEEEEE")) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "我的订单", onBack: onBack)

                if apiService.token == nil || apiService.token!.isEmpty {
                    Spacer(minLength: 0)
                    Text("请先登录")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "666666"))
                    Spacer(minLength: 0)
                } else if loading {
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                } else if orders.isEmpty {
                    Spacer(minLength: 0)
                    Text("暂无订单")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "999999"))
                    Spacer(minLength: 0)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(orders, id: \.orderSn) { item in
                                orderCard(item: item)
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { loadOrders() }
    }

    private func orderCard(item: OrderItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text("订单编号：\(item.orderSn)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "333333"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.stateText)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "666666"))
            }

            HStack(alignment: .top) {
                Text(item.goodsName)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "333333"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("创建时间:\(item.createTimeText)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "999999"))
            }

            HStack(alignment: .top) {
                Text("￥\(item.activeMoney)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "F82C2C"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !item.paytimeText.isEmpty {
                    Text("完成时间:\(item.paytimeText)")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "999999"))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
    }

    private func loadOrders() {
        Task {
            await MainActor.run { loading = true }
            let list = await apiService.fetchOrderList()
            await MainActor.run {
                orders = list
                loading = false
            }
        }
    }
}
