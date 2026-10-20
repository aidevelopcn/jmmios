import Foundation
import Combine

let gpaSemesterOrder = [
    "大1上", "大1下", "大2上", "大2下", "大3上", "大3下", "大4上", "大4下", "大5上", "大5下"
]
let gpaCreditOptions = ["1", "1.5", "2", "3", "4", "5", "6"]
let enrollmentYearMin = 2023
let enrollmentYearMax = 2030
let educationSystemOptions = ["四年本科", "五年本科", "三年专科", "其他"]
let subjectLockedHint = "该学期科目登记已由班主任/教务完成，如需修改请联系班主任在后台调整"
let subjectAttrs = ["必修", "选修", "通识", "其他"]
let defaultPlanTargetSemester = "大3下"

enum PlanCalcMode: Int, CaseIterable {
    case cumulative
    case semester
    var label: String {
        switch self {
        case .cumulative: return "按累计 GPA"
        case .semester: return "按本学期 GPA"
        }
    }
}

enum GpaViewScope: Int, CaseIterable {
    case term, year, cumulative
    var label: String {
        switch self {
        case .term: return "本学期"
        case .year: return "本学年"
        case .cumulative: return "累计"
        }
    }
}

enum HistoryEntryMode: Int, CaseIterable {
    case packed, perTerm
    var label: String {
        switch self {
        case .packed: return "历史一键填"
        case .perTerm: return "逐学期填写"
        }
    }
}

struct GpaProfileSetupResult {
    var schoolyear: Int
    var schoolyearLocked: Bool
    var ruleId: Int
    var semester: String
}

let educationSystemDemoOptions: [(String, String)] = [
    ("四年本科", "四年制（最多到大四下）"),
    ("五年本科", "五年制（含大五上 / 大五下）"),
    ("三年专科", "三年制（最多到大三下）")
]

struct GpaScoreBand {
    let minScore: Double?
    let maxScore: Double?
    let gradeLabel: String
    let point: Double
}

struct GpaRuleOption: Identifiable {
    let id: Int
    let name: String
    let scoreType: String
    let maxPoint: Double
    let formula: String
    let bands: [GpaScoreBand]
}

struct GpaCourseRow: Identifiable {
    var id: String { subjectName }
    var subjectName: String
    var credits: String
    var examScore: String
    var countsToGpa: String
    var scoreStatus: String

    init(
        subjectName: String,
        credits: String,
        examScore: String,
        countsToGpa: String = "是",
        scoreStatus: String = "正常"
    ) {
        self.subjectName = subjectName
        self.credits = credits
        self.examScore = examScore
        self.countsToGpa = countsToGpa
        self.scoreStatus = scoreStatus
    }
}

struct SubjectRegisterRow: Identifiable {
    var id: String
    var subjectName: String
    var credits: String
    var subjectCode: String
    var subjectType: String
    var assessmentMethod: String
    var regularScoreRatio: String
    var midtermScoreRatio: String
    var finalScoreRatio: String
    var remarks: String
    var teachingUnit: String
    var classHours: String

    init(
        id: String = "",
        subjectName: String = "",
        credits: String = "",
        subjectCode: String = "",
        subjectType: String = "",
        assessmentMethod: String = "",
        regularScoreRatio: String = "",
        midtermScoreRatio: String = "",
        finalScoreRatio: String = "",
        remarks: String = "",
        teachingUnit: String = "",
        classHours: String = ""
    ) {
        self.id = id
        self.subjectName = subjectName
        self.credits = credits
        self.subjectCode = subjectCode
        self.subjectType = subjectType
        self.assessmentMethod = assessmentMethod
        self.regularScoreRatio = regularScoreRatio
        self.midtermScoreRatio = midtermScoreRatio
        self.finalScoreRatio = finalScoreRatio
        self.remarks = remarks
        self.teachingUnit = teachingUnit
        self.classHours = classHours
    }

    func toGpaCourseRow() -> GpaCourseRow {
        GpaCourseRow(subjectName: subjectName.trimmingCharacters(in: .whitespaces), credits: credits.trimmingCharacters(in: .whitespaces), examScore: "")
    }
}

struct SubjectRegisterPanel {
    var semester: String
    var school: String
    var major: String
    var schoolyear: Int
    var needProfile: Bool
    var done: Bool
    var locked: Bool
    var classTeacherBound: Bool
    var courses: [SubjectRegisterRow]
}

struct GpaTermRow {
    let semester: String
    let termGpaDisplay: String
    let termCredits: Double
    let cumulativeGpaDisplay: String
    let cumulativeCredits: Double
    let entryMode: String
}

struct GpaPanelData {
    var semester: String
    var locked: Bool
    var classTeacherBound: Bool
    var ruleId: Int
    var needsBaseline: Bool
    var expectedBaselineSemester: String?
    var baselineGpa: String
    var baselineCredits: String
    var courses: [GpaCourseRow]
    var coursesBySemester: [String: [GpaCourseRow]]
    var termGpaDisplay: String
    var cumulativeGpaDisplay: String
    var cumulativeCredits: Double
    var terms: [GpaTermRow]
    var schoolyear: Int
    var schoolyearLocked: Bool
    var needsProfileSetup: Bool
    var needsEnrollYear: Bool
    var needsRule: Bool
    var baselineSet: Bool
}

struct GpaPlanCourse {
    var semester: String
    var subjectName: String
    var credits: Double
    var targetScore: String
    var locked: Bool
    var creditText: String
    func resolvedCredits() -> Double { Double(creditText) ?? credits }
}

struct GpaPlanData {
    var targetSemester: String
    var targetGpa: Double
    var projectedGpa: Double?
    var achievable: Bool
    var courses: [GpaPlanCourse]
    var baselineGpa: String
    var baselineCredits: String
    var showBaseline: Bool
    var expectedBaselineSemester: String
    var ruleId: Int
}

struct GpaTermStats {
    let gpa: Double
    let credits: Double
}

struct PastHistoryStats {
    let gpa: Double
    let credits: Double
    let src: String
}

struct ReverseBand {
    let min: Int
    let text: String
    let point: Double
}

struct ReverseCalc {
    let cum: Bool
    let isNow: Bool
    let target: Double
    let need: Double
    let restC: Double
    let pending: Double
    let total: Double
    let histC: Double
    let histG: Double
    let histSrc: String
    let termC: Double
    let fixedC: Double
    let fixedP: Double
    let fixedN: Int
    let futureC: Double
    let reachable: Bool
    let maxGpa: Double
    let band: ReverseBand?
}

@MainActor
final class AcademicSession: ObservableObject {
    @Published var school = ""
    @Published var major = ""
    @Published var schoolyear = 0
    @Published var educationSystem = ""
    @Published var semester = ""
    @Published var revision = 0

    func apply(
        school: String? = nil,
        major: String? = nil,
        schoolyear: Int? = nil,
        educationSystem: String? = nil,
        semester: String? = nil
    ) {
        var changed = false
        if let school, !school.isEmpty, self.school != school { self.school = school; changed = true }
        if let major, !major.isEmpty, self.major != major { self.major = major; changed = true }
        if let schoolyear, schoolyear > 0, self.schoolyear != schoolyear { self.schoolyear = schoolyear; changed = true }
        if let educationSystem {
            let normalized = AcademicCalc.normalizeEducationSystem(educationSystem)
            if !normalized.isEmpty, self.educationSystem != normalized {
                self.educationSystem = normalized
                changed = true
            }
        }
        if let semester, !semester.isEmpty, self.semester != semester { self.semester = semester; changed = true }
        if changed { revision += 1 }
    }

    func applyFromRegister(_ panel: SubjectRegisterPanel) {
        apply(
            school: school.isEmpty ? panel.school : nil,
            major: major.isEmpty ? panel.major : nil,
            schoolyear: AcademicCalc.hasProfileEnrollmentYear(schoolyear) ? nil : panel.schoolyear,
            semester: semester.isEmpty ? panel.semester : nil
        )
    }

    var headerLabel: String {
        let schoolPart = school.isEmpty ? "未填学校" : school
        let majorPart = major.isEmpty ? "未填专业" : major
        let termPart = AcademicCalc.displayGpaSemesterName(semester)
        let termShown = termPart.isEmpty ? "未选学期" : termPart
        let systemPart = educationSystem.isEmpty ? "" : " · \(educationSystem)"
        return "当前：\(schoolPart)｜\(majorPart)｜\(termShown)\(systemPart)"
    }
}
