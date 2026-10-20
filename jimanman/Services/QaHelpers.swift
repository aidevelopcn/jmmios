import Foundation

enum QaHelpers {
    static let welcomeHintEmpty = "请先登记科目再发起答疑，方便按科目留存你的答疑记录"
    static let welcomeHintPlus = "提交新问题时，记得右上角点「+」打开新窗口"

    private static let subjectAliases: [(String, String)] = [
        ("线代", "线性代数"),
        ("线性", "线性代数"),
        ("高数", "高等数学"),
        ("微积分", "高等数学"),
        ("定积分", "高等数学"),
        ("不定积分", "高等数学"),
        ("二重积分", "高等数学"),
        ("偏导数", "高等数学"),
        ("微分方程", "高等数学"),
        ("导数", "高等数学"),
        ("微分", "高等数学"),
        ("军理", "军事理论"),
        ("军事", "军事理论"),
        ("大物", "大学物理"),
        ("概率", "概率论与数理统计"),
        ("概率论", "概率论与数理统计"),
        ("概率统计", "概率论与数理统计"),
        ("离散", "离散数学"),
        ("大英", "大学英语"),
        ("马原", "马克思主义基本原理")
    ]

    static func inferQaSubject(prompt: String, registered: [String], selected: String) -> String {
        let picked = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !picked.isEmpty { return picked }
        return inferQaSubjectFromText(prompt, registered: registered)
    }

    static func inferQaSubjectFromText(_ text: String, registered: [String]) -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty || source == "[图片]" { return "" }
        var best = ""
        var bestLen = 0
        for name in registered {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { continue }
            for needle in needlesForQaSubject(n) {
                if source.contains(needle), needle.count > bestLen {
                    best = n
                    bestLen = needle.count
                }
            }
        }
        return best
    }

    static func extractQaKnowledgePoint(_ text: String) -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty { return "" }
        guard let regex = try? NSRegularExpression(pattern: #"\*{0,4}\s*知识点\s*\*{0,4}\s*[:：]?\s*([^\n*]{2,40})"#),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source) else { return "" }
        return sanitizeQaKnowledgeName(String(source[range]))
    }

    static func sanitizeQaKnowledgeName(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"[$\\].*"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: #"^\d+[)）.、．]\s*"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.components(separatedBy: CharacterSet(charactersIn: "、，,；;")).first ?? ""
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n:：.-—_"))
        if isGarbageQaKnowledge(text) || text.count > 16 { return "" }
        return looksLikeQaKnowledgeName(text) ? text : ""
    }

    static func isGarbageQaKnowledge(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "[图片]" || value == "未命名会话" { return true }
        if value.range(of: #"答疑服务异常|未收到|请稍后|请提供|没有题目|图片或输入|phpprivate|function|private static|public static"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if value.range(of: #"[$\\=]|\\int|\\frac|\\sum|\\begin"#, options: .regularExpression) != nil { return true }
        if value.range(of: #"^\d+[)）.、．]"#, options: .regularExpression) != nil { return true }
        let latin = value.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 128 }.count
        let han = value.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        return latin > 6 && han < 2
    }

    static func looksLikeQaKnowledgeName(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || isGarbageQaKnowledge(value) { return false }
        if value.count < 2 || value.count > 12 { return false }
        if value.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) == false { return false }
        return value.range(of: #"[$\\={}]|^\d"#, options: .regularExpression) == nil
    }

    static func buildQaSubjectFilterList(registered: [String], extra: [String] = []) -> [String] {
        var out: [String] = []
        func add(_ raw: String) {
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty || out.contains(n) { return }
            out.append(n)
        }
        add("全部")
        registered.forEach(add)
        extra.forEach {
            let n = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if n != "全部" && n != "未归类" { add(n) }
        }
        return out
    }

    static func formatQaListTime(_ raw: Int64) -> String {
        if raw <= 0 { return "" }
        let millis = raw < 10_000_000_000 ? raw * 1000 : raw
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let diff = now - millis
        if diff < 60_000 { return "刚刚" }
        if diff < 3_600_000 { return "\(diff / 60_000) 分钟前" }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date()).timeIntervalSince1970 * 1000
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "zh_CN")
        timeFmt.dateFormat = "HH:mm"
        if Double(millis) >= todayStart { return timeFmt.string(from: date) }
        if Double(millis) >= todayStart - 86_400_000 { return "昨天 \(timeFmt.string(from: date))" }
        let yearFmt = DateFormatter()
        yearFmt.locale = Locale(identifier: "zh_CN")
        yearFmt.dateFormat = "yyyy"
        if yearFmt.string(from: date) == yearFmt.string(from: Date()) {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.dateFormat = "M月d日"
            return fmt.string(from: date)
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        return fmt.string(from: date)
    }

    static func formatQaListTime(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "0" || text.lowercased() == "null" { return "" }
        if let n = Int64(text), n > 0 { return formatQaListTime(n) }
        let patterns = ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        for pattern in patterns {
            fmt.dateFormat = pattern
            if let date = fmt.date(from: text) {
                return formatQaListTime(Int64(date.timeIntervalSince1970 * 1000))
            }
        }
        return text
    }

    static func conversationMatchesQaSubject(subjectName: String, title: String, filter: String) -> Bool {
        let target = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty || target == "全部" { return true }
        let name = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == target { return true }
        if title.contains("【\(target)】") { return true }
        if !name.isEmpty {
            let nameNeedles = needlesForQaSubject(target)
            let targetNeedles = needlesForQaSubject(name)
            if nameNeedles.contains(where: { name.contains($0) }) || targetNeedles.contains(where: { target.contains($0) }) {
                return true
            }
        }
        return title.contains(target)
    }

    static func conversationTitleLine(_ chat: ConversationItem, registered: [String] = []) -> String {
        let source = [chat.knowledgePoint, chat.title, chat.preview].joined(separator: "\n")
        let subject = chat.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? inferQaSubjectFromText(source, registered: registered)
            : chat.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let knowledge = sanitizeQaKnowledgeName(chat.knowledgePoint).isEmpty
            ? extractQaKnowledgePoint(source)
            : sanitizeQaKnowledgeName(chat.knowledgePoint)
        let prefix = subject.isEmpty ? "" : "【\(subject)】"
        let title = prefix + knowledge
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名会话" : title
    }

    static func conversationPreviewLine(_ chat: ConversationItem) -> String {
        var rest = chat.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasPrefix("[图片]") {
            rest = String(rest.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        rest = stripQaQuestionHeading(rest)
        var line = chat.hasImage ? "[图片]" : ""
        if !rest.isEmpty {
            line += line.isEmpty ? rest : " \(rest)"
        }
        return line.isEmpty ? "\(chat.messageCount) 条消息" : line
    }

    static func stripQaQuestionHeading(_ raw: String) -> String {
        var text = raw
        if let regex = try? NSRegularExpression(pattern: #"\*{0,6}\s*题目\s*\*{0,6}(\s*\*)*"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: #"^\s*题目\s*"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shortQaModeLabel(_ label: String) -> String {
        if label.hasSuffix("模式") {
            let cut = String(label.dropLast(2))
            return cut.isEmpty ? label : cut
        }
        return label
    }

    static func pickQaChoice(items: [QaChoice], defaultKey: String, currentKey: String, fallback: String) -> String {
        if items.contains(where: { $0.key == currentKey }) { return currentKey }
        return items.first(where: { $0.key == defaultKey })?.key ?? items.first?.key ?? fallback
    }

    static func providerForQaMode(config: QaChatConfig, modeKey: String) -> String {
        let bound = config.modeProviders[modeKey] ?? ""
        if !bound.isEmpty, config.providers.contains(where: { $0.key == bound }) {
            return bound
        }
        let fallback = config.defaultProvider.isEmpty ? "qwen" : config.defaultProvider
        return pickQaChoice(items: config.providers, defaultKey: config.defaultProvider, currentKey: bound, fallback: fallback)
    }

    static func mergeSubjectNames(_ lists: [String]...) -> [String] {
        var out: [String] = []
        for list in lists {
            for item in list {
                let n = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty, !out.contains(n) { out.append(n) }
            }
        }
        return out
    }

    static func isStreamErrorChunk(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("请求失败") || value.contains("答疑服务") || value.contains("没有返回内容")
    }

    static func lastReusableImageUrl(_ messages: [ChatMessage], excludeIds: Set<String>) -> String {
        for item in messages.reversed() {
            if excludeIds.contains(item.id) { continue }
            if let url = item.imageLocalURL, !url.isEmpty { return url }
            if !item.relatedImageUrl.isEmpty { return item.relatedImageUrl }
        }
        return ""
    }

    private static func needlesForQaSubject(_ name: String) -> [String] {
        var out: [String] = []
        func add(_ raw: String) {
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty, !out.contains(n) { out.append(n) }
        }
        add(name)
        let key = normalizeSubjectKey(name)
        for (alias, canonical) in subjectAliases {
            let canonicalKey = normalizeSubjectKey(canonical)
            if name == canonical
                || key == canonicalKey
                || (!canonicalKey.isEmpty && key.contains(canonicalKey))
                || (!key.isEmpty && canonicalKey.contains(key))
                || name.contains(alias) {
                add(alias)
                add(canonical)
            }
        }
        return out
    }

    private static func normalizeSubjectKey(_ value: String) -> String {
        value.lowercased().filter { ch in
            !" 　（）()【】[]{}".contains(ch)
        }
    }
}

struct QaChoice: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
}

struct QaChatConfig {
    var providers: [QaChoice] = [QaChoice(key: "qwen", label: "通义千问")]
    var modes: [QaChoice] = [QaChoice(key: "answer", label: "答案模式")]
    var defaultProvider: String = "qwen"
    var defaultMode: String = "answer"
    var modeProviders: [String: String] = [:]
}

struct QaAgentItem {
    let id: Int
    let name: String
    let welcomeMessage: String
}

struct QaAgentListResult {
    var agents: [QaAgentItem]
    var subjects: [String]
    var unmatched: [String]
    var qaConfig: QaChatConfig
}

struct QaSubjectHint {
    var status: String
    var message: String
    var subjects: [String]
    var unmatched: [String]
}

struct ConversationDetailResult {
    var messages: [ChatMessage]
    var sessionId: String
    var agentId: Int
    var favoriteId: Int
    var wrongId: Int
}

struct FavoriteToggleResult {
    var ok: Bool
    var active: Bool = false
    var id: Int = 0
}
