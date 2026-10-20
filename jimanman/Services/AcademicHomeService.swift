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
}

enum AcademicHomeService {
    private static let semesterOrder = [
        "大1上", "大1下", "大2上", "大2下", "大3上", "大3下", "大4上", "大4下", "大5上", "大5下"
    ]

    static func loadGradeGoals() async -> [HomeGradeGoalItem] {
        async let summaryTask = fetchHomeSummaryGoals()
        async let panelTask = fetchGpaPanel()
        let summary = await summaryTask
        let panel = await panelTask
        let current = panel.semester
        var bySem = panel.coursesBySemester
        if bySem.values.allSatisfy({ $0.isEmpty }) {
            bySem = await loadRegisteredCourses(current: current.isEmpty ? "大1上" : current, already: bySem)
        }
        let plan = await fetchGpaPlan(targetSemester: current)
        return mergeGoals(summaryGoals: summary, coursesBySemester: bySem, panelCourses: panel.courses, panelSemester: current, plan: plan)
    }

    private static func fetchHomeSummaryGoals() async -> [(name: String, credit: String, goal: String, scored: Bool)] {
        guard let json = await academicGet("homeSummary"), codeOK(json),
              let data = json["data"] as? [String: Any] else { return [] }
        let arr = data["gradeGoals"] as? [[String: Any]] ?? []
        return arr.compactMap { item in
            let name = stringValue(item["name"])
            guard !name.isEmpty else { return nil }
            let exam = stringValue(item["examScore"])
            let scored = boolValue(item["scored"]) || !exam.isEmpty
            return (name, stringValue(item["credit"]), stringValue(item["goal"]), scored)
        }
    }

    private static func fetchGpaPanel() async -> (
        semester: String,
        courses: [HomeGpaCourseRow],
        coursesBySemester: [String: [HomeGpaCourseRow]]
    ) {
        guard let json = await academicGet("gpaPanel"), codeOK(json),
              let data = json["data"] as? [String: Any] else {
            return ("", [], [:])
        }
        let semester = stringValue(data["semester"])
        let courses = parseCourses(data["courses"] as? [[String: Any]] ?? [])
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
        return (semester, courses, bySem)
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
            return HomeGpaPlanCourse(subjectName: name, targetScore: stringValue(c["targetScore"]))
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
        let path = semester.isEmpty
            ? "subjectRegister"
            : "subjectRegister?semester=\(urlEncode(semester))"
        guard let json = await academicGet(path), codeOK(json),
              let data = json["data"] as? [String: Any] else { return [] }
        let courses = data["courses"] as? [[String: Any]] ?? []
        return courses.compactMap { c in
            let name = stringValue(c["subjectName"]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return HomeGpaCourseRow(subjectName: name, credits: stringValue(c["credits"]), examScore: "")
        }
    }

    private static func mergeGoals(
        summaryGoals: [(name: String, credit: String, goal: String, scored: Bool)],
        coursesBySemester: [String: [HomeGpaCourseRow]],
        panelCourses: [HomeGpaCourseRow],
        panelSemester: String,
        plan: [HomeGpaPlanCourse]
    ) -> [HomeGradeGoalItem] {
        var examByName: [String: String] = [:]
        var creditByName: [String: String] = [:]
        let rows = coursesBySemester.values.flatMap { $0 } + panelCourses
        for row in rows where !row.subjectName.trimmingCharacters(in: .whitespaces).isEmpty {
            let name = row.subjectName.trimmingCharacters(in: .whitespaces)
            if !row.examScore.trimmingCharacters(in: .whitespaces).isEmpty {
                examByName[name] = row.examScore.trimmingCharacters(in: .whitespaces)
            }
            if !row.credits.trimmingCharacters(in: .whitespaces).isEmpty {
                creditByName[name] = row.credits
            }
        }
        var pinByName: [String: String] = [:]
        for course in plan {
            let score = course.targetScore.filter { $0.isNumber || $0 == "." }
            if !score.isEmpty { pinByName[course.subjectName] = score }
        }

        func toItem(name: String, creditRaw: String, fallbackGoal: String) -> HomeGradeGoalItem {
            let exam = examByName[name] ?? ""
            let scored = !exam.isEmpty
            let goal: String
            if scored {
                goal = exam
            } else if let pin = pinByName[name], !pin.isEmpty {
                goal = pin
            } else {
                goal = fallbackGoal.isEmpty ? "95" : fallbackGoal
            }
            let credit = formatCredit(creditRaw.isEmpty ? (creditByName[name] ?? "") : creditRaw)
            return HomeGradeGoalItem(
                id: name,
                name: name,
                credit: credit,
                goal: formatGoalScore(goal),
                scored: scored
            )
        }

        if !summaryGoals.isEmpty {
            return summaryGoals.map { toItem(name: $0.name, creditRaw: $0.credit, fallbackGoal: $0.goal) }
        }
        let currentRows = panelCourses.filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
        let fallbackRows = currentRows.isEmpty ? (coursesBySemester[panelSemester] ?? []) : currentRows
        if !fallbackRows.isEmpty {
            return fallbackRows.map {
                let name = $0.subjectName.trimmingCharacters(in: .whitespaces)
                return toItem(name: name, creditRaw: $0.credits, fallbackGoal: pinByName[name] ?? "")
            }
        }
        return semesterOrder.compactMap { coursesBySemester[$0] }.flatMap { $0 }
            .filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
            .reduce(into: [HomeGpaCourseRow]()) { acc, row in
                let name = row.subjectName.trimmingCharacters(in: .whitespaces)
                if !acc.contains(where: { $0.subjectName.trimmingCharacters(in: .whitespaces) == name }) {
                    acc.append(row)
                }
            }
            .map {
                let name = $0.subjectName.trimmingCharacters(in: .whitespaces)
                return toItem(name: name, creditRaw: $0.credits, fallbackGoal: pinByName[name] ?? "")
            }
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
