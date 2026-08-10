import Foundation

/// 学习能力测评数据与进度管理，对齐 Android AssessmentScreens.kt
enum AssessmentStore {
    private static let progressKey = "assessment_progress"

    private static let metaMap: [Int: (title: String, duration: Int, iconName: String, fallbackDesc: String)] = [
        1: ("注意力控制", 4, "ceping_target", "评估你的专注力和抗干扰能力"),
        2: ("元认知能力", 5, "ceping_brain", "评估你的学习策略和自我监控能力"),
        3: ("自驱力", 4, "ceping_zap", "评估你的内在动机和自我激励能力"),
        4: ("跨学科迁移", 4, "ceping_merge", "评估你的知识整合和应用能力"),
        5: ("自我效能感", 4, "ceping_shield", "评估你的自信心和应对挑战的能力")
    ]

    static func loadConfigs() -> [AssessmentConfig] {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assessments = root["assessments"] as? [[String: Any]] else {
            return defaultConfigs()
        }

        let configs = assessments.compactMap { obj -> AssessmentConfig? in
            let id = obj["id"] as? Int ?? 0
            guard let meta = metaMap[id] else { return nil }

            let scoreRange = obj["scoreRange"] as? [String: Any]
            let item = AssessmentItem(
                id: id,
                title: meta.title,
                description: (obj["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? meta.fallbackDesc,
                totalQuestions: obj["totalQuestions"] as? Int ?? 0,
                minScore: scoreRange?["min"] as? Int ?? 0,
                maxScore: scoreRange?["max"] as? Int ?? 0,
                durationMinutes: meta.duration,
                iconName: meta.iconName
            )

            let questions = (obj["questions"] as? [[String: Any]] ?? [])
                .compactMap { q -> AssessmentQuestion? in
                    guard let qid = q["id"] as? Int else { return nil }
                    return AssessmentQuestion(
                        id: qid,
                        content: q["content"] as? String ?? "",
                        optionA: q["optionA"] as? String ?? "",
                        optionB: q["optionB"] as? String ?? "",
                        reverse: q["reverse"] as? Bool ?? false
                    )
                }
                .sorted { $0.id < $1.id }

            let options = (obj["options"] as? [[String: Any]] ?? [])
                .compactMap { op -> AssessmentOption? in
                    guard let value = op["value"] as? Int,
                          let label = op["label"] as? String else { return nil }
                    return AssessmentOption(value: value, label: label)
                }
                .sorted { $0.value < $1.value }

            guard !questions.isEmpty, !options.isEmpty else { return nil }
            return AssessmentConfig(item: item, questions: questions, options: options)
        }

        return configs.isEmpty ? defaultConfigs() : configs.sorted { $0.item.id < $1.item.id }
    }

    static func config(for assessmentId: Int) -> AssessmentConfig? {
        loadConfigs().first { $0.item.id == assessmentId }
    }

    static func loadProgress() -> [Int: Int] {
        guard let data = UserDefaults.standard.data(forKey: progressKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: dict.compactMap { key, value in
            guard let intKey = Int(key) else { return nil }
            return (intKey, value)
        })
    }

    static func saveScore(assessmentId: Int, score: Int) {
        var map = loadProgress()
        map[assessmentId] = score
        let stringDict = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: progressKey)
        }
    }

    static func saveSummaryReport(reports: [(item: AssessmentItem, score: Int, level: String)], archetype: String) -> Result<String, Error> {
        switch createSummaryReportFile(reports: reports, archetype: archetype) {
        case .success(let url):
            return .success("报告已保存：\(url.lastPathComponent)")
        case .failure(let error):
            return .failure(error)
        }
    }

    static func createSummaryReportFile(
        reports: [(item: AssessmentItem, score: Int, level: String)],
        archetype: String
    ) -> Result<URL, Error> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let ts = formatter.string(from: Date())
        let fileName = "assessment_report_\(ts).txt"
        let content = summaryReportContent(reports: reports, archetype: archetype, timestamp: ts)

        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("assessment-reports", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(fileName)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .success(fileURL)
        } catch {
            return .failure(error)
        }
    }

    static func summaryReportContent(
        reports: [(item: AssessmentItem, score: Int, level: String)],
        archetype: String,
        timestamp: String? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let ts = timestamp ?? formatter.string(from: Date())

        var content = "绩满满 - 综合能力测评报告\n"
        content += "保存时间：\(ts)\n"
        content += "能力画像：\(archetype)\n"
        content += "----------------------------------------\n"
        for report in reports {
            let percent = report.item.maxScore > 0 ? report.score * 100 / report.item.maxScore : 0
            content += "\(report.item.title)：\(report.score)/\(report.item.maxScore)（\(percent)%） 等级：\(report.level)\n"
        }
        return content
    }

    static var saveLocationHint: String { "可通过分享保存到「文件」App" }

    private static func defaultConfigs() -> [AssessmentConfig] {
        [
            AssessmentConfig(
                item: AssessmentItem(id: 1, title: "注意力控制", description: "评估你的专注力和抗干扰能力",
                                     totalQuestions: 1, minScore: 1, maxScore: 5, durationMinutes: 4, iconName: "ceping_target"),
                questions: [AssessmentQuestion(id: 1, content: "做需要耐心的任务（如写论文、解数学题）时，能长时间专注")],
                options: [
                    AssessmentOption(value: 1, label: "非常不符合"),
                    AssessmentOption(value: 2, label: "不太符合"),
                    AssessmentOption(value: 3, label: "一般"),
                    AssessmentOption(value: 4, label: "比较符合"),
                    AssessmentOption(value: 5, label: "非常符合")
                ]
            )
        ]
    }
}
