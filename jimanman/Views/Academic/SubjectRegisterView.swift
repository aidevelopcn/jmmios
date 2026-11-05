import SwiftUI

struct SubjectRegisterView: View {
    let onBack: () -> Void
    var onOpenGpa: () -> Void = {}

    @EnvironmentObject private var session: AcademicSession
    @State private var loading = true
    @State private var saving = false
    @State private var recognizing = false
    @State private var school = ""
    @State private var major = ""
    @State private var schoolyear = ""
    @State private var selectedSemester = ""
    @State private var formalLocked = false
    @State private var courses: [SubjectRegisterRow] = []
    @State private var showSemesterSheet = false
    @State private var showCourseSheet = false
    @State private var showUploadSheet = false
    @State private var draftCountsToGpa = true
    @State private var showImagePicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedImage: UIImage?
    @State private var editingIndex = -1
    @State private var draftName = ""
    @State private var draftCredit = "4"
    @State private var draftAttr = "必修"
    @State private var pendingDelete = false

    private var inferredSemester: String {
        AcademicCalc.inferGpaSemesterCode(session.schoolyear).ifEmpty(session.semester)
    }

    private var currentSemester: String {
        inferredSemester.ifEmpty(selectedSemester)
    }

    private var viewingCurrent: Bool {
        selectedSemester.ifEmpty(currentSemester) == currentSemester
    }

    private var namedCourses: [SubjectRegisterRow] {
        courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var totalCredits: Double {
        namedCourses.reduce(0) { $0 + (Double($1.credits) ?? 4) }
    }

    private var gpaCount: Int {
        namedCourses.filter(\.countsInGpa).count
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "科目登记", onBack: onBack)
                if loading {
                    Spacer()
                    ProgressView().tint(AcademicPalette.teal)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                showSemesterSheet = true
                            } label: {
                                Text(viewingCurrent
                                     ? "\(AcademicCalc.displayGpaSemesterBadge(currentSemester)) ▾"
                                     : "\(AcademicCalc.displayGpaSemesterName(selectedSemester.ifEmpty(currentSemester)))（补录）▾")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AcademicPalette.teal)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AcademicPalette.hintBg)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            subjectHero

                            if formalLocked {
                                Text(subjectLockedHint)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "B91C1C"))
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(hex: "FEF2F2"))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            if namedCourses.isEmpty {
                                Text(viewingCurrent ? "本学期还没有科目" : "该学期没有科目记录")
                                    .font(.system(size: 13))
                                    .foregroundColor(AcademicPalette.dim)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(namedCourses.enumerated()), id: \.offset) { index, course in
                                        if index > 0 {
                                            Color(hex: "0F172A").opacity(0.05).frame(height: 1)
                                        }
                                        courseRow(course)
                                    }
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "0F172A").opacity(0.06), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }

                            HStack(spacing: 8) {
                                AcademicPrimaryButton(
                                    title: saving
                                        ? "保存中…"
                                        : "＋ 添加\(viewingCurrent ? "本学期" : "该学期")科目",
                                    enabled: !saving && !formalLocked,
                                    action: openAddCourse
                                )
                                AcademicSecondaryButton(
                                    title: recognizing ? "识别中…" : "上传课表",
                                    enabled: !recognizing && !formalLocked
                                ) { showUploadSheet = true }
                                .frame(width: 118)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }

            if showSemesterSheet { semesterSheet }
            if showCourseSheet { courseSheet }
            if showUploadSheet { uploadSheet }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $pickedImage, sourceType: pickerSource)
        }
        .onChange(of: pickedImage) { image in
            guard let image else { return }
            pickedImage = nil
            runOcr(image)
        }
        .task { await reload(inferredSemester) }
        .onChange(of: session.schoolyear) { _ in
            Task { await reload(inferredSemester) }
        }
    }

    private var subjectHero: some View {
        JmmHeroSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(AcademicPalette.lemon).frame(width: 6, height: 6)
                    Text(viewingCurrent ? "本学期科目" : "补录学期")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                }
                Text("\(namedCourses.count) 门")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text(creditLine)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white.opacity(0.92))
                HStack {
                    Text(viewingCurrent ? "" : "历史学期 · \(namedCourses.count) 门")
                        .font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    if viewingCurrent && !namedCourses.isEmpty {
                        Button("GPA 计算 ›", action: onOpenGpa)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 10)
            }
            .padding(18)
        }
    }

    private var creditLine: String {
        if namedCourses.isEmpty { return "还没有科目" }
        let shown = abs(totalCredits - totalCredits.rounded()) < 0.05
            ? String(Int(totalCredits.rounded()))
            : String(format: "%.1f", totalCredits)
        return "共 \(shown) 学分" + (gpaCount > 0 ? " · 计入GPA \(gpaCount)门" : "")
    }

    private func courseRow(_ course: SubjectRegisterRow) -> some View {
        let inGpa = course.countsInGpa
        let style = subjectGpaStyle(inGpa)
        return HStack(spacing: 12) {
            Button {
                if let idx = courses.firstIndex(where: { $0.subjectName == course.subjectName && $0.id == course.id }) {
                    openEditCourse(idx)
                }
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(style.dot).frame(width: 6, height: 6)
                    Text(course.subjectName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AcademicPalette.ink)
                        .lineLimit(1)
                    let credit = formatCreditLabel(course.credits)
                    if !credit.isEmpty {
                        Text(credit)
                            .font(.system(size: 11))
                            .foregroundColor(AcademicPalette.dim)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button {
                toggleCountsToGpa(course)
            } label: {
                Text(inGpa ? "计入GPA" : "不计入GPA")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(style.pillText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(style.pillBg)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.pillBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            Text("›").foregroundColor(AcademicPalette.dim)
        }
        .padding(.vertical, 10)
    }

    private var semesterSheet: some View {
        AcademicSheet(title: "选择学期", onDismiss: { showSemesterSheet = false }) {
            let active = selectedSemester.ifEmpty(currentSemester)
            let terms = AcademicCalc.semesterListByGrade(AcademicCalc.maxGradeByEducationSystem(session.educationSystem))
            VStack(spacing: 8) {
                ForEach(terms, id: \.self) { code in
                    let future = AcademicCalc.isFutureSemester(code, current: currentSemester)
                    AcademicOptionRow(
                        title: AcademicCalc.displayGpaSemesterName(code),
                        right: future ? "待开学" : (code == currentSemester ? "当前 ✓" : (code == active && !namedCourses.isEmpty ? "\(namedCourses.count) 门" : "")),
                        selected: code == active,
                        disabled: future
                    ) {
                        showSemesterSheet = false
                        if code != selectedSemester {
                            Task { await reload(code) }
                        }
                    }
                }
            }
        }
    }

    private var courseSheet: some View {
        AcademicSheet(
            title: editingIndex >= 0 ? "编辑科目" : "添加科目",
            onDismiss: { showCourseSheet = false }
        ) {
            AcademicLabeledField(label: "课程名称", text: $draftName, placeholder: "请填写科目全称")
            AcademicLabeledField(label: "学分", text: $draftCredit, placeholder: "如 3.5", keyboard: .decimalPad)
            Button { draftCountsToGpa.toggle() } label: {
                HStack {
                    Image(systemName: draftCountsToGpa ? "checkmark.square.fill" : "square")
                        .foregroundColor(draftCountsToGpa ? AcademicPalette.teal : AcademicPalette.dim)
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
            AcademicPrimaryButton(title: "保存", action: saveDraftCourse)
            if editingIndex >= 0 {
                Button {
                    pendingDelete.toggle()
                } label: {
                    Text(pendingDelete ? "再点一次确认删除" : "删除该科目")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "DC2626"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            if pendingDelete {
                Button("确认删除", role: .destructive, action: deleteEditingCourse)
            }
        }
    }

    private var uploadSheet: some View {
        AcademicSheet(title: "上传课表", onDismiss: { if !recognizing { showUploadSheet = false } }) {
            Text("识别仅补充缺失科目，新增科目默认参与GPA计算，可编辑。")
                .font(.system(size: 13))
                .foregroundColor(AcademicPalette.muted)
            AcademicPrimaryButton(title: recognizing ? "识别中…" : "＋ 选择课表图片 · 可分多次传", enabled: !recognizing) {
                pickerSource = .photoLibrary
                showImagePicker = true
            }
            AcademicSecondaryButton(title: "拍照录入", enabled: !recognizing) {
                pickerSource = .camera
                showImagePicker = true
            }
        }
    }

    private func openAddCourse() {
        if formalLocked {
            academicToast(subjectLockedHint)
            return
        }
        editingIndex = -1
        draftName = ""
        draftCredit = "4"
        draftAttr = "必修"
        draftCountsToGpa = true
        pendingDelete = false
        showCourseSheet = true
    }

    private func openEditCourse(_ index: Int) {
        guard courses.indices.contains(index) else { return }
        let row = courses[index]
        editingIndex = index
        draftName = row.subjectName
        draftCredit = row.credits.isEmpty ? "4" : row.credits
        draftAttr = normalizeSubjectAttr(row.subjectType)
        draftCountsToGpa = row.countsInGpa
        pendingDelete = false
        showCourseSheet = true
    }

    private func saveDraftCourse() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { academicToast("请填写科目全称"); return }
        guard let credit = Double(draftCredit.trimmingCharacters(in: .whitespaces)), credit > 0 else {
            academicToast("请填写有效学分")
            return
        }
        var next = courses
        if courses.indices.contains(editingIndex) {
            next[editingIndex].subjectName = name
            next[editingIndex].credits = draftCredit.trimmingCharacters(in: .whitespaces)
            next[editingIndex].subjectType = draftAttr
            next[editingIndex].countsToGpa = draftCountsToGpa ? "是" : "否"
        } else {
            next.append(SubjectRegisterRow(
                subjectName: name,
                credits: draftCredit.trimmingCharacters(in: .whitespaces),
                subjectType: draftAttr,
                countsToGpa: draftCountsToGpa ? "是" : "否"
            ))
        }
        showCourseSheet = false
        persist(next)
    }

    private func deleteEditingCourse() {
        guard courses.indices.contains(editingIndex) else { return }
        var next = courses
        next.remove(at: editingIndex)
        showCourseSheet = false
        pendingDelete = false
        persist(next)
    }

    private func applyCourses(_ rows: [SubjectRegisterRow], toastDupes: Bool = false) {
        let (deduped, removed) = dedupe(rows.map(withDefaultCredits))
        courses = deduped
        if toastDupes, removed > 0 {
            academicToast("已自动合并 \(removed) 门同学期重复科目")
        }
    }

    private func persist(_ rows: [SubjectRegisterRow]? = nil) {
        if formalLocked { return }
        let previous = courses
        let source = rows ?? courses
        let (deduped, _) = dedupe(source.map(withDefaultCredits))
        let named = deduped.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
        applyCourses(named)
        Task {
            saving = true
            let result = await AcademicApi.saveSubjectRegister(
                semester: selectedSemester.ifEmpty(inferredSemester),
                school: school.trimmingCharacters(in: .whitespaces),
                major: major.trimmingCharacters(in: .whitespaces),
                schoolyear: Int(schoolyear) ?? session.schoolyear,
                courses: named
            )
            switch result {
            case .success(let data):
                selectedSemester = data.semester.ifEmpty(selectedSemester)
                school = data.school.ifEmpty(school)
                major = data.major.ifEmpty(major)
                if data.schoolyear > 0 { schoolyear = String(data.schoolyear) }
                formalLocked = data.locked && data.courses.contains { !$0.subjectName.isEmpty }
                session.applyFromRegister(data)
                applyCourses(named.isEmpty ? [] : data.courses)
            case .failure(let error):
                applyCourses(previous)
                academicToast(error.localizedDescription)
            }
            saving = false
        }
    }

    private func applyPanel(_ data: SubjectRegisterPanel, fallbackSemester: String) {
        selectedSemester = data.semester.ifEmpty(fallbackSemester).ifEmpty(inferredSemester)
        school = data.school.ifEmpty(school)
        major = data.major.ifEmpty(major)
        schoolyear = data.schoolyear > 0 ? String(data.schoolyear) : schoolyear
        formalLocked = data.locked && data.courses.contains { !$0.subjectName.isEmpty }
        session.applyFromRegister(data)
        applyCourses(data.courses)
    }

    private func toggleCountsToGpa(_ course: SubjectRegisterRow) {
        if formalLocked {
            academicToast(subjectLockedHint)
            return
        }
        guard let idx = courses.firstIndex(where: { $0.subjectName == course.subjectName && $0.id == course.id }) else { return }
        var next = courses
        next[idx].countsToGpa = next[idx].countsInGpa ? "否" : "是"
        persist(next)
    }

    private func reload(_ semester: String) async {
        if let cached = AcademicApi.peekSubjectRegister(semester: semester) {
            applyPanel(cached, fallbackSemester: semester)
            loading = false
        } else {
            loading = true
        }
        let result = await AcademicApi.fetchSubjectRegister(semester: semester)
        switch result {
        case .success(let data):
            applyPanel(data, fallbackSemester: semester)
        case .failure(let error):
            if AcademicApi.peekSubjectRegister(semester: semester) == nil {
                academicToast(error.localizedDescription)
            }
        }
        loading = false
    }

    private func runOcr(_ image: UIImage) {
        let semester = selectedSemester.ifEmpty(currentSemester)
        Task {
            recognizing = true
            guard let meta = await AcademicApi.uploadImageMeta(image) else {
                academicToast("上传失败")
                recognizing = false
                return
            }
            let result = await AcademicApi.recognizeSubjectRegister(
                imageUrl: meta.url,
                semester: semester,
                courses: courses,
                imageMeta: meta
            )
            switch result {
            case .success(let pair):
                if !pair.0.isEmpty, selectedSemester.isEmpty {
                    selectedSemester = pair.0
                }
                applyCourses(pair.1, toastDupes: true)
                persist()
                showUploadSheet = false
                academicToast("识别成功，已补充缺少的科目")
            case .failure(let error):
                academicToast(error.localizedDescription.isEmpty ? "识别失败，请重新拍照后再试" : error.localizedDescription)
            }
            recognizing = false
        }
    }
}

private struct SubjectAttrStyle {
    let dot: Color
    let pillBg: Color
    let pillBorder: Color
    let pillText: Color
}

private func subjectAttrStyle(_ type: String) -> SubjectAttrStyle {
    switch type.trimmingCharacters(in: .whitespaces) {
    case "必修":
        return SubjectAttrStyle(dot: Color(hex: "00DCC8"), pillBg: Color(hex: "E0FAF6"), pillBorder: Color(hex: "00DCC8").opacity(0.35), pillText: Color(hex: "009688"))
    case "选修":
        return SubjectAttrStyle(dot: Color(hex: "3B82F6"), pillBg: Color(hex: "EFF6FF"), pillBorder: Color(hex: "3B82F6").opacity(0.35), pillText: Color(hex: "1D4ED8"))
    case "通识":
        return SubjectAttrStyle(dot: Color(hex: "F97316"), pillBg: Color(hex: "FFF7ED"), pillBorder: Color(hex: "F97316").opacity(0.35), pillText: Color(hex: "C2410C"))
    default:
        return SubjectAttrStyle(dot: Color(hex: "9CA3AF"), pillBg: Color(hex: "F2F4F7"), pillBorder: Color(hex: "DDE0E4"), pillText: Color(hex: "6B7280"))
    }
}

private func normalizeSubjectAttr(_ raw: String) -> String {
    let value = raw.trimmingCharacters(in: .whitespaces)
    if subjectAttrs.contains(value) { return value }
    return value.isEmpty ? "必修" : "其他"
}

private func normalizeSubjectNameKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespaces)
        .lowercased()
        .replacingOccurrences(of: #"[\s　]+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"[（）()【】\[\]{}]"#, with: "", options: .regularExpression)
}

private func withDefaultCredits(_ row: SubjectRegisterRow) -> SubjectRegisterRow {
    let credits = row.credits.trimmingCharacters(in: .whitespaces)
    if credits.isEmpty || Double(credits) == nil {
        var next = row
        next.credits = "4"
        return next
    }
    return row
}

private func dedupe(_ rows: [SubjectRegisterRow]) -> ([SubjectRegisterRow], Int) {
    var named: [String: SubjectRegisterRow] = [:]
    var order: [String] = []
    var removed = 0
    for row in rows {
        let name = row.subjectName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { continue }
        let key = normalizeSubjectNameKey(name)
        if let existing = named[key] {
            removed += 1
            named[key] = mergePreferFilled(existing, row)
        } else {
            named[key] = row
            order.append(key)
        }
    }
    return (order.compactMap { named[$0] }, removed)
}

private func mergePreferFilled(_ a: SubjectRegisterRow, _ b: SubjectRegisterRow) -> SubjectRegisterRow {
    func pick(_ x: String, _ y: String) -> String { x.isEmpty && !y.isEmpty ? y : x }
    var out = a
    out.id = a.id.isEmpty ? b.id : a.id
    out.credits = pick(a.credits, b.credits)
    out.subjectCode = pick(a.subjectCode, b.subjectCode)
    out.subjectType = pick(a.subjectType, b.subjectType)
    out.assessmentMethod = pick(a.assessmentMethod, b.assessmentMethod)
    out.regularScoreRatio = pick(a.regularScoreRatio, b.regularScoreRatio)
    out.midtermScoreRatio = pick(a.midtermScoreRatio, b.midtermScoreRatio)
    out.finalScoreRatio = pick(a.finalScoreRatio, b.finalScoreRatio)
    out.remarks = pick(a.remarks, b.remarks)
    out.teachingUnit = pick(a.teachingUnit, b.teachingUnit)
    out.classHours = pick(a.classHours, b.classHours)
    out.countsToGpa = pick(a.countsToGpa, b.countsToGpa)
    return out
}

private func subjectGpaStyle(_ countsToGpa: Bool) -> SubjectAttrStyle {
    if countsToGpa {
        return SubjectAttrStyle(
            dot: AcademicPalette.teal,
            pillBg: Color(hex: "E0FAF6"),
            pillBorder: AcademicPalette.teal.opacity(0.35),
            pillText: AcademicPalette.teal
        )
    }
    return SubjectAttrStyle(
        dot: Color(hex: "9CA3AF"),
        pillBg: Color(hex: "F2F4F7"),
        pillBorder: Color(hex: "DDE0E4"),
        pillText: Color(hex: "6B7280")
    )
}

private func formatCreditLabel(_ credits: String) -> String {
    let value = credits.trimmingCharacters(in: .whitespaces).ifEmpty("4")
    if let number = Double(value), number == Double(Int(number)) {
        return "\(Int(number))学分"
    }
    return "\(value)学分"
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespaces).isEmpty ? fallback : self
    }
}
