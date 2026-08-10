import SwiftUI

// MARK: - 储值页面（对齐 Android RechargeScreen）
struct RechargeView: View {
    let onBack: () -> Void

    @State private var goodsList: [VipGoods] = []
    @State private var loading = true
    @State private var placingOrder = false
    @State private var showPayError = false
    @State private var payErrorMessage = ""
    @State private var showPayResult = false
    @State private var payResultMessage = ""

    var body: some View {
        ProfileScreenScaffold(background: Color(hex: "EEEEEE")) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "储值", onBack: onBack)

                if loading {
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                } else if goodsList.isEmpty {
                    Spacer(minLength: 0)
                    Text("暂无商品")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "999999"))
                    Spacer(minLength: 0)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(goodsList, id: \.id) { item in
                                goodsCard(item: item)
                            }
                        }
                        .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("提示", isPresented: $showPayError) { Button("确定") {} } message: { Text(payErrorMessage) }
        .alert("提示", isPresented: $showPayResult) { Button("确定") {} } message: { Text(payResultMessage) }
        .onAppear { loadGoods() }
    }

    private func goodsCard(item: VipGoods) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "111111"))

            if !item.tip.isEmpty {
                Text("（\(item.tip)）")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "707070"))
            }

            if !item.desc.isEmpty {
                Text(item.desc)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "707070"))
            }

            Spacer().frame(height: 8)

            HStack(alignment: .center, spacing: 8) {
                Text("特惠 ¥\(item.price)")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "00D7CD")))

                if (Double(item.oldPrice) ?? 0) > (Double(item.price) ?? 0) {
                    Text("原价 ¥\(item.oldPrice)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "999999"))
                }

                Spacer(minLength: 0)

                Button(action: { placeOrder(item: item) }) {
                    Text(placingOrder ? "下单中" : "立即开通")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "F59E0B")))
                }
                .buttonStyle(.plain)
                .disabled(placingOrder)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
    }

    private func loadGoods() {
        Task {
            await MainActor.run { loading = true }
            let list = await ApiService.shared.fetchVipGoodsList()
            await MainActor.run {
                goodsList = list
                loading = false
            }
        }
    }

    private func placeOrder(item: VipGoods) {
        guard let token = ApiService.shared.token, !token.isEmpty else {
            payErrorMessage = "请先登录"
            showPayError = true
            return
        }

        Task {
            await MainActor.run { placingOrder = true }
            if let params = await ApiService.shared.createVipOrder(goodsId: item.id) {
                await MainActor.run { placingOrder = false }
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
                return
            } else {
                payErrorMessage = "下单失败"
                showPayError = true
            }
            await MainActor.run { placingOrder = false }
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
