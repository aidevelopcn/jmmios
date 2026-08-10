import Foundation

// MARK: - 用户信息
struct UserProfile: Codable {
    let id: Int
    var nickname: String
    var avatarUrl: String
    let isVip: Bool
    let vipTime: String
    var school: String
    var major: String
    var schoolYear: String
    var invitationCode: String
    
    enum CodingKeys: String, CodingKey {
        case id, nickname, avatarUrl, school, major
        case isVip = "is_vip"
        case vipTime = "vip_expire_time_text"
        case schoolYear = "schoolyear"
        case invitationCode = "invitation_code"
    }
    
    init(id: Int, nickname: String, avatarUrl: String, isVip: Bool, vipTime: String,
         school: String, major: String, schoolYear: String = "", invitationCode: String = "") {
        self.id = id
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.isVip = isVip
        self.vipTime = vipTime
        self.school = school
        self.major = major
        self.schoolYear = schoolYear
        self.invitationCode = invitationCode
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl) ?? ""
        isVip = try c.decodeIfPresent(Bool.self, forKey: .isVip) ?? false
        vipTime = try c.decodeIfPresent(String.self, forKey: .vipTime) ?? ""
        school = try c.decodeIfPresent(String.self, forKey: .school) ?? ""
        major = try c.decodeIfPresent(String.self, forKey: .major) ?? ""
        if let yearInt = try? c.decode(Int.self, forKey: .schoolYear) {
            schoolYear = String(yearInt)
        } else {
            schoolYear = try c.decodeIfPresent(String.self, forKey: .schoolYear) ?? ""
        }
        invitationCode = try c.decodeIfPresent(String.self, forKey: .invitationCode) ?? ""
    }
}

// MARK: - 登录结果
struct LoginResult {
    let success: Bool
    let token: String
    let message: String
}

// MARK: - 轮播图
struct BannerItem {
    let imageURL: String
}

// MARK: - VIP 商品
struct VipGoods: Decodable {
    let id: Int
    let name: String
    let tip: String
    let desc: String
    let price: String
    let oldPrice: String
    
    enum CodingKeys: String, CodingKey {
        case id, price
        case goods_name, goods_tip, goods_desc
        case old_price
    }
    
    init(id: Int, name: String, tip: String, desc: String, price: String, oldPrice: String) {
        self.id = id
        self.name = name
        self.tip = tip
        self.desc = desc
        self.price = price
        self.oldPrice = oldPrice
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .goods_name) ?? ""
        tip = try c.decodeIfPresent(String.self, forKey: .goods_tip) ?? ""
        desc = try c.decodeIfPresent(String.self, forKey: .goods_desc) ?? ""
        price = Self.decodeFlexibleString(from: c, forKey: .price) ?? "0"
        oldPrice = Self.decodeFlexibleString(from: c, forKey: .old_price) ?? "0"
    }
    
    /// API 可能返回字符串或数字（Android optString 会自动转换）
    private static func decodeFlexibleString(from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let value = try? c.decode(String.self, forKey: key) { return value }
        if let value = try? c.decode(Double.self, forKey: key) { return formatNumber(value) }
        if let value = try? c.decode(Int.self, forKey: key) { return String(value) }
        return nil
    }
    
    private static func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}

// MARK: - 订单
struct OrderItem: Decodable {
    let orderSn: String
    let goodsName: String
    let activeMoney: String
    let stateText: String
    let paytimeText: String
    let createTimeText: String
    
    enum CodingKeys: String, CodingKey {
        case orderSn, goodsName, activeMoney, stateText, paytimeText, createTimeText
        case order_sn, goods_name, active_money, state_text, paytime_text, create_time_text
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderSn = try c.decodeIfPresent(String.self, forKey: .order_sn) ?? ""
        goodsName = try c.decodeIfPresent(String.self, forKey: .goods_name) ?? ""
        activeMoney = try c.decodeIfPresent(String.self, forKey: .active_money) ?? ""
        stateText = try c.decodeIfPresent(String.self, forKey: .state_text) ?? ""
        paytimeText = try c.decodeIfPresent(String.self, forKey: .paytime_text) ?? ""
        createTimeText = try c.decodeIfPresent(String.self, forKey: .create_time_text) ?? ""
    }

    init(orderSn: String, goodsName: String, activeMoney: String, stateText: String, paytimeText: String, createTimeText: String) {
        self.orderSn = orderSn
        self.goodsName = goodsName
        self.activeMoney = activeMoney
        self.stateText = stateText
        self.paytimeText = paytimeText
        self.createTimeText = createTimeText
    }
}

// MARK: - 答疑记录
struct AskRecordItem: Identifiable {
    let id: String
    let title: String
    let questionText: String
    let answerSummary: String
    let imageUrl: String
    let timeText: String
}

// MARK: - 会话记录
struct ConversationItem: Identifiable {
    let id: String
    let title: String
    let messageCount: Int
}

// MARK: - 聊天消息
struct ChatMessage: Identifiable {
    let id: String
    let role: String // "user" or "assistant"
    var content: String
    var isStreaming: Bool
    var relatedQuestion: String
    var relatedImageUrl: String
    var imageLocalURL: String?
    var imageName: String
    var imageSize: Int64
    
    init(id: String = UUID().uuidString, role: String, content: String,
         isStreaming: Bool = false, relatedQuestion: String = "",
         relatedImageUrl: String = "", imageLocalURL: String? = nil,
         imageName: String = "", imageSize: Int64 = 0) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.relatedQuestion = relatedQuestion
        self.relatedImageUrl = relatedImageUrl
        self.imageLocalURL = imageLocalURL
        self.imageName = imageName
        self.imageSize = imageSize
    }
}

// MARK: - 测评相关
struct AssessmentItem: Identifiable {
    let id: Int
    let title: String
    let description: String
    let totalQuestions: Int
    let minScore: Int
    let maxScore: Int
    let durationMinutes: Int
    let iconName: String
}

struct AssessmentQuestion: Identifiable {
    let id: Int
    let content: String
    let optionA: String
    let optionB: String
    let reverse: Bool

    init(id: Int, content: String, optionA: String = "", optionB: String = "", reverse: Bool = false) {
        self.id = id
        self.content = content
        self.optionA = optionA
        self.optionB = optionB
        self.reverse = reverse
    }
}

struct AssessmentOption: Identifiable {
    var id: Int { value }
    let value: Int
    let label: String
}

struct AssessmentConfig {
    let item: AssessmentItem
    let questions: [AssessmentQuestion]
    let options: [AssessmentOption]
}

// MARK: - 微信支付参数
struct WechatPayParams {
    let appId: String
    let partnerId: String
    let prepayId: String
    let nonceStr: String
    let timeStamp: String
    let sign: String
    let packageValue: String
}
