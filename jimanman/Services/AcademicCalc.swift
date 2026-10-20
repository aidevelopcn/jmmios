import Foundation

enum AcademicCalc {
    static let std4Tiers: [(Double, Double)] = [
        (90, 4.0), (85, 3.7), (82, 3.3), (78, 3.0), (75, 2.7),
        (72, 2.3), (68, 2.0), (64, 1.5), (60, 1.0), (0, 0.0)
    ]
    static let simple4Tiers: [(Double, Double)] = [
        (90, 4.0), (80, 3.0), (70, 2.0), (60, 1.0), (0, 0.0)
    ]

    static func currentAcademicYearAndHalf(_ date: Date = Date()) -> (Int, String) {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        if month >= 8 { return (year, "上") }
        if month == 1 { return (year - 1, "上") }
        return (year - 1, "下")
    }

    static func inferGpaSemesterCode(_ enrollYear: Int, now: Date = Date()) -> String {
        guard enrollYear >= 1990, enrollYear <= 2100 else { return "" }
        let (ay, half) = currentAcademicYearAndHalf(now)
        let grade = min(max(ay - enrollYear + 1, 1), 5)
        return "大\(grade)\(half)"
    }

    static func lookbackGpaSemesters(_ current: String) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        guard let idx = gpaSemesterOrder.firstIndex(of: trimmed) else {
            return trimmed.isEmpty ? ["大1上"] : [trimmed]
        }
        return Array(gpaSemesterOrder.prefix(idx + 1))
    }

    static func gpaRowsForSemester(_ bySemester: [String: [GpaCourseRow]], _ semester: String) -> [GpaCourseRow] {
        (bySemester[semester] ?? []).filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func registeredCreditsOf(_ courses: [GpaCourseRow]) -> Double {
        courses
            .filter { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty && $0.countsToGpa != "否" }
            .reduce(0) { $0 + (Double($1.credits.trimmingCharacters(in: .whitespaces)) ?? 0) }
    }

    static func isPastGpaSemester(_ code: String, current: String) -> Bool {
        guard let cur = gpaSemesterOrder.firstIndex(of: current.trimmingCharacters(in: .whitespaces)),
              let idx = gpaSemesterOrder.firstIndex(of: code.trimmingCharacters(in: .whitespaces)) else { return false }
        return idx < cur
    }

    static func pastRegisteredCredits(_ current: String, _ coursesBySemester: [String: [GpaCourseRow]]) -> Double {
        coursesBySemester
            .filter { isPastGpaSemester($0.key, current: current) }
            .reduce(0) { $0 + registeredCreditsOf($1.value) }
    }

    static func sortedGpaRules(_ rules: [GpaRuleOption]) -> [GpaRuleOption] {
        func rank(_ rule: GpaRuleOption) -> Int {
            let n = displayGpaRuleName(rule)
            switch n {
            case "标准 4.0": return 0
            case "简单 4.0": return 1
            case "5.0制5级分段": return 2
            default:
                if rule.name.contains("成绩-50") { return 3 }
                if rule.name.contains("等级") { return 4 }
                return 5
            }
        }
        return rules.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            return ra == rb ? a.id < b.id : ra < rb
        }
    }

    static func pickDefaultGpaRuleId(_ rules: [GpaRuleOption]) -> Int {
        sortedGpaRules(rules).first?.id ?? 0
    }

    static func formatGpaCredits(_ credits: Double) -> String {
        if credits <= 0 { return "0" }
        let rounded = (credits * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    static func previousGpaSemesterCode(_ code: String) -> String? {
        guard let idx = gpaSemesterOrder.firstIndex(of: code.trimmingCharacters(in: .whitespaces)), idx > 0 else { return nil }
        return gpaSemesterOrder[idx - 1]
    }

    static func nextGpaSemester(_ current: String) -> String? {
        guard let idx = gpaSemesterOrder.firstIndex(of: current.trimmingCharacters(in: .whitespaces)),
              idx < gpaSemesterOrder.count - 1 else { return nil }
        return gpaSemesterOrder[idx + 1]
    }

    static func latestRegisteredSemester(_ bySemester: [String: [GpaCourseRow]], prefer: String = "") -> String {
        func named(_ rows: [GpaCourseRow]) -> Bool {
            rows.contains { !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if !prefer.isEmpty, named(bySemester[prefer] ?? []) { return prefer }
        return bySemester
            .filter { named($0.value) }
            .max { a, b in
                (gpaSemesterOrder.firstIndex(of: a.key.trimmingCharacters(in: .whitespaces)) ?? Int.min)
                    < (gpaSemesterOrder.firstIndex(of: b.key.trimmingCharacters(in: .whitespaces)) ?? Int.min)
            }?
            .key ?? ""
    }

    static func cumulativeRegisteredCredits(
        currentSemester: String,
        currentCourses: [GpaCourseRow],
        coursesBySemester: [String: [GpaCourseRow]]
    ) -> Double {
        var total = registeredCreditsOf(currentCourses)
        if total <= 0 {
            total += registeredCreditsOf(coursesBySemester[currentSemester] ?? [])
        }
        total += pastRegisteredCredits(currentSemester, coursesBySemester)
        return total
    }

    static func gradeNameOfScore(_ score: Double?) -> String {
        guard let score else { return "待录入" }
        if score >= 90 { return "优" }
        if score >= 80 { return "良" }
        if score >= 70 { return "中" }
        if score >= 60 { return "及格" }
        return "不及格"
    }

    static func weightedScoreAverage(_ courses: [GpaCourseRow]) -> String {
        var credits = 0.0
        var total = 0.0
        for row in scoredCourses(courses) {
            guard let score = Double(row.examScore.trimmingCharacters(in: .whitespaces)),
                  let credit = Double(row.credits.trimmingCharacters(in: .whitespaces)) else { continue }
            credits += credit
            total += score * credit
        }
        return credits > 0 ? String(format: "%.1f", total / credits) : "—"
    }

    static func formatGpaOrDash(_ stats: GpaTermStats) -> String {
        stats.credits > 0 ? String(format: "%.2f", stats.gpa) : "—"
    }

    static func yearStatsOf(
        currentSemester: String,
        currentCourses: [GpaCourseRow],
        terms: [GpaTermRow],
        rule: GpaRuleOption?,
        coursesBySemester: [String: [GpaCourseRow]] = [:]
    ) -> GpaTermStats? {
        guard let grade = gradeDigit(currentSemester) else { return nil }
        let fall = "大\(grade)上"
        let spring = "大\(grade)下"
        var credits = 0.0
        var points = 0.0
        for sem in [fall, spring] {
            let rows = sem == currentSemester ? currentCourses : (coursesBySemester[sem] ?? [])
            let st = termStatsOf(rows, rule: rule)
            if st.credits > 0 {
                credits += st.credits
                points += st.gpa * st.credits
                continue
            }
            if let term = terms.first(where: { $0.semester == sem && $0.termCredits > 0 }),
               let gpa = Double(term.termGpaDisplay) {
                credits += term.termCredits
                points += gpa * term.termCredits
            }
        }
        return credits > 0 ? GpaTermStats(gpa: points / credits, credits: credits) : nil
    }

    static func cumulativeStatsOf(
        currentSemester: String,
        currentCourses: [GpaCourseRow],
        terms: [GpaTermRow],
        baselineGpa: String,
        baselineCredits: String,
        rule: GpaRuleOption?,
        pastCoursesBySemester: [String: [GpaCourseRow]] = [:]
    ) -> GpaTermStats? {
        var current = termStatsOf(currentCourses, rule: rule)
        if current.credits <= 0,
           let term = terms.first(where: { $0.semester == currentSemester && $0.termCredits > 0 }),
           let gpa = Double(term.termGpaDisplay) {
            current = GpaTermStats(gpa: gpa, credits: term.termCredits)
        }
        let past = mergedPastTermStats(
            current: currentSemester,
            terms: terms,
            pastCoursesBySemester: pastCoursesBySemester,
            rule: rule
        )
        var credits = 0.0
        var points = 0.0
        if !past.isEmpty {
            for term in past {
                credits += term.credits
                points += term.gpa * term.credits
            }
        } else if let gpa = Double(baselineGpa), let cr = Double(baselineCredits), cr > 0 {
            credits += cr
            points += gpa * cr
        }
        if current.credits > 0 {
            credits += current.credits
            points += current.gpa * current.credits
        }
        return credits > 0 ? GpaTermStats(gpa: points / credits, credits: credits) : nil
    }

    static func gradeDigit(_ semester: String) -> String? {
        guard let match = semester.range(of: #"大([1-5])"#, options: .regularExpression) else { return nil }
        let text = String(semester[match])
        return String(text.dropFirst())
    }

    static func ruleLooksSimple(_ rule: GpaRuleOption?) -> Bool {
        let key = "\(rule?.name ?? "")\(rule?.scoreType ?? "")"
        return key.contains("简单") || key.contains("五级") || key.contains("五档")
    }

    static func isSimpleGpaRule(_ rule: GpaRuleOption?) -> Bool { ruleLooksSimple(rule) }

    static func scoreToGpaPoint(_ score: Double?, rule: GpaRuleOption?) -> Double? {
        guard let score, score >= 0, score <= 100 else { return nil }
        if rule?.formula == "linear_50" {
            if score < 60 { return 0 }
            let point = (score - 50.0) / 10.0
            let maxP = (rule?.maxPoint ?? 0) > 0 ? (rule?.maxPoint ?? 4) : 4
            return min(max(point, 0), maxP)
        }
        let bands = rule?.bands ?? []
        if !bands.isEmpty {
            for band in bands {
                if let minS = band.minScore, score >= minS, band.maxScore == nil || score <= (band.maxScore ?? 100) {
                    return band.point
                }
            }
            return 0
        }
        let tiers = ruleLooksSimple(rule) ? simple4Tiers : std4Tiers
        for (min, point) in tiers where score >= min {
            return point
        }
        return 0
    }

    static func scoredCourses(_ courses: [GpaCourseRow]) -> [GpaCourseRow] {
        courses.filter {
            !$0.subjectName.trimmingCharacters(in: .whitespaces).isEmpty
                && $0.countsToGpa != "否"
                && Double($0.examScore.trimmingCharacters(in: .whitespaces)) != nil
        }
    }

    static func termStatsOf(_ courses: [GpaCourseRow], rule: GpaRuleOption?) -> GpaTermStats {
        var credits = 0.0
        var points = 0.0
        for row in scoredCourses(courses) {
            guard let score = Double(row.examScore.trimmingCharacters(in: .whitespaces)),
                  let credit = Double(row.credits.trimmingCharacters(in: .whitespaces)),
                  let gp = scoreToGpaPoint(score, rule: rule) else { continue }
            credits += credit
            points += gp * credit
        }
        return credits > 0 ? GpaTermStats(gpa: points / credits, credits: credits) : GpaTermStats(gpa: 0, credits: 0)
    }

    static func mergedPastTermStats(
        current: String,
        terms: [GpaTermRow],
        pastCoursesBySemester: [String: [GpaCourseRow]],
        rule: GpaRuleOption?
    ) -> [GpaTermStats] {
        var bySem: [String: GpaTermStats] = [:]
        for term in terms {
            guard isPastGpaSemester(term.semester, current: current), term.termCredits > 0,
                  let gpa = Double(term.termGpaDisplay) else { continue }
            bySem[term.semester] = GpaTermStats(gpa: gpa, credits: term.termCredits)
        }
        for (sem, rows) in pastCoursesBySemester {
            if !isPastGpaSemester(sem, current: current) || bySem[sem] != nil { continue }
            let st = termStatsOf(rows, rule: rule)
            if st.credits > 0 { bySem[sem] = st }
        }
        return Array(bySem.values)
    }

    static func pastHistoryStats(
        currentSemester: String,
        terms: [GpaTermRow],
        baselineGpa: String,
        baselineCredits: String,
        pastCoursesBySemester: [String: [GpaCourseRow]] = [:],
        rule: GpaRuleOption? = nil
    ) -> PastHistoryStats {
        let past = mergedPastTermStats(
            current: currentSemester,
            terms: terms,
            pastCoursesBySemester: pastCoursesBySemester,
            rule: rule
        )
        let registered = pastRegisteredCredits(currentSemester, pastCoursesBySemester)
        if !past.isEmpty {
            let scoredCredits = past.reduce(0) { $0 + $1.credits }
            let points = past.reduce(0) { $0 + $1.gpa * $1.credits }
            return PastHistoryStats(
                gpa: scoredCredits > 0 ? points / scoredCredits : 0,
                credits: max(scoredCredits, registered),
                src: "明细"
            )
        }
        if let gpa = Double(baselineGpa), let credits = Double(baselineCredits), credits > 0 {
            return PastHistoryStats(gpa: gpa, credits: max(credits, registered), src: "一键填")
        }
        if registered > 0 {
            return PastHistoryStats(gpa: 0, credits: registered, src: "科目登记")
        }
        return PastHistoryStats(gpa: 0, credits: 0, src: "")
    }

    static func displayGpaRuleName(_ rule: GpaRuleOption?) -> String {
        let name = rule?.name ?? ""
        let maxP = rule?.maxPoint ?? 0
        if name.contains("十级") || name.contains("十档") || name.contains("细分") { return "标准 4.0" }
        if isFivePointBandRule(name, maxP) { return "5.0制5级分段" }
        if name.contains("五级") || name.contains("五档") || name.contains("简单") { return "简单 4.0" }
        return name.isEmpty ? "标准 4.0" : name
    }

    static func displayGpaRulePickerLabel(_ rule: GpaRuleOption) -> String {
        switch displayGpaRuleName(rule) {
        case "标准 4.0": return "标准 4.0（十档）"
        case "简单 4.0": return "简单 4.0（五档）"
        case "5.0制5级分段": return "5.0制5级分段"
        default: return rule.name.isEmpty ? displayGpaRuleName(rule) : rule.name
        }
    }

    private static func isFivePointBandRule(_ name: String, _ maxPoint: Double) -> Bool {
        let fiveScale = name.contains("5.0") || name.contains("5制") || maxPoint >= 4.95
        let banded = name.contains("五级") || name.contains("五档") || name.contains("分段")
        return fiveScale && banded && !name.contains("成绩-50")
    }

    static func displayGpaSemesterName(_ code: String) -> String {
        guard let match = code.trimmingCharacters(in: .whitespaces).range(of: #"大([1-5])([上下])"#, options: .regularExpression) else {
            return code
        }
        let text = String(code[match])
        let gradeChar = text.dropFirst().prefix(1)
        let half = String(text.suffix(1))
        let names = ["", "一", "二", "三", "四", "五"]
        let grade = Int(gradeChar) ?? 0
        let shown = grade < names.count ? names[grade] : String(grade)
        return "大\(shown)\(half)"
    }

    static func displayGpaSemesterBadge(_ code: String) -> String {
        guard let match = code.trimmingCharacters(in: .whitespaces).range(of: #"大([1-5])([上下])"#, options: .regularExpression) else {
            return code
        }
        let text = String(code[match])
        let gradeChar = text.dropFirst().prefix(1)
        let half = String(text.suffix(1))
        let names = ["", "一", "二", "三", "四", "五"]
        let grade = Int(gradeChar) ?? 0
        let shown = grade < names.count ? names[grade] : String(grade)
        return "大\(shown) · \(half)"
    }

    static func maxGradeByEducationSystem(_ edu: String) -> Int {
        if edu.contains("三") { return 3 }
        if edu.contains("五") { return 5 }
        return 4
    }

    static func futureSemestersInclusive(current: String, target: String, maxGrade: Int) -> [String] {
        let capIdx = gpaSemesterOrder.firstIndex(of: "大\(maxGrade)下") ?? (gpaSemesterOrder.count - 1)
        let start = max(gpaSemesterOrder.firstIndex(of: current.trimmingCharacters(in: .whitespaces)) ?? 0, 0)
        let endRaw = gpaSemesterOrder.firstIndex(of: target.trimmingCharacters(in: .whitespaces)) ?? start
        let end = min(endRaw, capIdx)
        if end < start { return [current] }
        return Array(gpaSemesterOrder[start...end])
    }

    static func bandOfNeed(_ need: Double, simple: Bool) -> ReverseBand? {
        if need.isNaN { return nil }
        let tiers = simple ? simple4Tiers : std4Tiers
        for i in stride(from: tiers.count - 1, through: 0, by: -1) {
            let min = tiers[i].0
            let point = tiers[i].1
            if point >= need - 1e-9 {
                let maxScore = i == 0 ? 100.0 : tiers[i - 1].0 - 1
                let text: String
                if i == 0 {
                    text = "90+分"
                } else if min == 0 {
                    text = "60以下"
                } else {
                    text = "\(Int(min))~\(Int(maxScore))分"
                }
                return ReverseBand(min: Int(min), text: text, point: point)
            }
        }
        return nil
    }

    static func computeReverse(
        cum: Bool,
        isNow: Bool,
        target: Double,
        histG: Double,
        histC: Double,
        histSrc: String,
        termC: Double,
        totalCredits: Double,
        fixedC: Double,
        fixedP: Double,
        fixedN: Int,
        simple: Bool
    ) -> ReverseCalc {
        if cum {
            let total = isNow ? max(histC + termC, totalCredits) : totalCredits
            let pending = total - histC
            let gap = target * total - histG * histC
            let maxGpa = total > 0 ? (4.0 * pending + histG * histC) / total : 0
            let futureC = isNow ? 0.0 : max(pending - termC, 0)
            let restC = pending - fixedC
            let need = restC > 0 ? (gap - fixedP) / restC : 0
            let reachable = pending > 0 && (restC > 0 ? need <= 4.0 + 1e-9 : fixedP >= gap - 1e-9)
            return ReverseCalc(
                cum: true, isNow: isNow, target: target, need: need, restC: restC, pending: pending,
                total: total, histC: histC, histG: histG, histSrc: histSrc, termC: termC,
                fixedC: fixedC, fixedP: fixedP, fixedN: fixedN, futureC: futureC,
                reachable: reachable, maxGpa: maxGpa, band: bandOfNeed(need, simple: simple)
            )
        }
        let gap = target * termC
        let restC = termC - fixedC
        let need = restC > 0 ? (gap - fixedP) / restC : 0
        let reachable = termC > 0 && (restC > 0 ? need <= 4.0 + 1e-9 : fixedP >= gap - 1e-9)
        let maxGpa = termC > 0 ? (4.0 * max(restC, 0) + fixedP) / termC : 4
        return ReverseCalc(
            cum: false, isNow: true, target: target, need: need, restC: restC, pending: termC,
            total: termC, histC: histC, histG: histG, histSrc: histSrc, termC: termC,
            fixedC: fixedC, fixedP: fixedP, fixedN: fixedN, futureC: 0,
            reachable: reachable, maxGpa: maxGpa, band: bandOfNeed(need, simple: simple)
        )
    }

    static func estimateTotalCreditsBySystem(_ educationSystem: String) -> Int {
        if educationSystem.contains("五") { return 170 }
        if educationSystem.contains("三") { return 90 }
        return 140
    }

    static func normalizeEnrollmentYear(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let year = Int(String(digits.prefix(4))) ?? 0
        return (enrollmentYearMin...enrollmentYearMax).contains(year) ? String(year) : ""
    }

    static func normalizeEducationSystem(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        return educationSystemOptions.first(where: { $0 == value }) ?? ""
    }

    static func hasProfileEnrollmentYear(_ schoolyear: Int, locked: Bool = false) -> Bool {
        locked || (enrollmentYearMin...enrollmentYearMax).contains(schoolyear)
    }

    static func hasProfileEducationSystem(_ educationSystem: String) -> Bool {
        !normalizeEducationSystem(educationSystem).isEmpty
    }

    static func semesterListByGrade(_ maxGrade: Int) -> [String] {
        gpaSemesterOrder.filter { code in
            let grade = Int(code.dropFirst().prefix(1)) ?? 0
            return (1...maxGrade).contains(grade)
        }
    }

    static func isFutureSemester(_ code: String, current: String) -> Bool {
        guard let cur = gpaSemesterOrder.firstIndex(of: current),
              let idx = gpaSemesterOrder.firstIndex(of: code) else { return false }
        return idx > cur
    }

    static func defaultEnrollmentYear() -> Int {
        min(max(Calendar.current.component(.year, from: Date()), enrollmentYearMin), enrollmentYearMax)
    }

    static func enrollmentYearOptions() -> [String] {
        (enrollmentYearMin...enrollmentYearMax).map { String($0) }
    }
}
