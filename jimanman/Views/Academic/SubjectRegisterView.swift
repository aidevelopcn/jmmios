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
    @State private var showAttrPicker = false
    @State private var showImagePicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedImage: UIImage?
    @State private var editingIndex = -1
    @State private var draftName = ""
    @State private var draftCredit = "4"
    @State private var draftAttr = "必修"
    @State private var pendingDelete = false

    private var currentSemester: String {
        AcademicCalc.inferGpaSemesterCode(session.schoolyear)
            .ifEmpty(selectedSemester)
            .ifEmpty("大1上")
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

    private var attrSummary: String {
        subjectAttrs.compactMap { attr in
            let count = namedCourses.filter { normalizeSubjectAttr($0.subjectType) == attr }.count
            return count > 0 ? "\(attr) \(count)" : nil
        }.joined(separator: " · ")
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
        .task { await reload(session.semester) }
        .onChange(of: session.schoolyear) { _ in
            Task { await reload(AcademicCalc.inferGpaSemesterCode(session.schoolyear).ifEmpty(session.semester).ifEmpty("大1上")) }
        }
    }

    private var subjectHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewingCurrent ? "本学期科目" : "补录学期")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
            Text("\(namedCourses.count) 门")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            Text(creditLine)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
            if viewingCurrent && !namedCourses.isEmpty {
                Button(action: onOpenGpa) {
                    Text("去算 GPA ›")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AcademicPalette.teal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: "00A691"), Color(hex: "00DCC8"), Color(hex: "5AE4D8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var creditLine: String {
        if namedCourses.isEmpty { return "还没有科目" }
        let shown = abs(totalCredits - totalCredits.rounded()) < 0.05
            ? String(Int(totalCredits.rounded()))
            : String(format: "%.1f", totalCredits)
        return "共 \(shown) 学分" + (attrSummary.isEmpty ? "" : " · \(attrSummary)")
    }

    private func courseRow(_ course: SubjectRegisterRow) -> some View {
        let attr = normalizeSubjectAttr(course.subjectType)
        let style = subjectAttrStyle(attr)
        return Button {
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
                Spacer()
                Text(attr)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(style.pillText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(style.pillBg)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.pillBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("›").foregroundColor(AcademicPalette.dim)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
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
            AcademicLabeledField(label: "学分", text: $draftCredit, placeholder: "4", keyboard: .decimalPad)
            Button { showAttrPicker.toggle() } label: {
                HStack {
                    Text("属性")
                        .font(.system(size: 12))
                        .foregroundColor(AcademicPalette.muted)
                    Spacer()
                    Text(draftAttr)
                        .font(.system(size: 14))
                        .foregroundColor(AcademicPalette.ink)
                    Text("▾").foregroundColor(AcademicPalette.dim)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if showAttrPicker {
                VStack(spacing: 6) {
                    ForEach(subjectAttrs, id: \.self) { attr in
                        AcademicOptionRow(title: attr, selected: draftAttr == attr) {
                            draftAttr = attr
                            showAttrPicker = false
                        }
                    }
                }
            }
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
        AcademicSheet(title: "上传课表", onDismiss: { showUploadSheet = false }) {
            Text("拍课表或从相册选图，识别后会自动补科目")
                .font(.system(size: 13))
                .foregroundColor(AcademicPalette.muted)
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

    private func openAddCourse() {
        if formalLocked {
            academicToast(subjectLockedHint)
            return
        }
        editingIndex = -1
        draftName = ""
        draftCredit = "4"
        draftAttr = "必修"
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
        } else {
            next.append(SubjectRegisterRow(subjectName: name, credits: draftCredit.trimmingCharacters(in: .whitespaces), subjectType: draftAttr))
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

    private func applyCourses(_ rows: [SubjectRegisterRow]) {
        let (deduped, _) = dedupe(rows.map(withDefaultCredits))
        courses = deduped
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
                semester: selectedSemester.ifEmpty(currentSemester),
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

    private func reload(_ semester: String) async {
        loading = true
        let result = await AcademicApi.fetchSubjectRegister(semester: semester)
        switch result {
        case .success(let data):
            selectedSemester = data.semester.ifEmpty(semester).ifEmpty(currentSemester)
            school = data.school
            major = data.major
            schoolyear = data.schoolyear > 0 ? String(data.schoolyear) : schoolyear
            formalLocked = data.locked && data.courses.contains { !$0.subjectName.isEmpty }
            session.applyFromRegister(data)
            applyCourses(data.courses)
        case .failure(let error):
            academicToast(error.localizedDescription)
        }
        loading = false
    }

    private func runOcr(_ image: UIImage) {
        let semester = selectedSemester.ifEmpty(currentSemester)
        Task {
            recognizing = true
            guard let url = await AcademicApi.uploadImage(image) else {
                academicToast("上传失败")
                recognizing = false
                return
            }
            let result = await AcademicApi.recognizeSubjectRegister(
                imageUrl: url,
                semester: semester,
                courses: courses
            )
            switch result {
            case .success(let pair):
                if !pair.0.isEmpty, selectedSemester.isEmpty {
                    selectedSemester = pair.0
                }
                applyCourses(pair.1)
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
    return out
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
