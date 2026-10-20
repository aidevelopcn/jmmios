import SwiftUI

struct GpaAcademicView: View {
    var openHistory: Bool = false
    let onBack: () -> Void

    @EnvironmentObject private var session: AcademicSession
    @State private var loading = true
    @State private var submitting = false
    @State private var recognizing = false
    @State private var panel: GpaPanelData?
    @State private var rules: [GpaRuleOption] = []
    @State private var selectedSemester = ""
    @State private var selectedRuleId = 0
    @State private var baselineGpa = ""
    @State private var baselineCredits = ""
    @State private var gpaMainTab: GpaMainTab = .calc
    @State private var gpaViewScope: GpaViewScope = .term
    @State private var historyEntryMode: HistoryEntryMode = .packed
    @State private var showProfileSetup = false
    @State private var setupEnrollYear = ""
    @State private var setupEduSystem = ""
    @State private var setupSaving = false
    @State private var schoolyearLocked = false
    @State private var showSetupYearPicker = false
    @State private var showSetupEduPicker = false
    @State private var showSetupRulePicker = false
    @State private var showEnrollLockConfirm = false
    @State private var showSemesterPicker = false
    @State private var showRulePicker = false
    @State private var showCourseSheet = false
    @State private var editingCourseIndex: Int?
    @State private var draftCourseName = ""
    @State private var draftCourseCredit = "4"
    @State private var draftCourseScore = ""
    @State private var showTermEntry = false
    @State private var entrySemester = ""
    @State private var entryQuickMode = true
    @State private var entryGpa = ""
    @State private var entryCredits = ""
    @State private var courses: [GpaCourseRow] = []
    @State private var baselineSaving = false
    @State private var showOcrSheet = false
    @State private var showImagePicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedImage: UIImage?
    @State private var pendingOcrMode = "grade"

    private enum GpaMainTab { case calc, terms }

    private var currentSemester: String {
        AcademicCalc.inferGpaSemesterCode(session.schoolyear > 0 ? session.schoolyear : (panel?.schoolyear ?? 0))
            .ifBlank(panel?.semester ?? "")
            .ifBlank(selectedSemester)
    }

    private var selectedRule: GpaRuleOption? { rules.first { $0.id == selectedRuleId } }
    private var formalLocked: Bool {
        panel?.locked == true && courses.contains { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private var editable: Bool { !formalLocked }
    private var terms: [GpaTermRow] { panel?.terms ?? [] }
    private var panelCourses: [String: [GpaCourseRow]] { panel?.coursesBySemester ?? [:] }
    private var viewingPast: Bool {
        !selectedSemester.isEmpty && !currentSemester.isEmpty && selectedSemester != currentSemester
    }

    private var currentTermCourses: [GpaCourseRow] {
        viewingPast ? AcademicCalc.gpaRowsForSemester(panelCourses, currentSemester).ifEmpty(courses) : courses
    }

    var body: some View {
        ZStack {
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
            runOcr(image)
        }
        .task {
            gpaMainTab = openHistory ? .terms : .calc
            await reload(preferRegisteredIfEmpty: true)
        }
    }

    private var pageContent: some View {
        VStack(spacing: 0) {
            ProfileSimpleTopBar(
                title: gpaMainTab == .terms ? "历史成绩" : "GPA计算",
                onBack: {
                    if gpaMainTab == .terms && !openHistory {
                        gpaMainTab = .calc
                    } else {
                        onBack()
                    }
                }
            )
            if loading {
                Spacer()
                ProgressView().tint(AcademicPalette.teal)
                Spacer()
            } else if gpaMainTab == .terms {
                historyScroll
            } else {
                calcScroll
            }
        }
        .background(Color.white.ignoresSafeArea())
    }

    private var calcScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 11) {
                AcademicCompactToolbar(
                    semesterLabel: semesterToolbarLabel,
                    ruleLabel: AcademicCalc.displayGpaRuleName(selectedRule),
                    onSemesterClick: { showSemesterPicker = true },
                    onRuleClick: { if !rules.isEmpty { showRulePicker = true } }
                )
                AcademicSegmentControl(
                    options: GpaViewScope.allCases.map(\.label),
                    selectedIndex: gpaViewScope.rawValue
                ) { gpaViewScope = GpaViewScope(rawValue: $0) ?? .term }

                calcHeroBlock
                if gpaViewScope == .year {
                    yearRows
                } else if gpaViewScope == .cumulative {
                    AcademicSecondaryButton(title: "历史成绩 ›") { gpaMainTab = .terms }
                }
                if gpaViewScope == .term && (!viewingPast || !courses.isEmpty) {
                    termCourseBlock
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var semesterToolbarLabel: String {
        let code = selectedSemester.isEmpty || selectedSemester == currentSemester ? currentSemester.ifBlank(selectedSemester) : selectedSemester
        let label = AcademicCalc.displayGpaSemesterName(code)
        if !selectedSemester.isEmpty && selectedSemester != currentSemester {
            return "\(label)（查看）"
        }
        return label
    }

    @ViewBuilder
    private var calcHeroBlock: some View {
        if viewingPast && gpaViewScope == .term && courses.isEmpty {
            pastEmptyBlock
        } else {
            GpaCalcHeroCard(title: heroTitle, gpaValue: heroGpa, subtitle: gpaViewScope == .year ? "" : heroSubtitle, chip: yearChip)
        }
    }

    private var heroTitle: String {
        switch gpaViewScope {
        case .term:
            return "本学期 GPA · \(AcademicCalc.displayGpaSemesterName(viewingPast ? selectedSemester.ifBlank(currentSemester) : currentSemester.ifBlank(selectedSemester)))"
        case .year:
            let ay = AcademicCalc.currentAcademicYearAndHalf().0
            return "\(ay)–\(ay + 1) 学年 GPA"
        case .cumulative:
            return "累计 GPA（截至当前学期）"
        }
    }

    private var yearChip: String {
        guard gpaViewScope == .year else { return "" }
        return currentSemester.hasSuffix("上") ? "进行中 · 已录 1/2 学期" : "进行中 · 已录 2/2 学期"
    }

    private var liveTerm: GpaTermStats {
        AcademicCalc.termStatsOf(viewingPast ? courses : currentTermCourses, rule: selectedRule)
    }

    private var liveYear: GpaTermStats? {
        AcademicCalc.yearStatsOf(
            currentSemester: currentSemester.ifBlank(selectedSemester),
            currentCourses: currentTermCourses,
            terms: terms,
            rule: selectedRule,
            coursesBySemester: panelCourses
        )
    }

    private var liveCum: GpaTermStats? {
        AcademicCalc.cumulativeStatsOf(
            currentSemester: currentSemester.ifBlank(selectedSemester),
            currentCourses: currentTermCourses,
            terms: terms,
            baselineGpa: baselineGpa,
            baselineCredits: baselineCredits,
            rule: selectedRule,
            pastCoursesBySemester: panelCourses
        )
    }

    private var heroGpa: String {
        if viewingPast && gpaViewScope == .term {
            return terms.first(where: { $0.semester == selectedSemester })?.termGpaDisplay.ifBlank("—") ?? "—"
        }
        switch gpaViewScope {
        case .term: return AcademicCalc.formatGpaOrDash(liveTerm)
        case .year: return liveYear.map { AcademicCalc.formatGpaOrDash($0) } ?? "—"
        case .cumulative: return liveCum.map { AcademicCalc.formatGpaOrDash($0) } ?? "—"
        }
    }

    private var heroSubtitle: String {
        if viewingPast && gpaViewScope == .term {
            if let t = terms.first(where: { $0.semester == selectedSemester }), t.termCredits > 0 {
                return "\(AcademicCalc.formatGpaCredits(t.termCredits)) 学分"
            }
            let listed = courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
            let cr = listed.reduce(0) { $0 + (Double($1.credits) ?? 0) }
            let pending = listed.allSatisfy { Double($0.examScore) == nil }
            if listed.isEmpty { return "该学期未录入" }
            if pending { return "\(listed.count) 门 · \(AcademicCalc.formatGpaCredits(cr)) 学分 · 待录入成绩" }
            return "\(listed.count) 门 · \(AcademicCalc.formatGpaCredits(cr)) 学分"
        }
        switch gpaViewScope {
        case .term:
            let rows = viewingPast ? courses : currentTermCourses
            let termCredits = max(liveTerm.credits, AcademicCalc.registeredCreditsOf(rows))
            return "加权均分 \(AcademicCalc.weightedScoreAverage(rows)) · \(AcademicCalc.formatGpaCredits(termCredits)) 学分"
        case .year:
            let yearCredits = max(liveYear?.credits ?? 0, AcademicCalc.registeredCreditsOf(currentTermCourses))
            let half = currentSemester.hasSuffix("上") ? "进行中 · 已录 1/2 学期" : "进行中 · 已录 2/2 学期"
            return yearCredits > 0 ? "\(AcademicCalc.formatGpaCredits(yearCredits)) 学分 · \(half)" : half
        case .cumulative:
            let cred = max(liveCum?.credits ?? 0, AcademicCalc.cumulativeRegisteredCredits(
                currentSemester: currentSemester.ifBlank(selectedSemester),
                currentCourses: currentTermCourses,
                coursesBySemester: panelCourses
            ))
            return cred > 0 ? "共 \(AcademicCalc.formatGpaCredits(cred)) 学分" : "—"
        }
    }

    @ViewBuilder
    private var pastEmptyBlock: some View {
        AcademicHintBar {
            Text("查看历史学期 · ").font(.system(size: 13)).foregroundColor(AcademicPalette.acc)
            Button("返回当前学期") {
                selectedSemester = currentSemester
                Task { await reload(semester: currentSemester) }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(AcademicPalette.acc)
        }
        pastEmptyStats
    }

    @ViewBuilder
    private var pastEmptyStats: some View {
        let scored = courses.contains { Double($0.examScore) != nil }
        let pastTerm = terms.first(where: { $0.semester == selectedSemester })
        if scored {
            AcademicPlainStatCard(
                title: "学期 GPA",
                value: AcademicCalc.formatGpaOrDash(AcademicCalc.termStatsOf(courses, rule: selectedRule)),
                subtitle: String(format: "%.0f 学分", AcademicCalc.termStatsOf(courses, rule: selectedRule).credits)
            )
        } else if let pastTerm, pastTerm.termCredits > 0 {
            AcademicPlainStatCard(
                title: "学期 GPA",
                value: pastTerm.termGpaDisplay.ifBlank("—"),
                subtitle: String(format: "%.0f 学分", pastTerm.termCredits)
            )
            Text("快速模式录入：只有 GPA 与学分汇总")
                .font(.system(size: 12))
                .foregroundColor(AcademicPalette.muted)
                .frame(maxWidth: .infinity)
        } else if !baselineGpa.isEmpty {
            AcademicPlainStatCard(
                title: "该学期成绩包含在一键填历史块中",
                value: String(format: "%.2f", Double(baselineGpa) ?? 0),
                subtitle: "历史合计 \(baselineCredits) 学分"
            )
        } else {
            Text("该学期未录入成绩 · 可到「历史成绩」补录")
                .font(.system(size: 13))
                .foregroundColor(AcademicPalette.dim)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var yearRows: some View {
        let grade = AcademicCalc.gradeDigit(currentSemester) ?? "1"
        let fall = "大\(grade)上"
        let spring = "大\(grade)下"
        let live = AcademicCalc.termStatsOf(currentTermCourses, rule: selectedRule)
        GpaYearSemesterRow(label: AcademicCalc.displayGpaSemesterName(fall), right: yearRowRight(fall, liveIfCurrent: live))
        if currentSemester.hasSuffix("上") {
            GpaYearSemesterRow(label: AcademicCalc.displayGpaSemesterName(spring), right: "成绩录入后自动并入", pending: true)
        } else {
            GpaYearSemesterRow(label: AcademicCalc.displayGpaSemesterName(spring), right: yearRowRight(spring, liveIfCurrent: live))
        }
        Text("学年只进行到上学期时，学年 GPA 就等于本学期 GPA")
            .font(.system(size: 12))
            .foregroundColor(Color(hex: "94A3B8"))
            .frame(maxWidth: .infinity)
    }

    private func yearRowRight(_ sem: String, liveIfCurrent: GpaTermStats) -> String {
        let rows = sem == currentSemester ? currentTermCourses : (panelCourses[sem] ?? [])
        let scored = sem == currentSemester ? liveIfCurrent : AcademicCalc.termStatsOf(rows, rule: selectedRule)
        let term = terms.first(where: { $0.semester == sem && $0.termCredits > 0 })
        let termGpa = term.flatMap { Double($0.termGpaDisplay) }
        let credits = max(scored.credits, max(term?.termCredits ?? 0, AcademicCalc.registeredCreditsOf(rows)))
        let pending = credits > 0 && scored.credits <= 0 && termGpa == nil
        if credits <= 0 { return "未录入" }
        if pending { return "\(AcademicCalc.formatGpaCredits(credits)) 学分 · 待录入成绩" }
        if scored.credits > 0 { return "\(AcademicCalc.formatGpaOrDash(scored)) · \(AcademicCalc.formatGpaCredits(credits)) 学分" }
        if let term, termGpa != nil { return "\(term.termGpaDisplay) · \(AcademicCalc.formatGpaCredits(credits)) 学分" }
        return "\(AcademicCalc.formatGpaCredits(credits)) 学分"
    }

    @ViewBuilder
    private var termCourseBlock: some View {
        ForEach(Array(courses.enumerated()), id: \.offset) { index, course in
            termCourseRow(index: index, course: course)
        }
        if editable {
            HStack(spacing: 8) {
                AcademicPrimaryButton(title: "＋ 添加成绩") {
                    editingCourseIndex = nil
                    draftCourseName = ""
                    draftCourseCredit = "4"
                    draftCourseScore = ""
                    showCourseSheet = true
                }
                AcademicSecondaryButton(title: "上传成绩单") {
                    pendingOcrMode = "grade"
                    showOcrSheet = true
                }
                .frame(width: 118)
            }
        }
        if courses.isEmpty {
            let pastN = panelCourses
                .filter { AcademicCalc.isPastGpaSemester($0.key, current: currentSemester) }
                .values
                .reduce(0) { $0 + $1.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }.count }
            if pastN > 0 {
                Text("科目登记已录入 \(pastN) 门历史科目，点左上角切换学期即可查看名称和学分")
                    .font(.system(size: 13))
                    .foregroundColor(AcademicPalette.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
    }

    private func termCourseRow(index: Int, course: GpaCourseRow) -> some View {
        let score = Double(course.examScore.trimmingCharacters(in: .whitespaces))
        return GpaCourseListRow(
            name: course.subjectName,
            credits: course.credits,
            score: course.examScore,
            pointText: AcademicCalc.scoreToGpaPoint(score, rule: selectedRule).map { String(format: "%.1f", $0) } ?? "—",
            pending: score == nil,
            editable: editable
        ) {
            editingCourseIndex = index
            draftCourseName = course.subjectName
            draftCourseCredit = course.credits.ifBlank("4")
            draftCourseScore = course.examScore
            showCourseSheet = true
        }
    }

    private var historyScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 11) {
                AcademicSegmentControl(
                    options: HistoryEntryMode.allCases.map(\.label),
                    selectedIndex: historyEntryMode.rawValue
                ) { historyEntryMode = HistoryEntryMode(rawValue: $0) ?? .packed }
                if historyEntryMode == .packed {
                    packedHistory
                } else {
                    perTermHistory
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var packedHistory: some View {
        AcademicLabeledField(label: "截至上学期总学分", text: $baselineCredits, placeholder: "如：90", keyboard: .decimalPad, enabled: editable && !baselineSaving)
        AcademicLabeledField(label: "截至上学期累计 GPA", text: $baselineGpa, placeholder: "如：3.50", keyboard: .decimalPad, enabled: editable && !baselineSaving)
        AcademicPrimaryButton(title: baselineSaving ? "保存中…" : "保存历史块", enabled: editable && !baselineSaving, action: savePackedBaseline)
        if !baselineGpa.isEmpty && !baselineCredits.isEmpty {
            AcademicHintBar {
                Text("已保存 · \(baselineGpa) · \(baselineCredits) 学分")
                    .font(.system(size: 13))
                    .foregroundColor(AcademicPalette.acc)
                Spacer()
                if editable {
                    Button("删除") { Task { await deleteBaseline() } }
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "B91C1C"))
                }
            }
        }
        if editable {
            AcademicSecondaryButton(title: "上传成绩单") {
                pendingOcrMode = "grade"
                showOcrSheet = true
            }
        }
        Text("学期范围由入学年份自动推算，不可修改；一键填范围截止到上学期，本学期成绩在首页按课程明细算，填完后在「逐学期填写」里显示为一个历史块。")
            .font(.system(size: 12))
            .foregroundColor(AcademicPalette.muted)
            .lineSpacing(4)
    }

    @ViewBuilder
    private var perTermHistory: some View {
        if !baselineGpa.isEmpty && !baselineCredits.isEmpty {
            Button {
                historyEntryMode = .packed
            } label: {
                AcademicHintBar {
                    Text("历史已用一键填录入（\(baselineCredits) 学分 · \(baselineGpa)）")
                        .font(.system(size: 13))
                        .foregroundColor(AcademicPalette.acc)
                    Spacer()
                    Text("查看/编辑").font(.system(size: 13)).foregroundColor(AcademicPalette.acc)
                }
            }
            .buttonStyle(.plain)
        }
        ForEach(historySkeleton, id: \.self) { sem in
            let isCur = sem == currentSemester
            let future = AcademicCalc.nextGpaSemester(currentSemester) == sem
            let term = terms.first(where: { $0.semester == sem })
            GpaTermSkeletonRow(
                label: AcademicCalc.displayGpaSemesterName(sem) + (isCur ? "（当前）" : ""),
                right: historyRight(sem: sem, isCur: isCur, future: future, term: term),
                current: isCur,
                future: future
            ) {
                openHistorySemester(sem, isCur: isCur, term: term)
            }
        }
    }

    private var historySkeleton: [String] {
        let cur = currentSemester.ifBlank(selectedSemester)
        var list = AcademicCalc.lookbackGpaSemesters(cur)
        if let next = AcademicCalc.nextGpaSemester(cur) { list.append(next) }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    private func historyRight(sem: String, isCur: Bool, future: Bool, term: GpaTermRow?) -> String {
        if future { return "待开学" }
        if isCur { return "当前学期 · 录入中 ›" }
        if let term, term.termCredits > 0 {
            return "\(term.termGpaDisplay) · \(String(format: "%.0f", term.termCredits)) 学分"
        }
        if !baselineGpa.isEmpty { return "一键填已覆盖" }
        return "待录入"
    }

    private func openHistorySemester(_ sem: String, isCur: Bool, term: GpaTermRow?) {
        if isCur {
            gpaMainTab = .calc
            selectedSemester = sem
            return
        }
        guard editable else { return }
        if !baselineGpa.isEmpty && term == nil {
            academicToast("单独录入后累计将改用逐学期明细，历史块不再计入")
        }
        entrySemester = sem
        entryQuickMode = term?.entryMode != "detail"
        entryGpa = term?.termGpaDisplay ?? ""
        entryCredits = (term != nil && (term?.termCredits ?? 0) > 0) ? String(format: "%.0f", term?.termCredits ?? 0) : ""
        showTermEntry = true
    }

    private var pickerOverlay: AnyView {
        if showSemesterPicker { return AnyView(semesterSheet) }
        if showRulePicker { return AnyView(ruleSheet) }
        if showCourseSheet { return AnyView(courseSheet) }
        if showTermEntry { return AnyView(termEntrySheet) }
        if showOcrSheet { return AnyView(ocrSheet) }
        if showSetupYearPicker { return AnyView(yearSheet) }
        if showSetupEduPicker { return AnyView(eduSheet) }
        if showSetupRulePicker { return AnyView(setupRuleSheet) }
        if showEnrollLockConfirm { return AnyView(enrollLockSheet) }
        return AnyView(EmptyView())
    }

    private var semesterSheet: some View {
        AcademicSheet(title: "选择学期", onDismiss: { showSemesterPicker = false }) {
            let currentPick = selectedSemester.ifBlank(currentSemester)
            let options = AcademicCalc.lookbackGpaSemesters(currentSemester.ifBlank(selectedSemester)).reversed()
            VStack(spacing: 8) {
                ForEach(Array(options), id: \.self) { sem in
                    AcademicOptionRow(
                        title: AcademicCalc.displayGpaSemesterName(sem) + (sem == currentSemester ? "  当前" : ""),
                        selected: sem == currentPick
                    ) {
                        selectedSemester = sem
                        showSemesterPicker = false
                        let cached = (panel?.coursesBySemester[sem] ?? []).filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
                        if !cached.isEmpty { courses = cached }
                        Task { await reload(semester: sem) }
                    }
                }
            }
        }
    }

    private var ruleSheet: some View {
        AcademicSheet(title: "GPA 计算方式", onDismiss: { showRulePicker = false }) {
            VStack(spacing: 8) {
                ForEach(rules) { rule in
                    AcademicOptionRow(title: AcademicCalc.displayGpaRulePickerLabel(rule), selected: rule.id == selectedRuleId) {
                        selectedRuleId = rule.id
                        showRulePicker = false
                        let year = session.schoolyear > 0 ? session.schoolyear : (panel?.schoolyear ?? 0)
                        if rule.id > 0, year > 0 {
                            Task {
                                _ = await AcademicApi.saveGpaProfileSetup(schoolyear: year, ruleId: rule.id)
                                await reload(semester: selectedSemester)
                            }
                        }
                    }
                }
            }
            Text("全局生效：所有学期与累计 GPA 立即按新换算表重算")
                .font(.system(size: 12))
                .foregroundColor(AcademicPalette.muted)
        }
    }

    private var courseSheet: some View {
        let previewScore = Double(draftCourseScore)
        let previewPoint = AcademicCalc.scoreToGpaPoint(previewScore, rule: selectedRule)
        return AcademicSheet(title: editingCourseIndex == nil ? "添加成绩" : "编辑成绩", onDismiss: { showCourseSheet = false }) {
            AcademicLabeledField(label: "课程名称", text: $draftCourseName, placeholder: "如：高等数学")
            AcademicLabeledField(label: "学分", text: $draftCourseCredit, placeholder: "如：3.5", keyboard: .decimalPad)
            AcademicLabeledField(label: "分数（0~100）", text: $draftCourseScore, placeholder: "如：92", keyboard: .decimalPad)
            AcademicHintBar {
                Text(previewScore == nil
                     ? "输入分数后显示对应绩点与等级"
                     : "\(draftCourseScore) 分 → \(String(format: "%.1f", previewPoint ?? 0)) 绩点 · \(AcademicCalc.gradeNameOfScore(previewScore))")
                    .font(.system(size: 13))
                    .foregroundColor(AcademicPalette.acc)
            }
            AcademicPrimaryButton(title: "保存", action: saveDraftCourse)
            if editingCourseIndex != nil {
                Button("删除该课程") {
                    if let idx = editingCourseIndex, courses.indices.contains(idx) {
                        courses.remove(at: idx)
                    }
                    showCourseSheet = false
                    persistCourses()
                }
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "B91C1C"))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var termEntrySheet: some View {
        AcademicSheet(title: "录入 \(AcademicCalc.displayGpaSemesterName(entrySemester))", onDismiss: { showTermEntry = false }) {
            AcademicSegmentControl(
                options: ["快速 · GPA+学分", "详细 · 逐门课"],
                selectedIndex: entryQuickMode ? 0 : 1
            ) { entryQuickMode = $0 == 0 }
            if entryQuickMode {
                AcademicLabeledField(label: "该学期 GPA", text: $entryGpa, placeholder: "如：3.65", keyboard: .decimalPad)
                AcademicLabeledField(label: "该学期学分", text: $entryCredits, placeholder: "如：26", keyboard: .decimalPad)
            } else {
                Text("详细模式会打开该学期，按本学期方式逐门录入。")
                    .font(.system(size: 13))
                    .foregroundColor(AcademicPalette.muted)
            }
            AcademicPrimaryButton(title: "保存本学期") {
                if entryQuickMode {
                    guard let gpa = Double(entryGpa), let cr = Double(entryCredits), gpa > 0, gpa <= 4, cr > 0 else {
                        academicToast("请填写有效 GPA 与学分")
                        return
                    }
                    Task {
                        submitting = true
                        let result = await AcademicApi.saveGpaQuickTerm(semester: entrySemester, gpa: entryGpa, credits: entryCredits)
                        if case .failure(let error) = result {
                            academicToast(error.localizedDescription)
                        } else {
                            showTermEntry = false
                            await reload(semester: selectedSemester)
                        }
                        submitting = false
                    }
                } else {
                    showTermEntry = false
                    selectedSemester = entrySemester
                    gpaMainTab = .calc
                    Task { await reload(semester: entrySemester) }
                }
            }
        }
    }

    private var ocrSheet: some View {
        AcademicSheet(title: pendingOcrMode == "grade" ? "识别成绩单" : "识别科目", onDismiss: { showOcrSheet = false }) {
            AcademicPrimaryButton(title: recognizing ? "识别中…" : "拍照", enabled: !recognizing) {
                pickerSource = .camera
                showImagePicker = true
            }
            AcademicSecondaryButton(title: "从相册选择", enabled: !recognizing) {
                pickerSource = .photoLibrary
                showImagePicker = true
            }
        }
    }

    private var profileOverlay: some View {
        let needsYear = !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: schoolyearLocked)
        let needsEdu = !AcademicCalc.hasProfileEducationSystem(session.educationSystem)
        let needsRule = panel?.needsRule == true || (panel?.ruleId ?? 0) <= 0
        return ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("开始前设置")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AcademicPalette.ink)
                if needsYear {
                    AcademicSettingRow(
                        label: "入学年份（保存后锁定）",
                        value: AcademicCalc.normalizeEnrollmentYear(setupEnrollYear).ifBlank("请选择"),
                        chevron: "▾"
                    ) { showSetupYearPicker = true }
                }
                if needsEdu {
                    AcademicSettingRow(
                        label: "学制",
                        value: educationSystemDemoOptions.first(where: { $0.0 == setupEduSystem.ifBlank(session.educationSystem) })?.1
                            ?? setupEduSystem.ifBlank("请选择"),
                        chevron: "▾"
                    ) { showSetupEduPicker = true }
                }
                if needsRule {
                    AcademicSettingRow(
                        label: "GPA 计算方式",
                        value: AcademicCalc.displayGpaRuleName(selectedRule),
                        chevron: "▾"
                    ) { showSetupRulePicker = true }
                }
                AcademicPrimaryButton(title: setupSaving ? "保存中…" : "保存并开始", enabled: !setupSaving, action: saveProfileSetup)
            }
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20)
        }
    }

    private var yearSheet: some View {
        AcademicSheet(title: "选择入学年份", onDismiss: { showSetupYearPicker = false }) {
            VStack(spacing: 8) {
                ForEach(AcademicCalc.enrollmentYearOptions(), id: \.self) { year in
                    AcademicOptionRow(title: "\(year)年", selected: setupEnrollYear == year) {
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
                ForEach(educationSystemDemoOptions, id: \.0) { item in
                    AcademicOptionRow(title: item.1, selected: setupEduSystem == item.0) {
                        setupEduSystem = item.0
                        showSetupEduPicker = false
                    }
                }
            }
        }
    }

    private var setupRuleSheet: some View {
        AcademicSheet(title: "GPA 计算模式", onDismiss: { showSetupRulePicker = false }) {
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

    private var enrollLockSheet: some View {
        let yearText = AcademicCalc.normalizeEnrollmentYear(setupEnrollYear)
            .ifBlank(session.schoolyear > 0 ? String(session.schoolyear) : "")
            .ifBlank(String(AcademicCalc.defaultEnrollmentYear()))
        return AcademicSheet(title: "确认入学年份", onDismiss: { showEnrollLockConfirm = false }) {
            Text("入学年份保存后不可自行修改。确认是 \(yearText) 年入学？")
                .font(.system(size: 14))
                .foregroundColor(AcademicPalette.ink)
            AcademicPrimaryButton(title: "确认锁定") {
                showEnrollLockConfirm = false
                Task { await commitProfileSetup(year: Int(yearText) ?? AcademicCalc.defaultEnrollmentYear(), lockYear: true) }
            }
            AcademicSecondaryButton(title: "取消") { showEnrollLockConfirm = false }
        }
    }

    private func saveDraftCourse() {
        let name = draftCourseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { academicToast("请填写课程名称"); return }
        guard let credit = Double(draftCourseCredit.trimmingCharacters(in: .whitespaces)), credit > 0 else {
            academicToast("请填写有效学分"); return
        }
        guard let score = Double(draftCourseScore), score >= 0, score <= 100 else {
            academicToast("分数需在 0~100 之间"); return
        }
        let row = GpaCourseRow(subjectName: name, credits: draftCourseCredit.trimmingCharacters(in: .whitespaces), examScore: draftCourseScore)
        if let idx = editingCourseIndex, courses.indices.contains(idx) {
            courses[idx] = row
        } else {
            courses.append(row)
        }
        showCourseSheet = false
        persistCourses()
    }

    private func persistCourses() {
        guard editable else { return }
        let snapshot = courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
        let semester = selectedSemester.ifBlank(panel?.semester ?? "")
        Task {
            let result = await AcademicApi.submitGpaPanel(
                semester: semester,
                ruleId: selectedRuleId,
                baselineGpa: "",
                baselineCredits: "",
                courses: snapshot
            )
            switch result {
            case .success:
                if snapshot.isEmpty {
                    courses = []
                } else if case .success(let data) = await AcademicApi.fetchGpaPanel(semester: semester) {
                    let bySem = await AcademicApi.loadRegisteredCoursesBySemester(
                        currentSemester: currentSemester.ifBlank(data.semester),
                        already: data.coursesBySemester
                    )
                    panel = data
                    panel?.coursesBySemester = bySem
                    let loaded = data.courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
                    courses = loaded.isEmpty ? AcademicCalc.gpaRowsForSemester(bySem, semester) : loaded
                }
            case .failure(let error):
                academicToast(error.localizedDescription)
            }
        }
    }

    private func savePackedBaseline() {
        guard let gpa = Double(baselineGpa), let credits = Double(baselineCredits), gpa > 0, gpa <= 4, credits > 0 else {
            academicToast("请填写有效的总学分与 GPA（0~4）")
            return
        }
        Task {
            baselineSaving = true
            let result = await AcademicApi.saveGpaBaseline(
                semester: currentSemester.ifBlank(selectedSemester),
                gpa: baselineGpa,
                credits: baselineCredits
            )
            if case .failure(let error) = result {
                academicToast(error.localizedDescription)
            } else {
                academicToast("历史块已保存")
                await reload(semester: selectedSemester)
            }
            baselineSaving = false
        }
    }

    private func deleteBaseline() async {
        baselineSaving = true
        let result = await AcademicApi.clearGpaBaseline(semester: currentSemester.ifBlank(selectedSemester))
        if case .failure(let error) = result {
            academicToast(error.localizedDescription)
        } else {
            baselineGpa = ""
            baselineCredits = ""
            await reload(semester: selectedSemester)
        }
        baselineSaving = false
    }

    private func saveProfileSetup() {
        let needsYear = !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: schoolyearLocked)
        let needsEdu = !AcademicCalc.hasProfileEducationSystem(session.educationSystem)
        let needsRule = panel?.needsRule == true || (panel?.ruleId ?? 0) <= 0
        let edu = setupEduSystem.ifBlank(session.educationSystem)
        let rule = selectedRuleId > 0 ? selectedRuleId : AcademicCalc.pickDefaultGpaRuleId(rules)
        if needsYear && setupEnrollYear.isEmpty && !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear) {
            academicToast("请选择入学年份"); return
        }
        if needsEdu && edu.isEmpty { academicToast("请选择学制"); return }
        if needsRule && rule <= 0 { academicToast("请选择 GPA 计算方式"); return }
        if needsYear {
            showEnrollLockConfirm = true
            return
        }
        let year = Int(AcademicCalc.normalizeEnrollmentYear(setupEnrollYear.ifBlank(session.schoolyear > 0 ? String(session.schoolyear) : "")))
            ?? AcademicCalc.defaultEnrollmentYear()
        Task { await commitProfileSetup(year: year, lockYear: false) }
    }

    private func commitProfileSetup(year: Int, lockYear: Bool) async {
        setupSaving = true
        let edu = setupEduSystem.ifBlank(session.educationSystem)
        let rule = selectedRuleId > 0 ? selectedRuleId : AcademicCalc.pickDefaultGpaRuleId(rules)
        await AcademicApi.persistAcademicProfile(
            school: session.school,
            major: session.major,
            schoolyear: year,
            semester: session.semester,
            educationSystem: edu
        )
        let result = await AcademicApi.saveGpaProfileSetup(schoolyear: year, ruleId: rule)
        switch result {
        case .success(let data):
            showProfileSetup = false
            schoolyearLocked = lockYear || data.schoolyearLocked
            session.apply(
                schoolyear: data.schoolyear > 0 ? data.schoolyear : year,
                educationSystem: edu,
                semester: data.semester.ifBlank(session.semester)
            )
            setupEnrollYear = String(data.schoolyear > 0 ? data.schoolyear : year)
            if data.ruleId > 0 { selectedRuleId = data.ruleId }
            await reload(semester: data.semester.ifBlank(selectedSemester))
        case .failure(let error):
            academicToast(error.localizedDescription)
        }
        setupSaving = false
    }

    private func runOcr(_ image: UIImage) {
        guard editable else { return }
        let semester = selectedSemester.ifBlank(panel?.semester ?? "")
        Task {
            recognizing = true
            guard let url = await AcademicApi.uploadImage(image) else {
                academicToast("上传失败")
                recognizing = false
                return
            }
            let result = await AcademicApi.recognizeGradeRegister(imageUrl: url, semester: semester, courses: courses)
            switch result {
            case .success(let merged):
                courses = merged.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
                academicToast("识别成功，已按明细重算")
                persistCourses()
                showOcrSheet = false
            case .failure(let error):
                academicToast(error.localizedDescription.isEmpty ? "识别失败，请重新拍照后再试" : error.localizedDescription)
            }
            recognizing = false
        }
    }

    private func reload(semester: String? = nil, preferRegisteredIfEmpty: Bool = false) async {
        loading = true
        let hint = semester ?? selectedSemester.ifBlank(session.semester)
        rules = await AcademicApi.fetchGpaRules()
        await AcademicApi.syncAcademicSession(session)
        if session.school.isEmpty || session.major.isEmpty || session.semester.isEmpty {
            if case .success(let reg) = await AcademicApi.fetchSubjectRegister(semester: hint) {
                session.applyFromRegister(reg)
            }
        }
        switch await AcademicApi.fetchGpaPanel(semester: hint) {
        case .success(let data):
            let inferredNow = AcademicCalc.inferGpaSemesterCode(session.schoolyear > 0 ? session.schoolyear : data.schoolyear)
            let currentCode = inferredNow.ifBlank(data.semester)
            let bySem = await AcademicApi.loadRegisteredCoursesBySemester(
                currentSemester: currentCode.ifBlank(data.semester),
                already: data.coursesBySemester
            )
            var next = data
            next.coursesBySemester = bySem
            panel = next
            schoolyearLocked = data.schoolyearLocked
            applySetupFields(from: data)
            if !currentCode.isEmpty && (session.semester.isEmpty || session.semester == currentCode) {
                session.apply(semester: currentCode)
            } else if inferredNow.isEmpty || data.semester == inferredNow || data.semester.isEmpty {
                session.apply(semester: data.semester.ifBlank(inferredNow))
            }
            selectedRuleId = data.ruleId > 0 ? data.ruleId : AcademicCalc.pickDefaultGpaRuleId(rules)
            let needsYear = !AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: schoolyearLocked)
            let needsEdu = !AcademicCalc.hasProfileEducationSystem(session.educationSystem)
            let needsRule = data.needsRule || data.ruleId <= 0
            showProfileSetup = needsYear || needsEdu || needsRule
            baselineGpa = data.baselineGpa
            baselineCredits = data.baselineCredits
            let panelSem = data.semester.ifBlank(hint)
            let loaded = data.courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
                .ifEmpty(AcademicCalc.gpaRowsForSemester(bySem, panelSem))
            let displaySem: String
            if !loaded.isEmpty || !preferRegisteredIfEmpty {
                displaySem = panelSem
            } else {
                displaySem = AcademicCalc.latestRegisteredSemester(bySem, prefer: currentCode).ifBlank(panelSem)
            }
            selectedSemester = displaySem
            if displaySem == panelSem && !loaded.isEmpty {
                courses = loaded
            } else {
                courses = AcademicCalc.gpaRowsForSemester(bySem, displaySem).ifEmpty(loaded)
            }
        case .failure(let error):
            academicToast(error.localizedDescription)
        }
        loading = false
    }

    private func applySetupFields(from data: GpaPanelData) {
        if AcademicCalc.hasProfileEnrollmentYear(session.schoolyear, locked: data.schoolyearLocked) {
            if (enrollmentYearMin...enrollmentYearMax).contains(session.schoolyear) {
                setupEnrollYear = String(session.schoolyear)
            } else if (enrollmentYearMin...enrollmentYearMax).contains(data.schoolyear) {
                setupEnrollYear = String(data.schoolyear)
            }
        } else if (enrollmentYearMin...enrollmentYearMax).contains(data.schoolyear), data.schoolyearLocked {
            session.apply(schoolyear: data.schoolyear)
            setupEnrollYear = String(data.schoolyear)
        } else if data.needsEnrollYear {
            setupEnrollYear = ""
        }
        setupEduSystem = session.educationSystem
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] {
        isEmpty ? fallback : self
    }
}
