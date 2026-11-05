import Foundation

struct HomeGradeGoalItem: Identifiable {
    let id: String
    let name: String
    let credit: String
    let goal: String
    let scored: Bool
}

private struct HomeGpaCourseRow {
    let subjectName: String
    let credits: String
    let examScore: String
}

private struct HomeGpaPlanCourse {
    let subjectName: String
    let targetScore: String
    let semester: String
}

enum AcademicHomeService {
    private static let semesterOrder = [
        "大1上", "大1下", "大2上", "大2下", "大3上", "大3下", "大4上", "大4下", "大5上", "大5下"
    ]

    static func loadGradeGoals(semesterHint: String = "") async -> [HomeGradeGoalItem] {
        async let summaryTask = fetchHomeSummaryGoals()
        async let panelTask = fetchGpaPanel(semesterHint: semesterHint)
        let summary = await summaryTask
        let panel = await panelTask
        let current = blank(semesterHint, panel.semester)
        var bySem = panel.coursesBySemester
        if !panel.provided && bySem.values.allSatisfy({ $0.isEmpty }) {
            bySem = await loadRegisteredCourses(current: current.isEmpty ? "大1上" : current, already: bySem)
        }
        let plan = await fetchGpaPlan(targetSemester: current)
        return mergeGoals(
            summaryGoals: summary,
            coursesBySemester: bySem,
            panelCourses: panel.courses,
            panelSemester: panel.semester,
            semesterHint: current,
            plan: plan
        )
    }

    private static func fetchHomeSummaryGoals() async -> [(name: String, credit: String, goal: String, scored: Bool, semester: String)] {
        guard let json = await academicGet("homeSummary"), codeOK(json),
              let data = json["data"] as? [String: Any] else { return [] }
        let arr = data["gradeGoals"] as? [[String: Any]] ?? []
        return arr.compactMap { item in
            let name = stringValue(item["name"])
            guard !name.isEmpty else { return nil }
            let exam = stringValue(item["examScore"])
            let scored = boolValue(item["scored"]) || !exam.isEmpty
            return (name, stringValue(item["credit"]), stringValue(item["goal"]), scored, stringValue(item["semester"]))
        }
    }

    private static func fetchGpaPanel(semesterHint: String) async -> (
        semester: String,
        courses: [HomeGpaCourseRow],
        coursesBySemester: [String: [HomeGpaCourseRow]],
        provided: Bool
    ) {
        let path = semesterHint.trimmingCharacters(in: .whitespaces).isEmpty
            ? "gpaPanel"
            : "gpaPanel?semester=\(urlEncode(semesterHint))"
        guard let json = await academicGet(path), codeOK(json),
              let data = json["data"] as? [String: Any] else {
            return ("", [], [:], false)
        }
        let semester = stringValue(data["semester"])
        let courses = parseCourses(data["courses"] as? [[String: Any]] ?? [])
        let provided = data["coursesBySemester"] != nil
        var bySem: [String: [HomeGpaCourseRow]] = [:]
        if let obj = data["coursesBySemester"] as? [String: Any] {
            for (key, value) in obj {
                let list = parseCourses(value as? [[String: Any]] ?? []).filter { !$0.subjectName.isEmpty }
                if !list.isEmpty { bySem[key] = list }
            }
        }
        if bySem.isEmpty && !courses.isEmpty {
            bySem[semester] = courses.filter { !$0.subjectName.isEmpty }
        }
        return (semester, courses, bySem, provided)
    }

    private static func fetchGpaPlan(targetSemester: String) async -> [HomeGpaPlanCourse] {
        let path = targetSemester.isEmpty
            ? "gpaPlan"
            : "gpaPlan?target_semester=\(urlEncode(targetSemester))"
        guard let json = await academicGet(path), codeOK(json),
              let data = json["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]],
              let plan = list.first,
              let courses = plan["courses"] as? [[String: Any]] else { return [] }
        return courses.compactMap { c in
            let name = stringValue(c["subjectName"]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return HomeGpaPlanCourse(
                subjectName: name,
                targetScore: stringValue(c["targetScore"]),
                semester: stringValue(c["semester"])
            )
        }
    }

    private static func loadRegisteredCourses(
        current: String,
        already: [String: [HomeGpaCourseRow]]
    ) async -> [String: [HomeGpaCourseRow]] {
        var out = already
        let scan = lookbackSemesters(current)
        for sem in scan {
            if (out[sem] ?? []).contains(where: { !$0.subjectName.isEmpty }) { continue }
            let rows = await fetchSubjectRegisterCourses(semester: sem)
            if !rows.isEmpty { out[sem] = rows }
        }
        return out
    }

    private static func fetchSubjectRegisterCourses(semester: String) async -> [HomeGpaCourseRow] {
        switch await AcademicApi.fetchSubjectRegister(semester: semester) {
        case .success(let panel):
            return panel.courses.compactMap { c in
                let name = c.subjectName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                return HomeGpaCourseRow(subjectName: name, credits: c.credits, examScore: "")
            }
        case .failure:
            return []
        }
    }

    private static func mergeGoals(
        summaryGoals: [(name: String, credit: String, goal: String, scored: Bool, semester: String)],
        coursesBySemester: [String: [HomeGpaCourseRow]],
        panelCourses: [HomeGpaCourseRow],
        panelSemester: String,
        semesterHint: String,
        plan: [HomeGpaPlanCourse]
    ) -> [HomeGradeGoalItem] {
        let current = blank(semesterHint, panelSemester)
        if current.isEmpty { return [] }

        var currentRows: [String: HomeGpaCourseRow] = [:]
        func absorb(_ row: HomeGpaCourseRow) {
            let name = row.subjectName.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return }
            if let prev = currentRows[name] {
                currentRows[name] = HomeGpaCourseRow(
                    subjectName: name,
                    credits: prev.credits.isEmpty ? row.credits : prev.credits,
                    examScore: prev.examScore.isEmpty ? row.examScore : prev.examScore
                )
            } else {
                currentRows[name] = HomeGpaCourseRow(subjectName: name, credits: row.credits, examScore: row.examScore)
            }
        }
        (coursesBySemester[current] ?? []).forEach(absorb)
        if panelSemester.isEmpty || panelSemester == current {
            panelCourses.forEach(absorb)
        }

        var examByName: [String: String] = [:]
        var creditByName: [String: String] = [:]
        for row in currentRows.values {
            if !row.examScore.trimmingCharacters(in: .whitespaces).isEmpty {
                examByName[row.subjectName] = row.examScore.trimmingCharacters(in: .whitespaces)
            }
            if !row.credits.trimmingCharacters(in: .whitespaces).isEmpty {
                creditByName[row.subjectName] = row.credits
            }
        }
        var pinByName: [String: String] = [:]
        for course in plan {
            let courseSemester = course.semester.trimmingCharacters(in: .whitespaces)
            if !courseSemester.isEmpty && courseSemester != current { continue }
            let score = course.targetScore.filter { $0.isNumber || $0 == "." }
            if !score.isEmpty { pinByName[course.subjectName] = score }
        }

        func toItem(name: String, creditRaw: String, fallbackGoal: String, scoredHint: Bool = false) -> HomeGradeGoalItem {
            let key = name.trimmingCharacters(in: .whitespaces)
            let exam = examByName[key] ?? ""
            let scored = !exam.isEmpty || (scoredHint && !fallbackGoal.isEmpty)
            let goal: String
            if !exam.isEmpty {
                goal = exam
            } else if let pin = pinByName[key], !pin.isEmpty {
                goal = pin
            } else {
                goal = fallbackGoal.isEmpty ? "95" : fallbackGoal
            }
            let credit = formatCredit(creditRaw.isEmpty ? (creditByName[key] ?? "") : creditRaw)
            return HomeGradeGoalItem(id: key, name: key, credit: credit, goal: formatGoalScore(goal), scored: scored)
        }

        let tagged = summaryGoals.filter { !$0.semester.trimmingCharacters(in: .whitespaces).isEmpty && !$0.name.isEmpty }
        if !tagged.isEmpty {
            return tagged.filter { $0.semester.trimmingCharacters(in: .whitespaces) == current }
                .map { toItem(name: $0.name, creditRaw: $0.credit, fallbackGoal: $0.goal, scoredHint: $0.scored) }
        }
        if !currentRows.isEmpty {
            var summaryByName: [String: (name: String, credit: String, goal: String, scored: Bool, semester: String)] = [:]
            for item in summaryGoals where !item.name.isEmpty {
                summaryByName[item.name.trimmingCharacters(in: .whitespaces)] = item
            }
            return currentRows.values.map { row in
                let summary = summaryByName[row.subjectName]
                return toItem(
                    name: row.subjectName,
                    creditRaw: (summary?.credit ?? "").isEmpty ? row.credits : (summary?.credit ?? ""),
                    fallbackGoal: summary?.goal ?? "",
                    scoredHint: summary?.scored == true
                )
            }
        }
        let pastNames = Set(
            coursesBySemester
                .filter { $0.key.trimmingCharacters(in: .whitespaces) != current }
                .flatMap { $0.value }
                .map { $0.subjectName.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        return summaryGoals
            .filter { !$0.name.isEmpty && !pastNames.contains($0.name.trimmingCharacters(in: .whitespaces)) }
            .map { toItem(name: $0.name, creditRaw: $0.credit, fallbackGoal: $0.goal, scoredHint: $0.scored) }
    }

    private static func blank(_ value: String, _ fallback: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? fallback.trimmingCharacters(in: .whitespaces) : text
    }

    private static func parseCourses(_ arr: [[String: Any]]) -> [HomeGpaCourseRow] {
        arr.map {
            HomeGpaCourseRow(
                subjectName: stringValue($0["subjectName"]),
                credits: stringValue($0["credits"]),
                examScore: stringValue($0["examScore"])
            )
        }
    }

    private static func lookbackSemesters(_ current: String) -> [String] {
        let idx = semesterOrder.firstIndex(of: current.trimmingCharacters(in: .whitespaces))
        guard let idx else {
            let c = current.trimmingCharacters(in: .whitespaces)
            return c.isEmpty ? ["大1上"] : [c]
        }
        return Array(semesterOrder.prefix(idx + 1))
    }

    private static func formatGoalScore(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "分", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let n = Double(text) else { return text.isEmpty ? "95" : text }
        if abs(n - n.rounded()) < 0.05 { return String(Int(n.rounded())) }
        return String(format: "%.1f", n)
    }

    private static func formatCredit(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return "" }
        if text.contains("学分") { return text }
        guard let n = Double(text) else { return text }
        return String(format: "%.1f学分", n)
    }

    private static func academicGet(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: "\(ApiConfig.baseURL)/api/studentAcademic/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        if let token = ApiService.shared.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func codeOK(_ json: [String: Any]) -> Bool {
        if let i = json["code"] as? Int { return i == 200 }
        if let n = json["code"] as? NSNumber { return n.intValue == 200 }
        return false
    }

    private static func stringValue(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
