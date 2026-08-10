import SwiftUI
import UIKit

// MARK: - 测评页容器（对齐 Android fillMaxSize + statusBarsPadding）
private struct AssessmentScreenContainer<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - 4pt 进度条（对齐 Android LinearProgressIndicator height=4dp，避免系统 ProgressView 额外高度）
private struct AssessmentThinProgressBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color(hex: "E5E7EB")
                Color(hex: "00D7CD")
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - 测评首页
struct AssessmentHomeView: View {
    let onBack: () -> Void
    var onStartAssessment: (Int) -> Void = { _ in }
    var onOpenSummary: () -> Void = {}

    @State private var progress: [Int: Int] = [:]
    @State private var showIncompleteHint = false

    private var assessmentItems: [AssessmentItem] {
        AssessmentStore.loadConfigs().map(\.item)
    }

    private var completedCount: Int { progress.count }
    private var totalCount: Int { assessmentItems.count }
    private var isAllComplete: Bool { totalCount > 0 && completedCount == totalCount }
    private var progressPercent: Int { totalCount == 0 ? 0 : (completedCount * 100 / totalCount) }

    var body: some View {
        AssessmentScreenContainer(background: Color(hex: "F9FAFB")) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    assessmentTopBar

                    assessmentHeroCard

                    Text("专项探索")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)

                    ForEach(assessmentItems) { item in
                        assessmentRow(item: item, completed: progress[item.id] != nil)
                    }

                    Button(action: loadProgress) {
                        Text("刷新测评进度")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 24)
                }
            }
        }
        .onAppear { loadProgress() }
        .alert("提示", isPresented: $showIncompleteHint) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("完成全部专项后可查看综合报告")
        }
    }

    private var assessmentTopBar: some View {
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
            Text("学习能力测试")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "111827"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var assessmentHeroCard: some View {
        let heroDesc = isAllComplete
            ? "你的五维雷达图和深度分析报告已生成。"
            : "完成所有 5 项测评以解锁你的能力雷达图。 (\(completedCount)/\(totalCount))"

        return VStack(alignment: .leading, spacing: 0) {
            Text("全维度综合素质评估")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isAllComplete ? .white : Color(hex: "1F2937"))

            Spacer().frame(height: 8)

            Text(heroDesc)
                .font(.system(size: 12))
                .foregroundColor(isAllComplete ? Color.white.opacity(0.8) : Color(hex: "6B7280"))

            Spacer().frame(height: 12)

            if isAllComplete {
                HStack(spacing: 6) {
                    Text("查看报告")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "00AFA4"))
                    Text("›")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "00AFA4"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white))
            } else {
                AssessmentThinProgressBar(value: Double(progressPercent) / 100.0)
            }
        }
        .padding(16)
        .background(isAllComplete ? Color(hex: "00AFA4") : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isAllComplete ? Color.clear : Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture {
            if isAllComplete { onOpenSummary() } else { showIncompleteHint = true }
        }
    }

    private func assessmentRow(item: AssessmentItem, completed: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                assessmentIcon(for: item.iconName)
                    .frame(width: 33, height: 33)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(completed ? Color(hex: "6B7280") : Color(hex: "1F2937"))
                    .lineSpacing(1)
                if completed {
                    Text("得分: \(progress[item.id] ?? 0) / \(item.maxScore)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "9CA3AF"))
                        .lineSpacing(1)
                } else {
                    Text("约 \(item.durationMinutes) 分钟 • \(item.totalQuestions) 道题")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "9CA3AF"))
                        .lineSpacing(1)
                }
            }

            Spacer(minLength: 0)

            Text(completed ? "✓" : "›")
                .font(.system(size: 19))
                .foregroundColor(completed ? Color(hex: "10B981") : Color(hex: "D1D5DB"))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "F3F4F6"), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onStartAssessment(item.id) }
    }

    private func loadProgress() {
        progress = AssessmentStore.loadProgress()
    }

    @ViewBuilder
    private func assessmentIcon(for name: String) -> some View {
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
        } else {
            Image(systemName: assessmentSystemIcon(for: name))
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(hex: "00AFA4"))
        }
    }

    private func assessmentSystemIcon(for name: String) -> String {
        switch name {
        case "ceping_target": return "scope"
        case "ceping_brain": return "lightbulb.fill"
        case "ceping_zap": return "bolt.fill"
        case "ceping_merge": return "arrow.triangle.branch"
        case "ceping_shield": return "shield.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - 测评题目页
struct AssessmentQuestionView: View {
    let assessmentId: Int
    let onQuit: () -> Void
    let onFinish: (Int, Int) -> Void

    @State private var currentPage = 0
    @State private var answers: [Int: Int] = [:]
    @State private var showIncompletePageHint = false

    private let pageSize = 10

    private var config: AssessmentConfig {
        AssessmentStore.config(for: assessmentId) ?? AssessmentStore.loadConfigs().first!
    }

    private var questions: [AssessmentQuestion] { config.questions }
    private var options: [AssessmentOption] { config.options }
    private var totalPages: Int { max(1, (questions.count + pageSize - 1) / pageSize) }
    private var isLastPage: Bool { currentPage == totalPages - 1 }

    private var currentPageQuestions: [AssessmentQuestion] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, questions.count)
        guard start < end else { return [] }
        return Array(questions[start..<end])
    }

    private var canGoNext: Bool {
        currentPageQuestions.allSatisfy { answers[$0.id] != nil }
    }

    var body: some View {
        AssessmentScreenContainer(background: Color(hex: "F9FAFB")) {
            VStack(spacing: 0) {
                questionTopBar

                AssessmentThinProgressBar(value: Double(currentPage + 1) / Double(totalPages))

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(currentPageQuestions) { question in
                            questionCard(question: question)
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                questionBottomBar
            }
        }
        .alert("提示", isPresented: $showIncompletePageHint) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("请完成本页所有题目")
        }
    }

    private var questionTopBar: some View {
        HStack {
            Button(action: { currentPage > 0 ? (currentPage -= 1) : onQuit() }) {
                Text("‹")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "9CA3AF"))
            }
            .buttonStyle(.plain)

            Text("第 \(currentPage + 1) / \(totalPages) 页")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "6B7280"))

            Spacer(minLength: 0)
                .frame(width: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var questionBottomBar: some View {
        VStack(spacing: 8) {
            Text("请选择最符合你当前状态的选项")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "9CA3AF"))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                Button(action: { if currentPage > 0 { currentPage -= 1 } }) {
                    Text("上一页")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "6B7280"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "F3F4F6")))
                }
                .buttonStyle(.plain)
                .disabled(currentPage <= 0)
                .opacity(currentPage > 0 ? 1 : 0.5)

                Button(action: handleSubmit) {
                    Text(isLastPage ? "提交" : "下一页")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(canGoNext ? Color(hex: "00D7CD") : Color(hex: "00D7CD").opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func questionCard(question: AssessmentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(question.id)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "00D7CD")))

                if !question.content.isEmpty {
                    Text(question.content)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "1F2937"))
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A：\(question.optionA)")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "1F2937"))
                            .lineSpacing(7)
                        Text("B：\(question.optionB)")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "1F2937"))
                            .lineSpacing(7)
                    }
                }
            }

            Spacer().frame(height: 10)

            HStack(spacing: 6) {
                ForEach(options) { option in
                    let selected = answers[question.id] == option.value
                    Button(action: { answers[question.id] = option.value }) {
                        Text(option.label)
                            .font(.system(size: 10, weight: selected ? .bold : .regular))
                            .foregroundColor(selected ? Color(hex: "00D7CD") : Color(hex: "6B7280"))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? Color(hex: "F0FDFA") : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selected ? Color(hex: "00D7CD") : Color(hex: "E5E7EB"), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }

    private func handleSubmit() {
        guard canGoNext else {
            showIncompletePageHint = true
            return
        }
        if isLastPage {
            let totalScore = questions.reduce(0) { sum, q in
                let answer = answers[q.id] ?? 0
                return sum + (q.reverse && answer > 0 ? 6 - answer : answer)
            }
            onFinish(assessmentId, totalScore)
        } else {
            currentPage += 1
        }
    }
}

// MARK: - 测评报告页
struct AssessmentReportView: View {
    let assessmentId: Int
    let score: Int
    let onBackHome: () -> Void

    private var assessment: AssessmentItem {
        AssessmentStore.config(for: assessmentId)?.item ?? AssessmentStore.loadConfigs().first!.item
    }

    private var percent: Float {
        assessment.maxScore > 0 ? Float(score) * 100 / Float(assessment.maxScore) : 0
    }

    private var levelInfo: (text: String, color: Color, desc: String, suggestion: String) {
        switch percent {
        case 80...: return ("极强", Color(hex: "059669"), "在长时间学习中能保持高度专注且不受干扰，可全面精准捕捉学习材料的关键信息。", "可以挑战跨学科多任务，继续保持优秀的学习能力。")
        case 60..<80: return ("较强", Color(hex: "F97316"), "长时间学习时注意力基本稳定，偶有走神也能快速调整，能抓住学习材料核心。", "定时核对学习目标，减少走神次数，训练信息筛选能力。")
        case 40..<60: return ("一般", Color(hex: "F97316"), "长时间学习时注意力容易波动，需要自我提醒才能维持专注。", "用番茄钟做短时专注训练，先做单任务再练双任务。")
        default: return ("较弱", Color(hex: "EF4444"), "长时间学习时难以集中注意力，易受外界干扰且需要他人督促。", "选择安静环境，分段专注学习，拆解任务执行。")
        }
    }

    var body: some View {
        AssessmentScreenContainer(background: Color.white) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Text(assessment.title)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "9CA3AF"))

                            Spacer().frame(height: 4)

                            Text("\(score)")
                                .font(.system(size: 52, weight: .bold))
                                .foregroundColor(Color(hex: "00D7CD"))

                            Text("满分 \(assessment.maxScore)")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "9CA3AF"))

                            Spacer().frame(height: 8)

                            Text(levelInfo.text)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(levelInfo.color)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(levelInfo.color.opacity(0.15)))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                        Spacer().frame(height: 16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("结果分析")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(hex: "1F2937"))
                            Text(levelInfo.desc)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "4B5563"))
                                .lineSpacing(8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)

                        Spacer().frame(height: 16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("提升建议")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(hex: "1F2937"))
                            Text(levelInfo.suggestion)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "0F766E"))
                                .lineSpacing(8)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "F0FDFA")))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "CCFBF1"), lineWidth: 1))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button(action: onBackHome) {
                    Text("返回测评首页")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "00D7CD")))
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
    }
}

// MARK: - 综合画像页
struct AssessmentSummaryView: View {
    let onBackHome: () -> Void

    @State private var reports: [(item: AssessmentItem, score: Int, level: String)] = []
    @State private var saveMessage = ""
    @State private var showSaveResult = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        AssessmentScreenContainer(background: Color(hex: "F0FDFA")) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Text("综合能力画像")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.8))
                        Text(archetype)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text("你的专属核心竞争力标签")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .background(Color(hex: "00AFA4"))

                    VStack(spacing: 10) {
                        radarChartArea
                        ForEach(reports, id: \.item.id) { report in
                            scoreBar(report: report)
                        }
                    }
                    .padding(14)

                    HStack(spacing: 10) {
                        Button(action: saveReport) {
                            Text("保存/分享报告")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "4B5563"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "E5E7EB"), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button(action: onBackHome) {
                            Text("返回首页")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "00AFA4")))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)

                    Text("保存路径：\(AssessmentStore.saveLocationHint)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "6B7280"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)

                    Spacer().frame(height: 16)
                }
            }
        }
        .onAppear { loadReports() }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareURL = nil }) {
            if let url = shareURL {
                ReportShareSheet(items: [url])
            }
        }
        .alert("提示", isPresented: $showSaveResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(saveMessage)
        }
    }

    private var archetype: String {
        guard let best = reports.max(by: { $0.score < $1.score }) else { return "均衡发展者" }
        switch best.item.id {
        case 1: return "深度潜伏者"
        case 2: return "战略思想家"
        case 3: return "自燃型行动派"
        case 4: return "超级连接者"
        case 5: return "高成就者"
        default: return "均衡发展者"
        }
    }

    private var radarChartArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("五维雷达图")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "1F2937"))

            AssessmentRadarChartView(reports: reports)
                .frame(height: 220)
                .frame(maxWidth: .infinity)

            ForEach(reports, id: \.item.id) { report in
                radarReportRow(report: report)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }

    private func radarReportRow(report: (item: AssessmentItem, score: Int, level: String)) -> some View {
        let pct = report.item.maxScore > 0 ? report.score * 100 / report.item.maxScore : 0
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(colorFor(report.item.id))
                .frame(width: 8, height: 8)
            Text("\(report.item.title)：\(report.score)/\(report.item.maxScore)（\(pct)%）·\(report.level)")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "4B5563"))
        }
        .padding(.vertical, 2)
    }

    private func scoreBar(report: (item: AssessmentItem, score: Int, level: String)) -> some View {
        let pct = report.item.maxScore > 0 ? Float(report.score) / Float(report.item.maxScore) : 0
        let lvlColor: Color = {
            switch report.level {
            case "极强": return Color(hex: "059669")
            case "较强", "一般": return Color(hex: "F97316")
            default: return Color(hex: "EF4444")
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(report.item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "1F2937"))
                Spacer(minLength: 0)
                Text(report.level)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(lvlColor)
            }
            Text("得分 \(report.score) / \(report.item.maxScore)")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "00AFA4"))
            AssessmentThinProgressBar(value: Double(min(pct, 1.0)), height: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }

    private func colorFor(_ id: Int) -> Color {
        switch id {
        case 1: return Color(hex: "14B8A6")
        case 2: return Color(hex: "3B82F6")
        case 3: return Color(hex: "F97316")
        case 4: return Color(hex: "6366F1")
        case 5: return Color(hex: "10B981")
        default: return Color(hex: "00AFA4")
        }
    }

    private func levelText(for item: AssessmentItem, score: Int) -> String {
        let percent = item.maxScore > 0 ? score * 100 / item.maxScore : 0
        if percent >= 80 { return "极强" }
        if percent >= 60 { return "较强" }
        if percent >= 40 { return "一般" }
        return "较弱"
    }

    private func loadReports() {
        let items = AssessmentStore.loadConfigs().map(\.item)
        let progress = AssessmentStore.loadProgress()
        reports = items.map { item in
            let score = progress[item.id] ?? 0
            return (item, score, levelText(for: item, score: score))
        }
    }

    private func saveReport() {
        switch AssessmentStore.createSummaryReportFile(reports: reports, archetype: archetype) {
        case .success(let url):
            shareURL = url
            showShareSheet = true
        case .failure(let error):
            saveMessage = "保存失败：\(error.localizedDescription)"
            showSaveResult = true
        }
    }
}

// MARK: - 雷达图
private struct AssessmentRadarChartView: View {
    let reports: [(item: AssessmentItem, score: Int, level: String)]

    var body: some View {
        Canvas { context, size in
            guard reports.count >= 3 else { return }
            let safeReports = Array(reports.prefix(5))
            let values = safeReports.map { report -> CGFloat in
                guard report.item.maxScore > 0 else { return 0 }
                return min(max(CGFloat(report.score) / CGFloat(report.item.maxScore), 0), 1)
            }

            let count = safeReports.count
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.34

            func pointAt(index: Int, ratio: CGFloat) -> CGPoint {
                let angle = (-Double.pi / 2) + (2 * Double.pi * Double(index) / Double(count))
                return CGPoint(
                    x: center.x + cos(angle) * Double(radius * ratio),
                    y: center.y + sin(angle) * Double(radius * ratio)
                )
            }

            for level in 1...4 {
                let ratio = CGFloat(level) / 4
                var ring = Path()
                for i in safeReports.indices {
                    let p = pointAt(index: i, ratio: ratio)
                    if i == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
                }
                ring.closeSubpath()
                context.stroke(ring, with: .color(Color(hex: "E5E7EB")), lineWidth: 1)
            }

            for i in safeReports.indices {
                var line = Path()
                line.move(to: center)
                line.addLine(to: pointAt(index: i, ratio: 1))
                context.stroke(line, with: .color(Color(hex: "E5E7EB")), lineWidth: 1)
            }

            var valuePath = Path()
            for i in safeReports.indices {
                let p = pointAt(index: i, ratio: values[i])
                if i == 0 { valuePath.move(to: p) } else { valuePath.addLine(to: p) }
            }
            valuePath.closeSubpath()
            context.fill(valuePath, with: .color(Color(hex: "00AFA4").opacity(0.3)))
            context.stroke(valuePath, with: .color(Color(hex: "00AFA4")), lineWidth: 2)

            for i in safeReports.indices {
                let p = pointAt(index: i, ratio: values[i])
                let dot = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(colorFor(safeReports[i].item.id)))
            }
        }
    }

    private func colorFor(_ id: Int) -> Color {
        switch id {
        case 1: return Color(hex: "14B8A6")
        case 2: return Color(hex: "3B82F6")
        case 3: return Color(hex: "F97316")
        case 4: return Color(hex: "6366F1")
        case 5: return Color(hex: "10B981")
        default: return Color(hex: "00AFA4")
        }
    }
}

// MARK: - 报告分享（保存到「文件」、AirDrop 等）
private struct ReportShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
