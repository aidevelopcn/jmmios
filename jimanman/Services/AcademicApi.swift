import Foundation
import UIKit

enum AcademicApi {
    private static var base: String { "\(ApiConfig.baseURL)/api/studentAcademic" }
    private static let cacheLock = NSLock()
    private static var subjectRegisterCache: [String: (TimeInterval, SubjectRegisterPanel)] = [:]

    private static func subjectRegisterCacheKey(_ semester: String) -> String {
        "\(ApiService.shared.token ?? "")|\(semester.trimmingCharacters(in: .whitespaces))"
    }

    static func peekSubjectRegister(semester: String) -> SubjectRegisterPanel? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let sem = semester.trimmingCharacters(in: .whitespaces)
        if !sem.isEmpty, let hit = subjectRegisterCache[subjectRegisterCacheKey(sem)] {
            return hit.1
        }
        if sem.isEmpty {
            let prefix = "\(ApiService.shared.token ?? "")|"
            return subjectRegisterCache
                .filter { $0.key.hasPrefix(prefix) }
                .max(by: { $0.value.0 < $1.value.0 })?
                .value.1
        }
        return nil
    }

    static func cacheSubjectRegister(_ panel: SubjectRegisterPanel, semester: String) {
        let resolved = panel.semester.trimmingCharacters(in: .whitespaces).isEmpty ? semester : panel.semester
        let now = Date().timeIntervalSince1970
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if !resolved.trimmingCharacters(in: .whitespaces).isEmpty {
            subjectRegisterCache[subjectRegisterCacheKey(resolved)] = (now, panel)
        }
        let sem = semester.trimmingCharacters(in: .whitespaces)
        if !sem.isEmpty, sem != resolved {
            subjectRegisterCache[subjectRegisterCacheKey(sem)] = (now, panel)
        }
    }

    static func clearSubjectRegisterCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        subjectRegisterCache.removeAll()
    }

    static func prefetchSubjectRegister(semester: String = "") {
        if peekSubjectRegister(semester: semester) != nil { return }
        Task {
            _ = await fetchSubjectRegister(semester: semester)
        }
    }

    static func fetchSubjectRegister(semester: String = "") async -> Result<SubjectRegisterPanel, Error> {
        let path = semester.isEmpty ? "subjectRegister" : "subjectRegister?semester=\(urlEncode(semester))"
        return await get(path) { json in
            guard codeOK(json), let data = json["data"] as? [String: Any] else {
                throw AcademicError(msg(json, "加载失败"))
            }
            let panel = parseSubjectRegisterPanel(data)
            cacheSubjectRegister(panel, semester: semester)
            return panel
        }
    }

    static func saveSubjectRegister(
        semester: String,
        school: String,
        major: String,
        schoolyear: Int,
        courses: [SubjectRegisterRow]
    ) async -> Result<SubjectRegisterPanel, Error> {
        let named = courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
        var form: [String: String] = [
            "semester": semester,
            "school": school,
            "major": major,
            "courses": jsonString(named.map { $0.asDict() })
        ]
        if named.isEmpty { form["clear_courses"] = "1" }
        if schoolyear > 0 { form["schoolyear"] = String(schoolyear) }
        return await post("subjectRegisterSave", form: form) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "保存失败")) }
            let data = json["data"] as? [String: Any] ?? [:]
            let panel = SubjectRegisterPanel(
                semester: stringValue(data["semester"]).isEmpty ? semester : stringValue(data["semester"]),
                school: stringValue(data["school"]).isEmpty ? school : stringValue(data["school"]),
                major: stringValue(data["major"]).isEmpty ? major : stringValue(data["major"]),
                schoolyear: intValue(data["schoolyear"]) > 0 ? intValue(data["schoolyear"]) : schoolyear,
                needProfile: false,
                done: boolValue(data["done"]),
                locked: boolValue(data["locked"]),
                classTeacherBound: boolValue(data["classTeacherBound"]),
                courses: parseSubjectRegisterRows(data["courses"])
            )
            cacheSubjectRegister(panel, semester: semester)
            return panel
        }
    }

    static func recognizeSubjectRegister(
        imageUrl: String,
        semester: String,
        courses: [SubjectRegisterRow],
        mode: String = "timetable",
        imageMeta: UploadedImageMeta? = nil
    ) async -> Result<(String, [SubjectRegisterRow]), Error> {
        var form: [String: String] = [
            "image_url": imageUrl,
            "semester": semester,
            "mode": mode,
            "courses": jsonString(courses.map { $0.asDict() })
        ]
        if let imageMeta {
            form["image_meta"] = imageMeta.asJson()
        }
        return await post("recognizeSubjectRegister", form: form, timeout: 180) { json in
            guard codeOK(json), let data = json["data"] as? [String: Any] else {
                throw AcademicError(msg(json, "识别失败"))
            }
            let next = stringValue(data["semester"]).isEmpty ? semester : stringValue(data["semester"])
            return (next, parseSubjectRegisterRows(data["courses"]))
        }
    }

    static func fetchQaSubjectHint() async -> QaSubjectHint? {
        guard let json = await academicGet("qaSubjectHint"), codeOK(json),
              let data = json["data"] as? [String: Any] else { return nil }
        return parseQaSubjectHint(data)
    }

    static func addQaSubjectName(_ subject: String) async -> Bool {
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let result = await post("qaSubjectAdd", form: ["subject": name]) { json in
            codeOK(json)
        }
        if case .success(true) = result {
            QaSubjectTombstone.forget(name)
            return true
        }
        return false
    }

    static func removeQaSubjectName(_ subject: String) async -> Bool {
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let result = await post("qaSubjectDelete", form: ["subject": name]) { json in
            codeOK(json)
        }
        if case .success(true) = result {
            QaSubjectTombstone.remember(name)
            return true
        }
        return false
    }

    static func loadSortedQaSubjectNames(extra: [String] = []) async -> [String] {
        struct Meta { var credits: Double; var required: Bool }
        var meta: [String: Meta] = [:]
        func absorb(_ name: String, _ credits: String, _ type: String) {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { return }
            let c = Double(credits.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let required = type.contains("必修")
            if var old = meta[n] {
                if c > old.credits { old.credits = c }
                old.required = old.required || required
                meta[n] = old
            } else {
                meta[n] = Meta(credits: c, required: required)
            }
        }
        var registerSemesters: [String] = []
        if case .success(let panel) = await fetchGpaPanel() {
            panel.courses.forEach { absorb($0.subjectName, $0.credits, "") }
            panel.coursesBySemester.forEach { sem, rows in
                if rows.contains(where: { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    if !registerSemesters.contains(sem) { registerSemesters.append(sem) }
                }
                rows.forEach { absorb($0.subjectName, $0.credits, "") }
            }
        }
        if registerSemesters.isEmpty {
            registerSemesters = Array(AcademicCalc.lookbackGpaSemesters("大5下").suffix(4))
        }
        for sem in registerSemesters {
            if case .success(let panel) = await fetchSubjectRegister(semester: sem) {
                panel.courses.forEach { absorb($0.subjectName, $0.credits, $0.subjectType) }
            }
        }
        extra.forEach { absorb($0, "", "") }
        let sorted = meta.sorted { a, b in
            if a.value.required != b.value.required { return a.value.required && !b.value.required }
            if a.value.credits != b.value.credits { return a.value.credits > b.value.credits }
            return a.key < b.key
        }.map(\.key)
        return QaSubjectTombstone.filter(sorted)
    }

    static func fetchRegisteredSubjectNamesAllSemesters() async -> [String] {
        var names: [String] = []
        func add(_ name: String) {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty, !names.contains(n) { names.append(n) }
        }
        if case .success(let panel) = await fetchGpaPanel() {
            panel.coursesBySemester.values.forEach { $0.forEach { add($0.subjectName) } }
            panel.courses.forEach { add($0.subjectName) }
        }
        if !names.isEmpty { return names }
        let bySem = await loadRegisteredCoursesBySemester(currentSemester: "大5下", already: [:])
        bySem.values.flatMap { $0 }.forEach { add($0.subjectName) }
        return names
    }

    static func prefetchMyCourses() {
        Task { _ = await fetchMyCourses() }
    }

    static func fetchMyCourses() async -> Result<MyCoursesPayload, Error> {
        if (ApiService.shared.token ?? "").isEmpty {
            MyCoursesCache.clear()
            return .failure(AcademicError("请先登录"))
        }
        return await get("myCourses") { json in
            let payload = try parseMyCoursesPayload(json)
            MyCoursesCache.save(payload)
            return payload
        }
    }

    static func confirmMyCourseHours(recordId: Int) async -> Result<String, Error> {
        await post("confirmCourseHours", form: ["record_id": String(recordId)]) { json in
            if jsonIntCode(json) == 401 { throw AcademicError("请先登录") }
            guard codeOK(json) else { throw AcademicError(msg(json, "确认失败")) }
            return msg(json, "确认成功")
        }
    }

    static func submitMyCourseRating(
        courseNo: String,
        rating1: Double,
        rating2: Double,
        comment1: String,
        comment2: String
    ) async -> Result<String, Error> {
        await post("submitCourseRating", form: [
            "course_no": courseNo,
            "rating1": String(rating1),
            "rating2": String(rating2),
            "comment1": comment1,
            "comment2": comment2
        ]) { json in
            if jsonIntCode(json) == 401 { throw AcademicError("请先登录") }
            guard codeOK(json) else { throw AcademicError(msg(json, "评价提交失败")) }
            return msg(json, "评价已提交")
        }
    }

    private static func jsonIntCode(_ json: [String: Any]) -> Int {
        if let i = json["code"] as? Int { return i }
        if let s = json["code"] as? String { return Int(s) ?? 0 }
        return 0
    }

    private static func parseMyCoursesPayload(_ json: [String: Any]) throws -> MyCoursesPayload {
        if jsonIntCode(json) == 401 { throw AcademicError("请先登录") }
        guard codeOK(json), let data = json["data"] as? [String: Any] else {
            throw AcademicError(msg(json, "加载失败"))
        }
        let list = data["courses"] as? [[String: Any]] ?? []
        return MyCoursesPayload(
            enrolled: boolValue(data["enrolled"]),
            reason: stringValue(data["reason"]),
            advisorName: stringValue(data["advisor_name"]),
            courses: list.map { item in
                let records = item["records"] as? [[String: Any]] ?? []
                let evaluation = item["evaluation"] as? [String: Any]
                return MyCourseItem(
                    courseNo: stringValue(item["course_no"]),
                    name: stringValue(item["name"]),
                    teacherName: stringValue(item["teacher_name"]),
                    advisorName: stringValue(item["advisor_name"]),
                    totalHours: doubleValue(item["total_hours"]),
                    usedHours: doubleValue(item["used_hours"]),
                    leftHours: doubleValue(item["left_hours"]),
                    canRate: boolValue(item["can_rate"]),
                    finished: boolValue(item["finished"])
                        || stringValue(item["sheet_status"]) == "已结课",
                    refunded: stringValue(item["sheet_status"]) == "学员退费",
                    sheetStatus: stringValue(item["sheet_status"]),
                    evaluation: evaluation.map {
                        MyCourseEvaluation(
                            rating1: doubleValue($0["rating1"]),
                            rating2: doubleValue($0["rating2"])
                        )
                    },
                    records: records.map {
                        MyCourseRecord(
                            id: intValue($0["id"]),
                            date: stringValue($0["date"]),
                            hours: doubleValue($0["hours"]),
                            status: stringValue($0["status"]),
                            confirmable: boolValue($0["confirmable"])
                        )
                    }
                )
            }
        )
    }

    private static func parseQaSubjectHint(_ data: [String: Any]) -> QaSubjectHint {
        func names(from key: String) -> [String] {
            var out: [String] = []
            if let arr = data[key] as? [Any] {
                for item in arr {
                    if let obj = item as? [String: Any] {
                        let n = stringValue(obj["name"]).trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty, !out.contains(n) { out.append(n) }
                    } else {
                        let n = stringValue(item).trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty, !out.contains(n) { out.append(n) }
                    }
                }
            }
            return out
        }
        let unmatched = QaSubjectTombstone.filter(names(from: "unmatched"))
        let registered = QaSubjectTombstone.filter(names(from: "registered"))
        let listed = QaSubjectTombstone.filter(names(from: "subjects"))
        let display = registered.isEmpty ? (unmatched.isEmpty ? listed : unmatched) : registered
        return QaSubjectHint(
            status: stringValue(data["status"]),
            message: stringValue(data["message"]),
            subjects: display,
            unmatched: unmatched
        )
    }

    static func fetchGpaRules() async -> [GpaRuleOption] {
        let json = await academicGet("gpaRules")
        guard let json, codeOK(json),
              let data = json["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] else { return [] }
        let rules = list.compactMap { item -> GpaRuleOption? in
            let id = intValue(item["id"])
            guard id > 0 else { return nil }
            return GpaRuleOption(
                id: id,
                name: stringValue(item["name"]),
                scoreType: stringValue(item["scoreType"]),
                maxPoint: doubleValue(item["maxPoint"], 4),
                formula: stringValue(item["formula"]),
                bands: parseBands(item["bands"])
            )
        }
        return AcademicCalc.sortedGpaRules(rules)
    }

    static func fetchGpaPanel(semester: String = "") async -> Result<GpaPanelData, Error> {
        let path = semester.isEmpty ? "gpaPanel" : "gpaPanel?semester=\(urlEncode(semester))"
        return await get(path) { json in
            guard codeOK(json), let data = json["data"] as? [String: Any] else {
                throw AcademicError(msg(json, "加载失败"))
            }
            return parseGpaPanel(data)
        }
    }

    static func submitGpaPanel(
        semester: String,
        ruleId: Int,
        baselineGpa: String,
        baselineCredits: String,
        courses: [GpaCourseRow]
    ) async -> Result<String, Error> {
        let named = courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
        var form: [String: String] = [
            "semester": semester,
            "courses": jsonString(named.map { $0.asDict() })
        ]
        if named.isEmpty { form["clear_courses"] = "1" }
        if ruleId > 0 { form["rule_id"] = String(ruleId) }
        if !baselineGpa.isEmpty { form["baseline_gpa"] = baselineGpa }
        if !baselineCredits.isEmpty { form["baseline_credits"] = baselineCredits }
        return await post("gpaSubmit", form: form) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "提交失败")) }
            clearSubjectRegisterCache()
            let data = json["data"] as? [String: Any]
            let text = stringValue(data?["cumulativeGpaDisplay"])
            return text.isEmpty ? "提交成功" : text
        }
    }

    static func fetchGpaPlan(targetSemester: String = "") async -> GpaPlanData? {
        let path = targetSemester.isEmpty
            ? "gpaPlan"
            : "gpaPlan?target_semester=\(urlEncode(targetSemester))"
        guard let json = await academicGet(path), codeOK(json),
              let data = json["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]],
              let plan = list.first else { return nil }
        var parsed = parseGpaPlan(
            plan,
            baselineGpa: optionalNumberString(data["baselineGpa"]),
            baselineCredits: optionalNumberString(data["baselineCredits"]),
            showBaseline: boolValue(data["showBaseline"]),
            expectedBaselineSemester: stringValue(data["expectedBaselineSemester"]),
            ruleId: intValue(data["ruleId"])
        )
        let overall = doubleValue(data["overallTargetGpa"])
        if parsed.targetGpa <= 0, overall > 0 { parsed.targetGpa = overall }
        return parsed
    }

    static func previewGpaPlan(
        targetSemester: String,
        targetGpa: Double,
        adjustments: [GpaPlanCourse],
        baselineGpa: String = "",
        baselineCredits: String = "",
        futureCredits: [String: String] = [:]
    ) async -> Result<GpaPlanData, Error> {
        var form: [String: String] = [
            "target_semester": targetSemester,
            "target_gpa": String(targetGpa),
            "adjustments": jsonString(adjustments.map { $0.asDict() })
        ]
        if !baselineGpa.isEmpty { form["baseline_gpa"] = baselineGpa }
        if !baselineCredits.isEmpty { form["baseline_credits"] = baselineCredits }
        if !futureCredits.isEmpty { form["future_credits"] = jsonString(futureCredits) }
        return await post("gpaPlanPreview", form: form) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "计算失败")) }
            return parseGpaPlanPreviewData(
                json["data"] as? [String: Any],
                targetSemester: targetSemester,
                targetGpa: targetGpa,
                futureCredits: futureCredits
            )
        }
    }

    static func saveGpaPlan(
        targetSemester: String,
        targetGpa: Double,
        adjustments: [GpaPlanCourse],
        baselineGpa: String = "",
        baselineCredits: String = "",
        ruleId: Int = 0,
        futureCredits: [String: String] = [:]
    ) async -> Result<GpaPlanData, Error> {
        var form: [String: String] = [
            "target_semester": targetSemester,
            "target_gpa": String(targetGpa),
            "adjustments": jsonString(adjustments.map { $0.asDict() })
        ]
        if !baselineGpa.isEmpty { form["baseline_gpa"] = baselineGpa }
        if !baselineCredits.isEmpty { form["baseline_credits"] = baselineCredits }
        if ruleId > 0 { form["rule_id"] = String(ruleId) }
        if !futureCredits.isEmpty { form["future_credits"] = jsonString(futureCredits) }
        return await post("gpaPlanSave", form: form) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "保存失败")) }
            return parseGpaPlanPreviewData(
                json["data"] as? [String: Any],
                targetSemester: targetSemester,
                targetGpa: targetGpa,
                ruleId: ruleId,
                futureCredits: futureCredits
            )
        }
    }

    static func saveGpaProfileSetup(schoolyear: Int, ruleId: Int) async -> Result<GpaProfileSetupResult, Error> {
        var form: [String: String] = ["rule_id": String(ruleId)]
        if schoolyear > 0 { form["schoolyear"] = String(schoolyear) }
        return await post("gpaProfileSetup", form: form) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "设置失败")) }
            let data = json["data"] as? [String: Any] ?? [:]
            return GpaProfileSetupResult(
                schoolyear: intValue(data["schoolyear"]),
                schoolyearLocked: boolValue(data["schoolyearLocked"]),
                ruleId: intValue(data["ruleId"]),
                semester: stringValue(data["semester"])
            )
        }
    }

    static func clearGpaBaseline(semester: String) async -> Result<Void, Error> {
        let cleared = await post("gpaClearBaseline", form: ["semester": semester]) { json in
            codeOK(json)
        }
        if case .success(true) = cleared { return .success(()) }
        return await post("gpaSaveBaseline", form: [
            "semester": semester,
            "clear": "1",
            "baseline_gpa": "",
            "baseline_credits": ""
        ]) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "删除失败")) }
        }
    }

    static func saveGpaQuickTerm(semester: String, gpa: String, credits: String) async -> Result<Void, Error> {
        await post("gpaSaveTerm", form: [
            "semester": semester,
            "mode": "quick",
            "gpa": gpa,
            "credits": credits
        ]) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "保存失败")) }
        }
    }

    static func recognizeGradeRegister(
        imageUrl: String,
        semester: String,
        courses: [GpaCourseRow]
    ) async -> Result<[GpaCourseRow], Error> {
        await post("recognizeGradeRegister", form: [
            "image_url": imageUrl,
            "semester": semester,
            "courses": jsonString(courses.map { $0.asDict() })
        ], timeout: 180) { json in
            guard codeOK(json), let data = json["data"] as? [String: Any] else {
                throw AcademicError(msg(json, "识别失败"))
            }
            return parseCourseRows(data["courses"])
        }
    }

    static func saveGpaBaseline(semester: String, gpa: String, credits: String) async -> Result<Void, Error> {
        await post("gpaSaveBaseline", form: [
            "semester": semester,
            "baseline_gpa": gpa,
            "baseline_credits": credits
        ]) { json in
            guard codeOK(json) else { throw AcademicError(msg(json, "保存失败")) }
        }
    }

    static func loadRegisteredCoursesBySemester(
        currentSemester: String,
        already: [String: [GpaCourseRow]],
        serverProvided: Bool = false
    ) async -> [String: [GpaCourseRow]] {
        if serverProvided { return already }
        var out = already
        let scan = AcademicCalc.lookbackGpaSemesters(currentSemester.isEmpty ? "大1上" : currentSemester)
        for sem in scan {
            if (out[sem] ?? []).contains(where: { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }) {
                continue
            }
            if case .success(let panel) = await fetchSubjectRegister(semester: sem) {
                let rows = panel.courses
                    .filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { $0.toGpaCourseRow() }
                if !rows.isEmpty { out[sem] = rows }
            }
        }
        return out
    }

    static func syncAcademicSession(_ session: AcademicSession) async {
        guard let json = await userGetInfo(), codeOK(json),
              let data = json["data"] as? [String: Any] else { return }
        let year = AcademicCalc.normalizeEnrollmentYear(stringValue(data["schoolyear"]))
        await MainActor.run {
            session.apply(
                school: stringValue(data["school"]),
                major: stringValue(data["major"]),
                schoolyear: Int(year) ?? 0,
                educationSystem: stringValue(data["education_system"])
            )
        }
    }

    static func persistAcademicProfile(
        school: String,
        major: String,
        schoolyear: Int,
        semester: String,
        educationSystem: String
    ) async {
        var params: [String: String] = [
            "school": school.trimmingCharacters(in: .whitespaces),
            "major": major.trimmingCharacters(in: .whitespaces)
        ]
        if let year = Int(AcademicCalc.normalizeEnrollmentYear(String(schoolyear))) {
            params["schoolyear"] = String(year)
        }
        let system = AcademicCalc.normalizeEducationSystem(educationSystem)
        if !system.isEmpty { params["education_system"] = system }
        _ = await ApiService.shared.updateUserInfo(params: params)
        if case .success(let existing) = await fetchSubjectRegister(semester: semester) {
            let courses = existing.courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
            if !courses.isEmpty {
                _ = await saveSubjectRegister(
                    semester: semester.isEmpty ? existing.semester : semester,
                    school: school.trimmingCharacters(in: .whitespaces),
                    major: major.trimmingCharacters(in: .whitespaces),
                    schoolyear: schoolyear,
                    courses: courses
                )
            }
        }
    }

    static func uploadImage(_ image: UIImage) async -> String? {
        await uploadImageMeta(image)?.url
    }

    static func uploadImageMeta(_ image: UIImage) async -> UploadedImageMeta? {
        let resized = resize(image, maxSide: 1600)
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        return await ApiService.shared.uploadFileMeta(imageData: data, fileName: "academic.jpg", mimeType: "image/jpeg")
    }

    static func fetchReviewBoard(date: String = "") async -> Result<ReviewBoard, Error> {
        let path = date.isEmpty ? "reviewBoard" : "reviewBoard?date=\(urlEncode(date))"
        return await get(path) { json in
            guard codeOK(json), let data = json["data"] as? [String: Any] else {
                throw AcademicError(msg(json, "加载失败"))
            }
            return parseReviewBoard(data)
        }
    }

    static func submitReviewCheckin(
        date: String,
        task: ReviewTask,
        doneAmount: Int,
        minutes: Int,
        note: String,
        photos: [String],
        makeup: Bool
    ) async -> Result<ReviewBoard, Error> {
        let photosJson = (try? String(data: JSONSerialization.data(withJSONObject: photos), encoding: .utf8)) ?? "[]"
        return await post("reviewCheckin", form: [
            "date": date,
            "task_key": task.taskKey,
            "done_amount": String(doneAmount),
            "minutes": String(minutes),
            "note": note,
            "photos": photosJson,
            "makeup": makeup ? "1" : "0"
        ]) { json in
            guard codeOK(json), let data = json["data"] as? [String: Any] else {
                throw AcademicError(msg(json, "打卡失败"))
            }
            return parseReviewBoard(data)
        }
    }

    // MARK: - parse

    private static func parseSubjectRegisterPanel(_ data: [String: Any]) -> SubjectRegisterPanel {
        SubjectRegisterPanel(
            semester: stringValue(data["semester"]),
            school: stringValue(data["school"]),
            major: stringValue(data["major"]),
            schoolyear: intValue(data["schoolyear"]),
            needProfile: boolValue(data["needProfile"]),
            done: boolValue(data["done"]),
            locked: boolValue(data["locked"]),
            classTeacherBound: boolValue(data["classTeacherBound"]),
            courses: parseSubjectRegisterRows(data["courses"])
        )
    }

    private static func parseSubjectRegisterRows(_ raw: Any?) -> [SubjectRegisterRow] {
        let arr = raw as? [[String: Any]] ?? []
        return arr.compactMap { c in
            let name = stringValue(c["subjectName"]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return SubjectRegisterRow(
                id: stringValue(c["id"]),
                subjectName: name,
                credits: stringValue(c["credits"]),
                subjectCode: stringValue(c["subjectCode"]),
                subjectType: stringValue(c["subjectType"]),
                assessmentMethod: stringValue(c["assessmentMethod"]),
                regularScoreRatio: stringValue(c["regularScoreRatio"]),
                midtermScoreRatio: stringValue(c["midtermScoreRatio"]),
                finalScoreRatio: stringValue(c["finalScoreRatio"]),
                remarks: stringValue(c["remarks"]),
                teachingUnit: stringValue(c["teachingUnit"]),
                classHours: stringValue(c["classHours"]),
                countsToGpa: stringValue(c["countsToGpa"]) == "否" ? "否" : "是"
            )
        }
    }

    private static func parseCourseRows(_ raw: Any?) -> [GpaCourseRow] {
        let arr = raw as? [[String: Any]] ?? []
        return arr.map {
            GpaCourseRow(
                subjectName: stringValue($0["subjectName"]),
                credits: stringValue($0["credits"]),
                examScore: stringValue($0["examScore"]),
                countsToGpa: stringValue($0["countsToGpa"]).isEmpty ? "是" : stringValue($0["countsToGpa"]),
                scoreStatus: stringValue($0["scoreStatus"]).isEmpty ? "正常" : stringValue($0["scoreStatus"])
            )
        }
    }

    private static func parseGpaPanel(_ data: [String: Any]) -> GpaPanelData {
        let courses = parseCourseRows(data["courses"])
        let baseline = data["baseline"] as? [String: Any]
        let termsArr = data["terms"] as? [[String: Any]] ?? []
        let termRows: [GpaTermRow] = termsArr.map {
            GpaTermRow(
                semester: stringValue($0["semester"]),
                termGpaDisplay: stringValue($0["termGpaDisplay"]),
                termCredits: doubleValue($0["termCredits"]),
                cumulativeGpaDisplay: stringValue($0["cumulativeGpaDisplay"]),
                cumulativeCredits: doubleValue($0["cumulativeCredits"]),
                entryMode: stringValue($0["entryMode"])
            )
        }
        let sem = stringValue(data["semester"])
        var termDisplay = ""
        var cumDisplay = ""
        var cumCredits = 0.0
        if let match = termRows.first(where: { $0.semester == sem }) {
            termDisplay = match.termGpaDisplay
            cumDisplay = match.cumulativeGpaDisplay
            cumCredits = match.cumulativeCredits
        }
        let coursesBySemesterProvided = data["coursesBySemester"] != nil
        var bySem: [String: [GpaCourseRow]] = [:]
        if let obj = data["coursesBySemester"] as? [String: Any] {
            for (key, value) in obj {
                let list = parseCourseRows(value).filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
                if !list.isEmpty { bySem[key] = list }
            }
        }
        if bySem.isEmpty {
            let named = courses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
            if !named.isEmpty { bySem[sem] = named }
        }
        return GpaPanelData(
            semester: sem,
            locked: boolValue(data["locked"]),
            classTeacherBound: boolValue(data["classTeacherBound"]),
            ruleId: intValue(data["ruleId"]),
            needsBaseline: boolValue(data["needsBaseline"]),
            expectedBaselineSemester: stringValue(data["expectedBaselineSemester"]).isEmpty ? nil : stringValue(data["expectedBaselineSemester"]),
            baselineGpa: optionalNumberString(baseline?["gpa"]),
            baselineCredits: optionalNumberString(baseline?["credits"]),
            courses: courses,
            coursesBySemester: bySem,
            coursesBySemesterProvided: coursesBySemesterProvided,
            termGpaDisplay: termDisplay,
            cumulativeGpaDisplay: cumDisplay,
            cumulativeCredits: cumCredits,
            terms: termRows,
            schoolyear: intValue(data["schoolyear"]),
            schoolyearLocked: boolValue(data["schoolyearLocked"]),
            needsProfileSetup: boolValue(data["needsProfileSetup"]),
            needsEnrollYear: boolValue(data["needsEnrollYear"]),
            needsRule: boolValue(data["needsRule"]),
            baselineSet: boolValue(data["baselineSet"]),
            gpaSource: stringValue(data["gpaSource"]).isEmpty ? "system" : stringValue(data["gpaSource"]),
            overrideGpa: optionalDouble(data["overrideGpa"]),
            overrideCredits: optionalDouble(data["overrideCredits"]),
            overrideSemester: stringValue(data["overrideSemester"])
        )
    }

    private static func parseGpaPlan(
        _ plan: [String: Any],
        baselineGpa: String,
        baselineCredits: String,
        showBaseline: Bool,
        expectedBaselineSemester: String,
        ruleId: Int
    ) -> GpaPlanData {
        let coursesArr = plan["courses"] as? [[String: Any]] ?? []
        let courses: [GpaPlanCourse] = coursesArr.map {
            let credits = doubleValue($0["credits"])
            return GpaPlanCourse(
                semester: stringValue($0["semester"]),
                subjectName: stringValue($0["subjectName"]),
                credits: credits,
                targetScore: stringValue($0["targetScore"]),
                locked: boolValue($0["locked"]),
                creditText: formatPlanCredits(credits),
                countsToGpa: stringValue($0["countsToGpa"]).isEmpty ? "是" : stringValue($0["countsToGpa"])
            )
        }
        let projected: Double? = {
            if plan["projectedGpa"] == nil || plan["projectedGpa"] is NSNull { return nil }
            return doubleValue(plan["projectedGpa"])
        }()
        var future: [String: String] = [:]
        if let raw = plan["futureCredits"] as? [String: Any] {
            for (k, v) in raw { future[k] = "\(v)" }
        }
        return GpaPlanData(
            targetSemester: stringValue(plan["targetSemester"]),
            targetGpa: doubleValue(plan["targetGpa"]),
            projectedGpa: projected,
            achievable: boolValue(plan["achievable"]),
            courses: courses,
            baselineGpa: baselineGpa,
            baselineCredits: baselineCredits,
            showBaseline: showBaseline,
            expectedBaselineSemester: expectedBaselineSemester,
            ruleId: ruleId,
            futureCredits: future
        )
    }

    private static func parseGpaPlanPreviewData(
        _ data: [String: Any]?,
        targetSemester: String,
        targetGpa: Double,
        ruleId: Int = 0,
        futureCredits: [String: String] = [:]
    ) -> GpaPlanData {
        let root = data ?? [:]
        let pending = root["pendingCourses"] as? [[String: Any]] ?? []
        let courses: [GpaPlanCourse] = pending.map { c in
            let credits = doubleValue(c["credits"])
            let score = stringValue(c["targetScore"])
            let point = doubleValue(c["targetPoint"])
            let displayScore: String = {
                if !score.isEmpty { return score }
                if point > 0 { return AcademicCalc.gpaPointToScoreRange(point) }
                return ""
            }()
            return GpaPlanCourse(
                semester: stringValue(c["semester"]),
                subjectName: stringValue(c["subjectName"]),
                credits: credits,
                targetScore: displayScore,
                locked: boolValue(c["locked"]),
                creditText: formatPlanCredits(credits),
                countsToGpa: stringValue(c["countsToGpa"]).isEmpty ? "是" : stringValue(c["countsToGpa"])
            )
        }
        let bucketsRaw = root["futureBuckets"] as? [[String: Any]] ?? []
        let futureBuckets = bucketsRaw.map {
            GpaFutureBucket(
                label: stringValue($0["semester"]),
                credits: doubleValue($0["credits"]),
                requiredAvgPoint: doubleValue($0["requiredAvgPoint"])
            )
        }
        let requiredAvg: Double? = root["requiredAvgPoint"] == nil || root["requiredAvgPoint"] is NSNull
            ? nil : doubleValue(root["requiredAvgPoint"])
        let maxPossible: Double? = root["maxPossibleGpa"] == nil || root["maxPossibleGpa"] is NSNull
            ? nil : doubleValue(root["maxPossibleGpa"])
        let achievable = root["achievable"] == nil ? true : boolValue(root["achievable"])
        let pendingCredits = courses.filter { !$0.locked }.reduce(0) { $0 + $1.resolvedCredits() }
        let futureSum = futureBuckets.reduce(0) { $0 + $1.credits }
        let hint: String = {
            if !achievable, let maxPossible {
                return String(format: "目标无法达成 · 待考全考满分累计最高 %.2f", maxPossible)
            }
            if let requiredAvg, achievable {
                return String(format: "待考 %.0f 学分 → 平均需 %.2f（约%@）", futureSum + pendingCredits, requiredAvg, AcademicCalc.gpaPointToScoreRange(requiredAvg))
            }
            return ""
        }()
        let projected: Double? = {
            if root["projectedGpa"] == nil || root["projectedGpa"] is NSNull { return nil }
            return doubleValue(root["projectedGpa"])
        }()
        return GpaPlanData(
            targetSemester: targetSemester,
            targetGpa: targetGpa,
            projectedGpa: projected,
            achievable: achievable,
            courses: courses,
            baselineGpa: "",
            baselineCredits: "",
            showBaseline: false,
            expectedBaselineSemester: "",
            ruleId: ruleId,
            maxPossibleGpa: maxPossible,
            requiredAvgPoint: requiredAvg,
            totalCredits: doubleValue(root["totalCredits"]),
            fixedCredits: doubleValue(root["fixedCredits"]),
            fixedQualityPoints: doubleValue(root["fixedQualityPoints"]),
            futureCredits: futureCredits,
            baselineHint: stringValue(root["baselineHint"]),
            futureBuckets: futureBuckets,
            hintMessage: hint
        )
    }

    private static func parseBands(_ raw: Any?) -> [GpaScoreBand] {
        let arr = raw as? [[String: Any]] ?? []
        return arr.map {
            GpaScoreBand(
                minScore: $0["minScore"] == nil || $0["minScore"] is NSNull ? nil : doubleValue($0["minScore"]),
                maxScore: $0["maxScore"] == nil || $0["maxScore"] is NSNull ? nil : doubleValue($0["maxScore"]),
                gradeLabel: stringValue($0["gradeLabel"]),
                point: doubleValue($0["point"])
            )
        }
    }

    private static func parseReviewBoard(_ data: [String: Any]) -> ReviewBoard {
        let summary = data["summary"] as? [String: Any] ?? [:]
        let alertJson = data["alert"] as? [String: Any]
        let groupsJson = data["groups"] as? [[String: Any]] ?? []
        let countdownJson = data["countdown"] as? [[String: Any]] ?? []
        let alert: ReviewAlert? = alertJson.map {
            ReviewAlert(
                taskKey: stringValue($0["taskKey"]),
                title: stringValue($0["title"]),
                subtitle: stringValue($0["subtitle"]),
                overdueLabel: stringValue($0["overdueLabel"]),
                target: intValue($0["target"]),
                unit: stringValue($0["unit"])
            )
        }
        let groups: [ReviewGroup] = groupsJson.map { group in
            let tasksJson = group["tasks"] as? [[String: Any]] ?? []
            return ReviewGroup(
                subjectName: stringValue(group["subjectName"]),
                color: stringValue(group["color"]).isEmpty ? "#14C8B4" : stringValue(group["color"]),
                tasks: tasksJson.map { task in
                    ReviewTask(
                        taskKey: stringValue(task["taskKey"]),
                        subjectName: stringValue(task["subjectName"]),
                        title: stringValue(task["title"]),
                        unit: stringValue(task["unit"]).isEmpty ? "题" : stringValue(task["unit"]),
                        target: intValue(task["target"]),
                        rolled: intValue(task["rolled"]),
                        overdue: boolValue(task["overdue"]),
                        overdueLabel: stringValue(task["overdueLabel"]),
                        done: boolValue(task["done"]),
                        doneAmount: intValue(task["doneAmount"]),
                        minutes: intValue(task["minutes"]),
                        finishedAt: stringValue(task["finishedAt"]),
                        meta: stringValue(task["meta"]),
                        hint: stringValue(task["hint"]),
                        canCheckin: boolValue(task["canCheckin"])
                    )
                }
            )
        }
        let countdown: [ReviewCountdown] = countdownJson.map {
            ReviewCountdown(
                subjectName: stringValue($0["subjectName"]),
                percent: intValue($0["percent"]),
                remaining: intValue($0["remaining"]),
                unit: stringValue($0["unit"]).isEmpty ? "题" : stringValue($0["unit"]),
                dailyAvg: intValue($0["dailyAvg"]),
                estimateLabel: stringValue($0["estimateLabel"]),
                planLabel: stringValue($0["planLabel"]),
                status: stringValue($0["status"]).isEmpty ? "na" : stringValue($0["status"]),
                statusText: stringValue($0["statusText"]),
                detail: stringValue($0["detail"])
            )
        }
        return ReviewBoard(
            semester: stringValue(data["semester"]),
            date: stringValue(data["date"]),
            today: stringValue(data["today"]),
            dateLabel: stringValue(data["dateLabel"]),
            canCheckin: boolValue(data["canCheckin"]),
            hasPlan: boolValue(data["hasPlan"]),
            summary: ReviewSummary(
                rate: intValue(summary["rate"]),
                total: intValue(summary["total"]),
                done: intValue(summary["done"]),
                pending: intValue(summary["pending"]),
                overdue: intValue(summary["overdue"]),
                headline: stringValue(summary["headline"]),
                subline: stringValue(summary["subline"])
            ),
            alert: alert,
            groups: groups,
            countdown: countdown
        )
    }

    private static func formatPlanCredits(_ credits: Double) -> String {
        if credits.isNaN || credits < 0 { return "" }
        if abs(credits - credits.rounded()) < 1e-6 { return String(Int(credits)) }
        return String(format: "%.1f", credits)
    }

    // MARK: - net

    private static func get<T>(_ path: String, map: ([String: Any]) throws -> T) async -> Result<T, Error> {
        guard let json = await academicGet(path) else { return .failure(AcademicError("网络错误")) }
        do { return .success(try map(json)) } catch { return .failure(error) }
    }

    private static func post<T>(_ path: String, form: [String: String], timeout: TimeInterval = 25, map: ([String: Any]) throws -> T) async -> Result<T, Error> {
        guard let json = await academicPost(path, form: form, timeout: timeout) else { return .failure(AcademicError("网络错误")) }
        do { return .success(try map(json)) } catch { return .failure(error) }
    }

    private static func academicGet(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: "\(base)/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        if let token = ApiService.shared.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return await send(request)
    }

    private static func academicPost(_ path: String, form: [String: String], timeout: TimeInterval) async -> [String: Any]? {
        guard let url = URL(string: "\(base)/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let token = ApiService.shared.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = form
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        return await send(request)
    }

    private static func userGetInfo() async -> [String: Any]? {
        guard let url = URL(string: "\(ApiConfig.baseURL)/api/user/getInfo") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        if let token = ApiService.shared.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return await send(request)
    }

    private static func send(_ request: URLRequest) async -> [String: Any]? {
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return out
    }

    static func codeOK(_ json: [String: Any]) -> Bool {
        if let i = json["code"] as? Int { return i == 200 }
        if let n = json["code"] as? NSNumber { return n.intValue == 200 }
        return false
    }

    static func stringValue(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    static func intValue(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    static func doubleValue(_ value: Any?, _ fallback: Double = 0) -> Double {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? fallback }
        return fallback
    }

    static func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    private static func optionalNumberString(_ value: Any?) -> String {
        if value == nil || value is NSNull { return "" }
        let s = stringValue(value)
        return s == "null" ? "" : s
    }

    private static func optionalDouble(_ value: Any?) -> Double? {
        if value == nil || value is NSNull { return nil }
        if let n = value as? NSNumber { return n.doubleValue }
        let s = stringValue(value)
        if s.isEmpty || s.lowercased() == "null" { return nil }
        return Double(s)
    }

    private static func msg(_ json: [String: Any], _ fallback: String) -> String {
        let m = stringValue(json["msg"])
        return m.isEmpty ? fallback : m
    }

    private static func jsonString(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

struct AcademicError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension SubjectRegisterRow {
    func asDict() -> [String: Any] {
        [
            "id": id,
            "subjectName": subjectName,
            "credits": credits,
            "subjectCode": subjectCode,
            "subjectType": subjectType,
            "assessmentMethod": assessmentMethod,
            "regularScoreRatio": regularScoreRatio,
            "midtermScoreRatio": midtermScoreRatio,
            "finalScoreRatio": finalScoreRatio,
            "remarks": remarks,
            "teachingUnit": teachingUnit,
            "classHours": classHours,
            "countsToGpa": countsToGpa == "否" ? "否" : "是"
        ]
    }
}

private extension GpaCourseRow {
    func asDict() -> [String: Any] {
        [
            "subjectName": subjectName,
            "credits": credits,
            "examScore": examScore,
            "countsToGpa": countsToGpa,
            "scoreStatus": scoreStatus
        ]
    }
}

private extension GpaPlanCourse {
    func asDict() -> [String: Any] {
        [
            "semester": semester,
            "subjectName": subjectName,
            "targetScore": targetScore,
            "locked": locked,
            "credits": resolvedCredits(),
            "countsToGpa": countsToGpa
        ]
    }
}

/// 本地删除墓碑（对齐 Android qaSubjectKey / loadRemovedQaSubjects）
enum QaSubjectTombstone {
    private static let prefPrefix = "jmm_qa_subject_tombstone."

    static func qaSubjectKey(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        let marks = CharacterSet(charactersIn: "【】「」《》\"'`“”")
        text = text.components(separatedBy: marks).joined()
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing = CharacterSet(charactersIn: "，。、；;,.:：！!？?~～·-—_")
        while let last = text.unicodeScalars.last, trailing.contains(last) {
            text.removeLast()
        }
        if text.count > 20 {
            text = String(text.prefix(20))
        }
        return text
    }

    private static func storageKey() -> String? {
        guard let token = ApiService.shared.token, !token.isEmpty else { return nil }
        return prefPrefix + token
    }

    static func loadRemoved() -> [String] {
        guard let key = storageKey() else { return [] }
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Array(Set(raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
    }

    private static func write(_ names: [String]) {
        guard let key = storageKey() else { return }
        UserDefaults.standard.set(names, forKey: key)
    }

    @discardableResult
    static func remember(_ name: String) -> [String] {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return loadRemoved() }
        let next = Array(Set(loadRemoved() + [clean]))
        write(next)
        return next
    }

    @discardableResult
    static func forget(_ name: String) -> [String] {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = qaSubjectKey(clean)
        let next = loadRemoved().filter { item in
            if item == clean { return false }
            if !key.isEmpty && qaSubjectKey(item) == key { return false }
            return true
        }
        write(next)
        return next
    }

    static func filter(_ names: [String], removed: [String]? = nil) -> [String] {
        let blockedRaw = Set((removed ?? loadRemoved()).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        if blockedRaw.isEmpty || names.isEmpty { return names }
        let blockedKeys = Set(blockedRaw.map { qaSubjectKey($0) }.filter { !$0.isEmpty })
        return names.filter { name in
            let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if blockedRaw.contains(raw) { return false }
            let key = qaSubjectKey(raw)
            return key.isEmpty || !blockedKeys.contains(key)
        }
    }
}
