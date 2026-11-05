import SwiftUI

struct GradeBacktrackView: View {
    let onBack: () -> Void
    var onOpenHistory: () -> Void = {}

    @EnvironmentObject private var session: AcademicSession
    @State private var loading = true
    @State private var saving = false
    @State private var recognizing = false
    @State private var rules: [GpaRuleOption] = []
    @State private var selectedRuleId = 0
    @State private var planMode: PlanCalcMode = .cumulative
    @State private var currentSemester = ""
    @State private var targetAnchorSemester = ""
    @State private var targetGpaInput = "3.55"
    @State private var termTargetGpaInput = "3.70"
    @State private var totalCreditsInput = ""
    @State private var baselineGpa = ""
    @State private var baselineCredits = ""
    @State private var histTerms: [GpaTermRow] = []
    @State private var pastCourseMap: [String: [GpaCourseRow]] = [:]
    @State private var gpaCourses: [GpaCourseRow] = []
    @State private var pinned: [(String, String)] = []
    @State private var showRulePicker = false
    @State private var showTargetPicker = false
    @State private var showNumSheet = false
    @State private var numField = ""
    @State private var numValue = ""
    @State private var showFixSheet = false
    @State private var fixName = ""
    @State private var fixScore = ""
    @State private var fixDone = false
    @State private var showAddSheet = false
    @State private var addName = ""
    @State private var addCredit = "4"
    @State private var addCountsToGpa = true
    @State private var showSchedSheet = false
    @State private var showProfileSetup = false
    @State private var setupEnrollYear = ""
    @State private var setupEduSystem = ""
    @State private var setupSaving = false
    @State private var showSetupYearPicker = false
    @State private var showSetupEduPicker = false
    @State private var showSetupRulePicker = false
    @State private var schoolyearLocked = false
    @State private var savedRuleId = 0
    @State private var panelNeedsRule = false
    @State private var showImagePicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedImage: UIImage?
    @State private var schedRows: [GpaCourseRow] = []
    @State private var showHistorySheet = false
    @State private var histGpaDraft = ""
    @State private var histCreditDraft = ""
    @State private var futureCreditsInput: [String: String] = [:]
    @State private var planPreview: GpaPlanData?
    @State private var previewToken = 0

    private var selectedRule: GpaRuleOption? { rules.first { $0.id == selectedRuleId } }
    private var simple: Bool { AcademicCalc.isSimpleGpaRule(selectedRule) }
    private var maxGrade: Int { AcademicCalc.maxGradeByEducationSystem(session.educationSystem) }

    private func pinnedOf(_ name: String) -> String {
        pinned.first { $0.0 == name }?.1 ?? ""
    }

    private func setPinned(_ name: String, _ score: String) {
        if let idx = pinned.firstIndex(where: { $0.0 == name }) {
            if score.isEmpty { pinned.remove(at: idx) } else { pinned[idx] = (name, score) }
        } else if !score.isEmpty {
            pinned.append((name, score))
        }
    }

    private var reverse: ReverseCalc {
        let pastHist = AcademicCalc.pastHistoryStats(
            currentSemester: currentSemester,
            terms: histTerms,
            baselineGpa: baselineGpa,
            baselineCredits: baselineCredits,
            pastCoursesBySemester: pastCourseMap,
            rule: selectedRule
        )
        let formulaHistC = pastHist.src == "科目登记" ? 0.0 : pastHist.credits
        let formulaHistG = pastHist.src == "科目登记" ? 0.0 : pastHist.gpa
        let registered = AcademicCalc.gpaRowsForSemester(pastCourseMap, currentSemester)
        let termRows = AcademicCalc.termPlanRows(registered: registered, planned: gpaCourses)
        let termC = AcademicCalc.subjectRegisterCredits(termRows)
        var fixedC = 0.0
        var fixedP = 0.0
        var fixedN = 0
        for row in termRows {
            let exam = Double(row.examScore)
            let pin = Double(pinnedOf(row.subjectName))
            let score = exam ?? pin
            let gp = AcademicCalc.scoreToGpaPoint(score, rule: selectedRule)
            let cr = Double(row.credits) ?? 0
            if let gp, cr > 0 {
                fixedC += cr
                fixedP += gp * cr
                fixedN += 1
            }
        }
        let isNow = targetAnchorSemester.isEmpty || targetAnchorSemester == currentSemester
        let target = planMode == .cumulative
            ? (Double(targetGpaInput) ?? 0)
            : (Double(termTargetGpaInput) ?? 0)
        return AcademicCalc.computeReverse(
            cum: planMode == .cumulative,
            isNow: isNow,
            target: target,
            histG: formulaHistG,
            histC: formulaHistC,
            histSrc: pastHist.src,
            termC: termC,
            totalCredits: Double(totalCreditsInput) ?? (pastHist.credits + termC),
            fixedC: fixedC,
            fixedP: fixedP,
            fixedN: fixedN,
            simple: simple
        )
    }

    private var pastHist: PastHistoryStats {
        AcademicCalc.pastHistoryStats(
            currentSemester: currentSemester,
            terms: histTerms,
            baselineGpa: baselineGpa,
            baselineCredits: baselineCredits,
            pastCoursesBySemester: pastCourseMap,
            rule: selectedRule
        )
    }

    private var pastRegistered: [(String, GpaCourseRow)] {
        pastCourseMap
            .filter { AcademicCalc.isPastGpaSemester($0.key, current: currentSemester) }
            .sorted { a, b in
                (gpaSemesterOrder.firstIndex(of: a.key.trimmingCharacters(in: .whitespaces)) ?? 99)
                    < (gpaSemesterOrder.firstIndex(of: b.key.trimmingCharacters(in: .whitespaces)) ?? 99)
            }
            .flatMap { sem, rows in
                rows.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }.map { (sem, $0) }
            }
    }

    private var pendingCredits: Double {
        let histC = pastHist.credits
        let scored = histC + gpaCourses.reduce(0) { acc, row in
            acc + (Double(row.examScore) != nil ? (Double(row.credits) ?? 0) : 0)
        }
        return max(reverse.total - scored, 0)
    }

    private var bandText: String {
        reverse.need <= 0 ? "60分保底" : (reverse.band?.text ?? "—")
    }

    private var futureLabel: String {
        let isNow = targetAnchorSemester.isEmpty || targetAnchorSemester == currentSemester
        let futureList = isNow ? [] : AcademicCalc.futureSemestersInclusive(current: currentSemester, target: targetAnchorSemester, maxGrade: maxGrade)
        guard futureList.count > 1 else { return "" }
        return "\(AcademicCalc.displayGpaSemesterName(futureList[1])) ~ \(AcademicCalc.displayGpaSemesterName(futureList.last ?? ""))"
    }

    var body: some View {
        ZStack {
            AcademicPalette.page.ignoresSafeArea()
            pageContent
            if showProfileSetup && !loading { profileOverlay }
            pickerOverlay
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $pickedImage, sourceType: pickerSource)
        }
        .onChange(of: pickedImage) { image in
            guard let image else { return }
            pickedImage = nil
            runSchedOcr(image)
        }
        .task { await reload() }
        .onDisappear { persistPlan() }
        .onChange(of: targetGpaInput) { _ in schedulePreview() }
        .onChange(of: termTargetGpaInput) { _ in schedulePreview() }
        .onChange(of: targetAnchorSemester) { _ in schedulePreview() }
        .onChange(of: planMode) { _ in schedulePreview() }
        .onChange(of: gpaCourses.count) { _ in schedulePreview() }
    }

    private var pageContent: some View {
        VStack(spacing: 0) {
            ProfileSimpleTopBar(title: "成绩目标", onBack: onBack, barBackground: .clear)
            if loading {
                Spacer()
                ProgressView().tint(AcademicPalette.teal)
                Spacer()
            } else {
                loadedScroll
            }
        }
        .background(AcademicPalette.page.ignoresSafeArea())
    }

    private var loadedScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                AcademicCompactToolbar(
                    semesterLabel: AcademicCalc.displayGpaSemesterBadge(currentSemester),
                    ruleLabel: AcademicCalc.displayGpaRuleName(selectedRule),
                    semesterEnabled: false,
                    onSemesterClick: {},
                    onRuleClick: { if !rules.isEmpty { showRulePicker = true } }
                )
                AcademicSegmentControl(
                    options: PlanCalcMode.allCases.map(\.label),
                    selectedIndex: planMode.rawValue
                ) { planMode = PlanCalcMode(rawValue: $0) ?? .cumulative }
                hero(reverse, pendingCredits: pendingCredits)
                targetCard
                AcademicSectionCard(
                    title: "本学期课程",
                    extra: !gpaCourses.isEmpty ? "\(gpaCourses.count) 门" : (!pastRegistered.isEmpty ? "已登记 \(pastRegistered.count) 门" : "0 门")
                ) {
                    courseList(o: reverse, bandText: bandText, futureLabel: futureLabel)
                }
                HStack(spacing: 10) {
                    AcademicPrimaryButton(title: "添加课程") {
                        addName = ""
                        addCredit = "4"
                        addCountsToGpa = true
                        showAddSheet = true
                    }
                    AcademicSecondaryButton(title: "上传课表") {
                        schedRows = []
                        showSchedSheet = true
                    }
                    .frame(width: 120)
                }
                if !reverse.cum {
                    Text("点某科可改分数或指定稳拿，其余实时重算")
                        .font(.system(size: 12))
                        .foregroundColor(AcademicPalette.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var pickerOverlay: AnyView {
        if showRulePicker { return AnyView(ruleSheet) }
        if showTargetPicker { return AnyView(targetSheet) }
        if showNumSheet { return AnyView(numSheet) }
        if showFixSheet { return AnyView(fixSheet) }
        if showAddSheet { return AnyView(addSheet) }
        if showSchedSheet { return AnyView(schedSheet) }
        if showHistorySheet { return AnyView(historySheet) }
        if showSetupYearPicker { return AnyView(yearSheet) }
        if showSetupEduPicker { return AnyView(eduSheet) }
        if showSetupRulePicker { return AnyView(setupRuleSheet) }
        return AnyView(EmptyView())
    }

    @ViewBuilder
    private var targetCard: some View {
        AcademicSectionCard(title: "目标") {
            if reverse.cum {
                AcademicSettingRow(label: "累计 GPA", value: String(format: "%.2f", reverse.target), accent: true, chevron: "›") {
                    numField = "targetGpa"
                    numValue = targetGpaInput
                    showNumSheet = true
                }
                AcademicSettingRow(
                    label: "截止学期",
                    value: AcademicCalc.displayGpaSemesterName(targetAnchorSemester.isEmpty ? currentSemester : targetAnchorSemester),
                    chevron: "▾"
                ) { showTargetPicker = true }
                if reverse.isNow {
                    AcademicSettingRow(label: "总学分", value: String(format: "%.0f", reverse.total), auto: "自动")
                } else {
                    AcademicSettingRow(label: "总学分", value: String(format: "%.0f", reverse.total), chevron: "›") {
                        numField = "totalCredits"
                        numValue = totalCreditsInput
                        showNumSheet = true
                    }
                }
                                    AcademicSettingRow(label: "历史成绩", value: historyValue(reverse), accent: true) {
                                        onOpenHistory()
                                    }
            } else {
                AcademicSettingRow(label: "本学期 GPA", value: String(format: "%.2f", reverse.target), accent: true, chevron: "›") {
                    numField = "termTargetGpa"
                    numValue = termTargetGpaInput
                    showNumSheet = true
                }
            }
            if let hint = planPreview?.hintMessage, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(AcademicPalette.muted)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func hero(_ o: ReverseCalc, pendingCredits: Double) -> some View {
        let pack = heroPack(o, pendingCredits: pendingCredits)
        AcademicHeroCard(
            title: pack.title,
            gpaValue: pack.big,
            unit: pack.unit,
            band: pack.band,
            footLeft: pack.footL,
            footRight: pack.footR,
            warn: !o.reachable
        )
    }

    private func heroPack(_ o: ReverseCalc, pendingCredits: Double) -> (title: String, big: String, unit: String, band: String, footL: String, footR: String) {
        if !o.reachable {
            if o.restC <= 0 {
                return (
                    "所有科目已确定 · 仍差目标",
                    String(format: "-%.2f", max(o.target * o.total - o.histG * o.histC - o.fixedP, 0)),
                    "绩点学分",
                    "建议调低目标或调整已定分数",
                    "已锁定 \(o.fixedN) 门",
                    o.cum ? "按累计" : "按本学期"
                )
            }
            return (
                "目标无法达成",
                String(format: "%.2f", o.maxGpa),
                o.cum ? "累计最高" : "本学期最高",
                "即使待考全满分 · 也只能到这",
                "待考 \(AcademicCalc.formatGpaCredits(pendingCredits)) 学分",
                "建议调低目标"
            )
        }
        if o.restC <= 0 {
            return (
                o.cum ? "累计 GPA" : "本学期 GPA",
                String(format: "%.2f", o.target),
                o.cum ? "目标" : "本学期",
                "所有科目已确定 · 目标已达成 ✓",
                "已锁定 \(o.fixedN) 门",
                o.cum ? String(format: "%.0f 总学分", o.total) : "本学期"
            )
        }
        if o.need <= 0 {
            return (
                o.cum ? "剩余待考" : "本学期需",
                "60",
                "分保底即可",
                "已锁定目标 · 轻松达成 ✓",
                "已锁定 \(o.fixedN) 门",
                "\(AcademicCalc.formatGpaCredits(pendingCredits)) 学分待考"
            )
        }
        if o.cum {
            return (
                o.isNow ? "本学期 · 需平均考到" : "剩余待考 · 需平均考到",
                String(format: "%.2f", o.need),
                "绩点",
                "\(o.band?.min ?? 0) 分起 · \(o.band?.text ?? "")",
                (o.fixedN > 0 ? "已锁 \(o.fixedN) 门 · " : "") + "待考 \(AcademicCalc.formatGpaCredits(pendingCredits)) 学分",
                String(format: "%.0f 总学分", o.total)
            )
        }
        return (
            "每门课需考到",
            "\(o.band?.min ?? 0)",
            "分起",
            "\(o.band?.text ?? "") · 本学期 GPA = \(String(format: "%.1f", o.target))",
            String(format: "%.0f 学分 · %d 门", o.termC, gpaCourses.count),
            o.fixedN > 0 ? "已锁 \(o.fixedN)" : ""
        )
    }

    private func historyValue(_ o: ReverseCalc) -> String {
        if o.histC > 0 && o.histSrc != "科目登记" {
            return String(format: "%.2f · %@ 学分  ✎", o.histG, AcademicCalc.formatGpaCredits(o.histC))
        }
        if pastHist.credits > 0 && pastHist.src == "科目登记" {
            return "\(AcademicCalc.formatGpaCredits(pastHist.credits)) 学分 · 待录入成绩  ✎"
        }
        if !pastRegistered.isEmpty {
            return "已登记 \(pastRegistered.count) 门 · 待录入成绩  ✎"
        }
        return "未录入  ✎"
    }

    @ViewBuilder
    private func courseList(o: ReverseCalc, bandText: String, futureLabel: String) -> some View {
        if gpaCourses.isEmpty && pastRegistered.isEmpty {
            Text("还没有课程，可添加或上传课表")
                .font(.system(size: 13))
                .foregroundColor(AcademicPalette.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if gpaCourses.isEmpty {
            Text("当前学期还没有科目，以下为科目登记已录入的历史学期")
                .font(.system(size: 12))
                .foregroundColor(AcademicPalette.dim)
                .padding(.bottom, 8)
            ForEach(Array(pastRegistered.enumerated()), id: \.offset) { index, item in
                pastRegisteredRow(index: index, item: item)
            }
        }
        ForEach(Array(gpaCourses.enumerated()), id: \.offset) { index, row in
            currentCourseRow(index: index, row: row, bandText: bandText)
        }
        if o.cum && o.futureC > 0 {
            HStack {
                Text(futureLabel).font(.system(size: 13)).foregroundColor(AcademicPalette.muted)
                Spacer()
                Text(o.reachable ? String(format: "%.0f 学分 · 平均%.2f", o.futureC, o.need) : "——")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(o.reachable ? AcademicPalette.acc : AcademicPalette.dim)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(AcademicPalette.hintBg)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(hex: "00A691").opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .padding(.top, 10)
        }
    }

    private func pastRegisteredRow(index: Int, item: (String, GpaCourseRow)) -> some View {
        let exam = item.1.examScore.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 0) {
            if index > 0 { Color(hex: "0F172A").opacity(0.08).frame(height: 0.5) }
            reverseCourseRow(
                name: item.1.subjectName,
                credits: item.1.credits.isEmpty ? "—" : item.1.credits,
                score: exam.isEmpty ? "—" : "\(exam)分",
                status: AcademicCalc.displayGpaSemesterName(item.0) + (exam.isEmpty ? " · 待录入" : " · 已出分")
            ) {}
        }
    }

    private func currentCourseRow(index: Int, row: GpaCourseRow, bandText: String) -> some View {
        let exam = row.examScore
        let pin = pinnedOf(row.subjectName)
        let pair: (String, String) = {
            if !exam.isEmpty { return ("\(exam)分", "已出分") }
            if !pin.isEmpty { return ("\(pin)分", "已定 ✎") }
            return (bandText, "待考")
        }()
        return VStack(spacing: 0) {
            if index > 0 { Color(hex: "0F172A").opacity(0.08).frame(height: 0.5) }
            reverseCourseRow(name: row.subjectName, credits: row.credits.isEmpty ? "0" : row.credits, score: pair.0, status: pair.1) {
                fixName = row.subjectName
                fixDone = !exam.isEmpty
                fixScore = exam.isEmpty ? pin : exam
                showFixSheet = true
            }
        }
    }

    private func reverseCourseRow(name: String, credits: String, score: String, status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .medium)).foregroundColor(AcademicPalette.ink)
                    Text("\(credits) 学分 · \(status)")
                        .font(.system(size: 11))
                        .foregroundColor(AcademicPalette.dim)
                }
                Spacer()
                Text(score)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AcademicPalette.teal)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var ruleSheet: some View {
        AcademicSheet(title: "GPA 计算方式", onDismiss: { showRulePicker = false }) {
            VStack(spacing: 8) {
                ForEach(rules) { rule in
                    AcademicOptionRow(
                        title: AcademicCalc.displayGpaRulePickerLabel(rule),
                        selected: rule.id == selectedRuleId
                    ) {
                        selectedRuleId = rule.id
                        showRulePicker = false
                        persistGpa()
                        persistPlan()
                    }
                }
            }
        }
    }

    private var targetSheet: some View {
        AcademicSheet(title: "截止学期", onDismiss: { showTargetPicker = false }) {
            let terms = AcademicCalc.futureSemestersInclusive(current: currentSemester, target: "大\(maxGrade)下", maxGrade: maxGrade)
            VStack(spacing: 8) {
                ForEach(terms, id: \.self) { code in
                    AcademicOptionRow(
                        title: AcademicCalc.displayGpaSemesterName(code),
                        selected: code == (targetAnchorSemester.isEmpty ? currentSemester : targetAnchorSemester)
                    ) {
                        targetAnchorSemester = code
                        showTargetPicker = false
                        persistPlan()
                    }
                }
            }
        }
    }

    private var numSheet: some View {
        AcademicSheet(title: "输入数值", onDismiss: { showNumSheet = false }) {
            AcademicLabeledField(label: "数值", text: $numValue, keyboard: .decimalPad)
            AcademicPrimaryButton(title: "确定") {
                switch numField {
                case "targetGpa": targetGpaInput = numValue
                case "termTargetGpa": termTargetGpaInput = numValue
                case "totalCredits": totalCreditsInput = numValue
                default: break
                }
                showNumSheet = false
                persistPlan()
            }
        }
    }

    private var fixSheet: some View {
        AcademicSheet(title: fixName, onDismiss: { showFixSheet = false }) {
            if fixDone {
                Text("该科已出分，不能改锁定分")
                    .font(.system(size: 13))
                    .foregroundColor(AcademicPalette.muted)
            } else {
                AcademicLabeledField(label: "指定分数", text: $fixScore, placeholder: "如 85", keyboard: .decimalPad)
                AcademicPrimaryButton(title: "锁定该分数") {
                    setPinned(fixName, fixScore.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0.isNumber || $0 == "." })
                    showFixSheet = false
                    persistPlan()
                }
                Button("清除锁定") {
                    setPinned(fixName, "")
                    showFixSheet = false
                    persistPlan()
                }
                .font(.system(size: 13))
                .foregroundColor(AcademicPalette.muted)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var addSheet: some View {
        AcademicSheet(title: "添加课程", onDismiss: { showAddSheet = false }) {
            AcademicLabeledField(label: "课程名称", text: $addName, placeholder: "科目全称")
            AcademicLabeledField(label: "学分", text: $addCredit, placeholder: "4", keyboard: .decimalPad)
            Button { addCountsToGpa.toggle() } label: {
                HStack {
                    Image(systemName: addCountsToGpa ? "checkmark.square.fill" : "square")
                        .foregroundColor(addCountsToGpa ? AcademicPalette.teal : AcademicPalette.dim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("计入GPA")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AcademicPalette.ink)
                        Text("不参与GPA的科目请取消勾选")
                            .font(.system(size: 12))
                            .foregroundColor(AcademicPalette.muted)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            AcademicPrimaryButton(title: "添加") {
                let name = addName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                guard let credit = Double(addCredit.trimmingCharacters(in: .whitespaces)), credit > 0 else {
                    academicToast("请填写有效学分")
                    return
                }
                if !gpaCourses.contains(where: { $0.subjectName == name }) {
                    gpaCourses.append(GpaCourseRow(
                        subjectName: name,
                        credits: addCredit.trimmingCharacters(in: .whitespaces),
                        examScore: "",
                        countsToGpa: addCountsToGpa ? "是" : "否"
                    ))
                    persistGpa()
                }
                addCountsToGpa = true
                showAddSheet = false
            }
        }
    }

    private var schedSheet: some View {
        AcademicSheet(title: "上传课表", onDismiss: { showSchedSheet = false }) {
            if recognizing {
                Text("识别中…").font(.system(size: 13)).foregroundColor(AcademicPalette.dim).frame(maxWidth: .infinity)
            } else if schedRows.isEmpty {
                AcademicSecondaryButton(title: "＋ 选择课表图片 · 可分多次传") {
                    pickerSource = .photoLibrary
                    showImagePicker = true
                }
                AcademicPrimaryButton(title: "拍照") {
                    pickerSource = .camera
                    showImagePicker = true
                }
            } else {
                AcademicSecondaryButton(title: "＋ 再传一张（识别失败可补传）") {
                    pickerSource = .photoLibrary
                    showImagePicker = true
                }
                let exist = Set(gpaCourses.map(\.subjectName))
                let addN = schedRows.filter { !exist.contains($0.subjectName) }.count
                let dupN = schedRows.count - addN
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(schedRows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.subjectName + (exist.contains(row.subjectName) ? "  已存在 · 跳过" : "  新增"))
                                .font(.system(size: 13))
                                .foregroundColor(AcademicPalette.ink)
                            Spacer()
                            Text("\(row.credits.isEmpty ? "—" : row.credits) 学分")
                                .font(.system(size: 13))
                                .foregroundColor(AcademicPalette.muted)
                        }
                    }
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "0F172A").opacity(0.06), lineWidth: 1))
                Text("识别汇总  新增 \(addN) 门 · 已存在 \(dupN) 门跳过")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AcademicPalette.acc)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AcademicPalette.hintBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                AcademicPrimaryButton(title: addN > 0 ? "补充 \(addN) 门到本学期" : "无新增科目", enabled: addN > 0) {
                    var names = Set(gpaCourses.map(\.subjectName))
                    for row in schedRows where !row.subjectName.isEmpty && !names.contains(row.subjectName) {
                        gpaCourses.append(GpaCourseRow(subjectName: row.subjectName, credits: row.credits.isEmpty ? "1" : row.credits, examScore: ""))
                        names.insert(row.subjectName)
                    }
                    persistGpa()
                    showSchedSheet = false
                }
            }
        }
    }

    private var historySheet: some View {
        AcademicSheet(title: "历史成绩", onDismiss: { showHistorySheet = false }) {
            AcademicLabeledField(label: "历史 GPA", text: $histGpaDraft, placeholder: "如 3.40", keyboard: .decimalPad)
            AcademicLabeledField(label: "历史学分", text: $histCreditDraft, placeholder: "如 48", keyboard: .decimalPad)
            AcademicPrimaryButton(title: "保存") {
                baselineGpa = histGpaDraft
                baselineCredits = histCreditDraft
                showHistorySheet = false
                Task {
                    _ = await AcademicApi.saveGpaBaseline(
                        semester: currentSemester,
                        gpa: baselineGpa,
                        credits: baselineCredits
                    )
                    persistPlan()
                }
            }
        }
    }

    private var profileOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("完善学籍后即可倒推")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AcademicPalette.ink)
                let needsYear = !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: schoolyearLocked)
                let needsEdu = !AcademicCalc.hasProfileEducationSystem(session.educationSystem)
                let needsRule = panelNeedsRule || savedRuleId <= 0
                if needsYear {
                    AcademicSettingRow(label: "入学年份", value: setupEnrollYear.isEmpty ? "请选择" : setupEnrollYear, chevron: "▾") {
                        showSetupYearPicker = true
                    }
                }
                if needsEdu {
                    AcademicSettingRow(label: "学制", value: setupEduSystem.isEmpty ? "请选择" : setupEduSystem, chevron: "▾") {
                        showSetupEduPicker = true
                    }
                }
                if needsRule {
                    AcademicSettingRow(label: "GPA 计算方式", value: AcademicCalc.displayGpaRuleName(selectedRule), chevron: "▾") {
                        showSetupRulePicker = true
                    }
                }
                AcademicPrimaryButton(title: setupSaving ? "保存中…" : "完成", enabled: !setupSaving, action: saveProfileSetup)
            }
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 28)
        }
    }

    private var yearSheet: some View {
        AcademicSheet(title: "入学年份", onDismiss: { showSetupYearPicker = false }) {
            VStack(spacing: 8) {
                ForEach(AcademicCalc.enrollmentYearOptions(), id: \.self) { year in
                    AcademicOptionRow(title: year, selected: setupEnrollYear == year) {
                        setupEnrollYear = year
                        showSetupYearPicker = false
                    }
                }
            }
        }
    }

    private var eduSheet: some View {
        AcademicSheet(title: "学制", onDismiss: { showSetupEduPicker = false }) {
            VStack(spacing: 8) {
                ForEach(educationSystemOptions, id: \.self) { item in
                    AcademicOptionRow(title: item, selected: setupEduSystem == item) {
                        setupEduSystem = item
                        showSetupEduPicker = false
                    }
                }
            }
        }
    }

    private var setupRuleSheet: some View {
        AcademicSheet(title: "GPA 计算方式", onDismiss: { showSetupRulePicker = false }) {
            VStack(spacing: 8) {
                ForEach(rules) { rule in
                    AcademicOptionRow(title: AcademicCalc.displayGpaRulePickerLabel(rule), selected: rule.id == selectedRuleId) {
                        selectedRuleId = rule.id
                        showSetupRulePicker = false
                    }
                }
            }
        }
    }

    private func persistGpa() {
        let snapshot = gpaCourses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
        Task {
            saving = true
            let result = await AcademicApi.submitGpaPanel(
                semester: currentSemester,
                ruleId: selectedRuleId,
                baselineGpa: "",
                baselineCredits: "",
                courses: snapshot
            )
            if case .failure(let error) = result {
                academicToast(error.localizedDescription)
            } else if snapshot.isEmpty {
                gpaCourses = []
            }
            saving = false
        }
    }

    private func persistPlan() {
        guard gpaCourses.contains(where: { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
        let target = planMode == .cumulative ? Double(targetGpaInput) : Double(termTargetGpaInput)
        guard let target else { return }
        Task {
            let registered = AcademicCalc.gpaRowsForSemester(pastCourseMap, currentSemester)
            let termRows = AcademicCalc.termPlanRows(registered: registered, planned: gpaCourses)
            let result = await AcademicApi.saveGpaPlan(
                targetSemester: targetAnchorSemester.isEmpty ? currentSemester : targetAnchorSemester,
                targetGpa: target,
                adjustments: termRows.map { row in
                    let pin = pinnedOf(row.subjectName)
                    return GpaPlanCourse(
                        semester: currentSemester,
                        subjectName: row.subjectName,
                        credits: Double(row.credits) ?? 0,
                        targetScore: pin,
                        locked: !pin.isEmpty && row.examScore.isEmpty,
                        creditText: row.credits,
                        countsToGpa: row.countsToGpa
                    )
                },
                baselineGpa: baselineGpa,
                baselineCredits: baselineCredits,
                ruleId: selectedRuleId,
                futureCredits: futureCreditsInput
            )
            if case .success(let preview) = result {
                planPreview = preview
            } else if case .failure(let error) = result {
                academicToast(error.localizedDescription)
            }
        }
    }

    private func schedulePreview() {
        previewToken += 1
        let token = previewToken
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard token == previewToken else { return }
            await runPreview()
        }
    }

    private func runPreview() async {
        let target = planMode == .cumulative ? Double(targetGpaInput) : Double(termTargetGpaInput)
        guard let target, target > 0 else { return }
        let registered = AcademicCalc.gpaRowsForSemester(pastCourseMap, currentSemester)
        let termRows = AcademicCalc.termPlanRows(registered: registered, planned: gpaCourses)
        let result = await AcademicApi.previewGpaPlan(
            targetSemester: targetAnchorSemester.isEmpty ? currentSemester : targetAnchorSemester,
            targetGpa: target,
            adjustments: termRows.map { row in
                let pin = pinnedOf(row.subjectName)
                return GpaPlanCourse(
                    semester: currentSemester,
                    subjectName: row.subjectName,
                    credits: Double(row.credits) ?? 0,
                    targetScore: pin,
                    locked: !pin.isEmpty && row.examScore.isEmpty,
                    creditText: row.credits,
                    countsToGpa: row.countsToGpa
                )
            },
            baselineGpa: baselineGpa,
            baselineCredits: baselineCredits,
            futureCredits: futureCreditsInput
        )
        if case .success(let preview) = result {
            planPreview = preview
        }
    }

    private func saveProfileSetup() {
        let needsYear = !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: schoolyearLocked)
        let needsEdu = !AcademicCalc.hasProfileEducationSystem(session.educationSystem)
        let needsRule = panelNeedsRule || savedRuleId <= 0
        let rule = selectedRuleId > 0 ? selectedRuleId : AcademicCalc.pickDefaultGpaRuleId(rules)
        let edu = setupEduSystem.isEmpty ? session.educationSystem : setupEduSystem
        if needsYear && setupEnrollYear.isEmpty && !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear) {
            academicToast("请选择入学年份")
            return
        }
        if needsEdu && edu.isEmpty {
            academicToast("请选择学制")
            return
        }
        if needsRule && rule <= 0 {
            academicToast("请选择 GPA 计算方式")
            return
        }
        Task {
            setupSaving = true
            let yearText = AcademicCalc.normalizeEnrollmentYear(setupEnrollYear)
                .ifEmpty(session.schoolyear > 0 ? String(session.schoolyear) : "")
                .ifEmpty(String(AcademicCalc.defaultEnrollmentYear()))
            let year = Int(yearText) ?? AcademicCalc.defaultEnrollmentYear()
            await AcademicApi.persistAcademicProfile(
                school: session.school,
                major: session.major,
                schoolyear: year,
                semester: currentSemester,
                educationSystem: edu
            )
            _ = await AcademicApi.saveGpaProfileSetup(schoolyear: year, ruleId: rule)
            session.apply(schoolyear: year, educationSystem: edu, semester: currentSemester)
            showProfileSetup = false
            setupSaving = false
            await reload()
        }
    }

    private func runSchedOcr(_ image: UIImage) {
        Task {
            recognizing = true
            guard let url = await AcademicApi.uploadImage(image) else {
                academicToast("上传失败")
                recognizing = false
                return
            }
            let asRegister = gpaCourses.map {
                SubjectRegisterRow(subjectName: $0.subjectName, credits: $0.credits)
            }
            let result = await AcademicApi.recognizeSubjectRegister(
                imageUrl: url,
                semester: currentSemester,
                courses: asRegister
            )
            switch result {
            case .success(let pair):
                schedRows = pair.1
                    .filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { $0.toGpaCourseRow() }
            case .failure(let error):
                academicToast(error.localizedDescription)
            }
            recognizing = false
        }
    }

    private func reload() async {
        loading = true
        rules = await AcademicApi.fetchGpaRules()
        await AcademicApi.syncAcademicSession(session)
        if session.school.isEmpty || session.major.isEmpty || session.semester.isEmpty {
            if let cached = AcademicApi.peekSubjectRegister(semester: session.semester) {
                session.applyFromRegister(cached)
            } else if case .success(let panel) = await AcademicApi.fetchSubjectRegister(semester: session.semester) {
                session.applyFromRegister(panel)
            }
        }
        let inferred = AcademicCalc.inferGpaSemesterCode(session.schoolyear)
        let semHint = inferred.isEmpty ? session.semester : inferred
        switch await AcademicApi.fetchGpaPanel(semester: semHint) {
        case .success(let panel):
            currentSemester = inferred.isEmpty ? (panel.semester.isEmpty ? semHint : panel.semester) : inferred
            schoolyearLocked = panel.schoolyearLocked
            if AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: panel.schoolyearLocked) {
                setupEnrollYear = (enrollmentYearMin...enrollmentYearMax).contains(session.schoolyear)
                    ? String(session.schoolyear)
                    : ((enrollmentYearMin...enrollmentYearMax).contains(panel.schoolyear) ? String(panel.schoolyear) : "")
                session.apply(semester: currentSemester)
            } else if (enrollmentYearMin...enrollmentYearMax).contains(panel.schoolyear), panel.schoolyearLocked {
                session.apply(schoolyear: panel.schoolyear, semester: currentSemester)
                setupEnrollYear = String(panel.schoolyear)
            } else if panel.needsEnrollYear {
                setupEnrollYear = ""
            }
            setupEduSystem = session.educationSystem
            savedRuleId = panel.ruleId
            panelNeedsRule = panel.needsRule
            let needsYear = !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: schoolyearLocked)
            let needsEdu = !AcademicCalc.hasProfileEducationSystem(session.educationSystem)
            let needsRule = panel.needsRule || panel.ruleId <= 0
            showProfileSetup = needsYear || needsEdu || needsRule
            selectedRuleId = panel.ruleId > 0 ? panel.ruleId : AcademicCalc.pickDefaultGpaRuleId(rules)
            baselineGpa = panel.baselineGpa
            baselineCredits = panel.baselineCredits
            histTerms = panel.terms
            let bySem = await AcademicApi.loadRegisteredCoursesBySemester(
                currentSemester: currentSemester.isEmpty ? panel.semester : currentSemester,
                already: panel.coursesBySemester,
                serverProvided: panel.coursesBySemesterProvided
            )
            pastCourseMap = bySem
            let loaded = panel.courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
            gpaCourses = loaded.isEmpty ? AcademicCalc.gpaRowsForSemester(bySem, currentSemester) : loaded
        case .failure(let error):
            academicToast(error.localizedDescription)
        }
        if let plan = await AcademicApi.fetchGpaPlan(targetSemester: currentSemester) {
            if plan.targetGpa > 0 { targetGpaInput = String(format: "%.2f", plan.targetGpa) }
            if plan.ruleId > 0 { selectedRuleId = plan.ruleId }
            if !plan.targetSemester.isEmpty { targetAnchorSemester = plan.targetSemester }
            pinned = plan.courses.compactMap { c in
                guard c.locked, !c.targetScore.isEmpty else { return nil }
                let score = c.targetScore.filter { $0.isNumber || $0 == "." }
                return score.isEmpty ? nil : (c.subjectName, score)
            }
            if !plan.futureCredits.isEmpty { futureCreditsInput = plan.futureCredits }
        }
        if targetAnchorSemester.isEmpty { targetAnchorSemester = currentSemester }
        if setupEduSystem.isEmpty { setupEduSystem = session.educationSystem }
        if selectedRuleId == 0 { selectedRuleId = AcademicCalc.pickDefaultGpaRuleId(rules) }
        loading = false
        await runPreview()
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespaces).isEmpty ? fallback : self
    }
}
