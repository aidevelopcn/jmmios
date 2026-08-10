import SwiftUI

// MARK: - GPA 计算器
struct GpaCalculatorView: View {
    let onBack: () -> Void
    
    @State private var courses: [GpaCourseInput] = []
    @State private var inputMode: GpaInputMode = .percentage
    @State private var algorithmKey = "standard_weighted"
    @State private var addCountText = ""
    @State private var hasCalculated = false
    @State private var calculatedGPA: Double = 0
    @State private var allResults: [String: Double] = [:]
    @State private var showAlgoSheet = false
    @State private var showRulesSheet = false
    @State private var showClearAlert = false
    @State private var showGradePicker = false
    @State private var showFivePointPicker = false
    @State private var pickingCourseIndex: Int? = nil
    @State private var ruleTab: GpaInputMode = .percentage
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // 头部区域
                gpaHeader
                
                Spacer().frame(height: 10)
                
                // 课程输入区
                courseInputCard
                
                Spacer().frame(height: 14)
                
                infoCard(title: "为什么我要算 GPA？", icon: "graduationcap",
                          content: "留学申请（特别是美加高校）的第一门槛，也是国内评优、推免保研资格的核心指标。一份高 GPA 是学习能力的直接证明。")
                
                infoCard(title: "常见算法区别", icon: "lightbulb",
                          content: "WES 算法：留学党首选；标准4.0：适合自我评估底线；浙大/北大：国内高校保研通用参考。")
                
                Spacer().frame(height: 16)
            }
        }
        .background(AppColors.background)
        .sheet(isPresented: $showAlgoSheet) { algorithmPickerSheet }
        .sheet(isPresented: $showRulesSheet) { rulesSheet }
        .alert("提示", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("确定") { resetCourses() }
        } message: { Text("确定要清空所有数据吗？") }
        .onAppear { if courses.isEmpty { resetCourses() } }
    }
    
    // MARK: - 头部区域
    private var gpaHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 30)
                }
                Spacer()
                Text("绩满满GPA计算器")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { showRulesSheet = true }) {
                    Text("计算规则").font(.system(size: 13)).foregroundColor(.white.opacity(0.9))
                }
            }
            
            Spacer().frame(height: 8)
            
            Button(action: { showAlgoSheet = true }) {
                HStack(spacing: 4) {
                    Text(hasCalculated ? "当前算法：\(currentAlgorithm.name)" : "选择算法：\(currentAlgorithm.name)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            
            Spacer().frame(height: 8)
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hasCalculated ? String(format: "%.2f", calculatedGPA) : "--")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundColor(.white)
                Text("/ \(currentAlgorithm.scale)")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.88))
            }
            
            if hasCalculated && !otherAlgorithms.isEmpty {
                Spacer().frame(height: 12)
                Text("【其他算法】").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.78))
                Spacer().frame(height: 6)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(otherAlgorithms, id: \.key) { algo in
                        let result = allResults[algo.key] ?? 0
                        Button(action: { selectAlgorithm(algo.key) }) {
                            VStack(spacing: 4) {
                                Text(algo.shortName).font(.system(size: 11)).foregroundColor(.white.opacity(0.9))
                                Text(String(format: "%.2f", result)).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                Text("/\(algo.scale)").font(.system(size: 10)).foregroundColor(.white.opacity(0.78))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.2)))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.primary)
    }
    
    // MARK: - 课程输入卡片
    private var courseInputCard: some View {
        VStack(spacing: 12) {
            // 模式切换
            modeSwitcher
            
            // 表头
            HStack(spacing: 0) {
                Text("课程名称").font(.system(size: 12)).foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .center)
                Text("成绩").font(.system(size: 12)).foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .center)
                Text("学分").font(.system(size: 12)).foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .center)
                Color.clear.frame(width: 28)
            }
            
            Spacer().frame(height: 4)
            
            // 课程行
            ForEach(0..<courses.count, id: \.self) { idx in
                courseRow(course: $courses[idx])
            }
            
            // 添加和清空
            addRow
            
            // 计算按钮
            Button(action: calculate) {
                Text("开始计算")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppColors.primary))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .padding(.horizontal, 12)
    }
    
    // MARK: - 模式切换
    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach([GpaInputMode.percentage, GpaInputMode.fivePoint, GpaInputMode.grade], id: \.self) { mode in
                let active = mode == inputMode
                Button(action: { switchMode(mode) }) {
                    Text(mode.label)
                        .font(.system(size: 14, weight: active ? .bold : .regular))
                        .foregroundColor(active ? .white : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if active { AppColors.primary } else { Color.clear }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        )
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "F6FAF9")))
    }
    
    // MARK: - 课程行
    private func courseRow(course: Binding<GpaCourseInput>) -> some View {
        HStack(spacing: 6) {
            TextField("课程 \(course.wrappedValue.id)", text: course.name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
            
            if inputMode == .percentage {
                TextField("--", text: course.score)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: { pickingCourseIndex = courses.firstIndex(where: { $0.id == course.wrappedValue.id }) ?? nil;
                             if inputMode == .grade { showGradePicker = true } else { showFivePointPicker = true } }) {
                    Text(course.wrappedValue.grade.isEmpty ? "--" : course.wrappedValue.grade)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .overlay(Rectangle().stroke(Color(hex: "D8DEE4"), lineWidth: 1))
                        .cornerRadius(6)
                }
            }
            
            TextField("--", text: course.credits)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12))
                .keyboardType(.decimalPad)
                .frame(maxWidth: .infinity)
            
            Button(action: { courses.removeAll(where: { $0.id == course.wrappedValue.id }); hasCalculated = false }) {
                Image(systemName: "multiply")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - 添加行
    private var addRow: some View {
        HStack(spacing: 6) {
            Text("添加").font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
            TextField("节课", text: $addCountText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12))
                .keyboardType(.numberPad)
                .frame(width: 70)
            Button(action: addCourses) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.primary)
            }
            Spacer()
            Button(action: { showClearAlert = true }) {
                Text("清空")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "F5F5F5")))
            }
        }
    }
    
    // MARK: - 信息卡片
    private func infoCard(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.primary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(AppColors.primary.opacity(0.1)))
                Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: "222222"))
            }
            Text(content).font(.system(size: 13)).foregroundColor(.secondary).lineSpacing(4)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .padding(.horizontal, 12)
    }
    
    // MARK: - 算法选择弹窗
    private var algorithmPickerSheet: some View {
        NavigationView {
            Form {
                Section("【推荐算法】") {
                    algoRow(key: "standard_weighted", name: "标准加权算法", shortName: "标准加权")
                }
                Section("【其他常见算法】") {
                    algoRow(key: "standard_4_0", name: "标准4.0算法", shortName: "标准4.0")
                    algoRow(key: "wes", name: "WES算法", shortName: "WES")
                    algoRow(key: "improved_4_0_1", name: "改进4.0算法(1)", shortName: "改进4.0(1)")
                    algoRow(key: "improved_4_0_2", name: "改进4.0算法(2)", shortName: "改进4.0(2)")
                    algoRow(key: "pku_4_0", name: "北大4.0算法", shortName: "北大4.0")
                    algoRow(key: "canada_4_3", name: "加拿大4.3算法", shortName: "加拿大")
                    algoRow(key: "ustc_4_3", name: "中科大4.3算法", shortName: "中科大")
                    algoRow(key: "sjtu_4_3", name: "上海交大4.3算法", shortName: "上交大")
                }
            }
            .navigationTitle("切换算法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showAlgoSheet = false } } }
        }
    }
    
    private func algoRow(key: String, name: String, shortName: String) -> some View {
        let active = key == algorithmKey
        let result = allResults[key]
        return Button(action: { algorithmKey = key; if hasCalculated { calculatedGPA = result ?? 0 }; showAlgoSheet = false }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 14, weight: active ? .bold : .regular))
                        .foregroundColor(active ? AppColors.primaryDark : .primary)
                    if let r = result {
                        Text(String(format: "%.2f / %.1f", r, algorithm(for: key).scale))
                            .font(.system(size: 13)).foregroundColor(AppColors.primary)
                    }
                }
                Spacer()
                if active { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundColor(AppColors.primary) }
            }
            .padding(.vertical, 8)
            .listRowBackground(active ? AppColors.primary.opacity(0.07) : Color.clear)
        }
    }
    
    // MARK: - 规则弹窗
    private var rulesSheet: some View {
        NavigationView {
            Picker("", selection: $ruleTab) {
                Text("百分制").tag(GpaInputMode.percentage)
                Text("等级制").tag(GpaInputMode.grade)
                Text("五分制").tag(GpaInputMode.fivePoint)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Group {
                switch ruleTab {
                case .percentage:
                    rulesText("标准4.0：90-100→4.0，80-89→3.0，70-79→2.0，60-69→1.0\n\nWES：85-100→4.0，75-84→3.0，60-74→2.0\n\n北大4.0、加拿大4.3、中科大4.3、上交大4.3 采用分段换算。")
                case .grade:
                    rulesText("A+/A=4.0, A-=3.7, B+=3.3, B=3.0, B-=2.7, C+=2.3, C=2.0, C-=1.7, D=1.0, F=0")
                case .fivePoint:
                    rulesText("5.0(优)->95, 4.0(良)->85, 3.0(中)->75, 2.0(及格)->65, 0.0(不及格)->0-59")
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .navigationTitle("计算规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showRulesSheet = false } } }
    }
    
    private func rulesText(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundColor(.secondary)
    }
    
    // MARK: - 数据和方法
    private var currentAlgorithm: (name: String, shortName: String, scale: Double) {
        algorithm(for: algorithmKey)
    }
    
    private var otherAlgorithms: [(key: String, name: String, shortName: String, scale: Double)] {
        currentAlgorithms.filter { $0.key != algorithmKey }
    }
    
    private var currentAlgorithms: [(key: String, name: String, shortName: String, scale: Double)] {
        switch inputMode {
        case .percentage:
            return [
                ("standard_weighted","标准加权算法","标准加权",4.0), ("standard_4_0","标准4.0算法","标准4.0",4.0),
                ("wes","WES算法","WES",4.0), ("improved_4_0_1","改进4.0算法(1)","改进4.0(1)",4.0),
                ("improved_4_0_2","改进4.0算法(2)","改进4.0(2)",4.0), ("pku_4_0","北大4.0算法","北大4.0",4.0),
                ("canada_4_3","加拿大4.3算法","加拿大",4.3), ("ustc_4_3","中科大4.3算法","中科大",4.3),
                ("sjtu_4_3","上海交大4.3算法","上交大",4.3)
            ]
        case .fivePoint:
            return [("standard_weighted","标准加权算法","标准加权",4.0), ("five_point","五分制算法","五分制",4.0)]
        case .grade:
            return [("standard_weighted","标准加权算法","标准加权",4.0), ("grade","等级制算法","等级制",4.0)]
        }
    }
    
    private func algorithm(for key: String) -> (name: String, shortName: String, scale: Double) {
        if let found = currentAlgorithms.first(where: { $0.key == key }) {
            return (name: found.name, shortName: found.shortName, scale: found.scale)
        }
        return (name: "标准加权算法", shortName: "标准加权", scale: 4.0)
    }
    
    private func switchMode(_ mode: GpaInputMode) {
        guard inputMode != mode else { return }
        inputMode = mode
        for i in courses.indices { courses[i].score = ""; courses[i].grade = "" }
        hasCalculated = false
        algorithmKey = currentAlgorithms.first!.key
    }
    
    private func selectAlgorithm(_ key: String) {
        algorithmKey = key
        calculatedGPA = allResults[key] ?? 0
    }
    
    private func resetCourses() {
        courses = []
        for i in 0..<3 { courses.append(GpaCourseInput(id: i + 1)) }
        hasCalculated = false
        calculatedGPA = 0
        allResults = [:]
    }
    
    private func addCourses() {
        let requested = Int(addCountText) ?? 1
        let count = min(max(requested, 1), 10)
        for _ in 0..<count { courses.append(GpaCourseInput(id: courses.count + 1)) }
        addCountText = ""
        hasCalculated = false
    }
    
    private func calculate() {
        let valid = courses.filter {
            let hasScore = inputMode == .percentage ? !$0.score.isEmpty : !$0.grade.isEmpty
            let credits = Double($0.credits) ?? 0
            return hasScore && credits > 0
        }
        if valid.isEmpty { return }
        
        var results: [String: Double] = [:]
        for algo in currentAlgorithms {
            results[algo.key] = computeGPA(courses: valid, algoKey: algo.key)
        }
        allResults = results
        calculatedGPA = results[algorithmKey] ?? 0
        hasCalculated = true
    }
    
    private func computeGPA(courses: [GpaCourseInput], algoKey: String) -> Double {
        if algoKey == "standard_weighted" { return computeStandardWeighted(courses: courses) }
        var totalPoints = 0.0
        var totalCredits = 0.0
        for c in courses {
            guard let cred = Double(c.credits), cred > 0 else { continue }
            var points: Double = 0
            switch inputMode {
            case .percentage:
                guard let score = Double(c.score) else { continue }
                points = getPointsFromPercentage(score: min(score, 100), algo: algoKey)
            case .fivePoint:
                points = getPointsFromFivePoint(value: c.grade)
            case .grade:
                points = getPointsFromGrade(grade: c.grade)
            }
            totalPoints += points * cred
            totalCredits += cred
        }
        return totalCredits > 0 ? totalPoints / totalCredits : 0
    }
    
    private func computeStandardWeighted(courses: [GpaCourseInput]) -> Double {
        var totalScore = 0.0
        var totalCredits = 0.0
        for c in courses {
            guard let cred = Double(c.credits), cred > 0 else { continue }
            var score = 0.0
            switch inputMode {
            case .percentage: score = Double(c.score) ?? 0
            case .fivePoint: score = fivePointMap[c.grade] ?? 0
            case .grade: score = gradeMap[c.grade] ?? 0
            }
            totalScore += score * cred
            totalCredits += cred
        }
        return totalCredits > 0 ? (totalScore / totalCredits) * 0.04 : 0
    }
    
    private func getPointsFromPercentage(score: Double, algo: String) -> Double {
        if score < 60 { return 0 }
        switch algo {
        case "standard_4_0": return score >= 90 ? 4 : score >= 80 ? 3 : score >= 70 ? 2 : 1
        case "wes": return score >= 85 ? 4 : score >= 75 ? 3 : score >= 60 ? 2 : 0
        case "pku_4_0": return pkuMap(score)
        case "canada_4_3": return canadaMap(score)
        default: return standardMap(score)
        }
    }
    
    // MARK: - 映射表
    private func standardMap(_ s: Double) -> Double {
        s >= 90 ? 4 : s >= 85 ? 4 : s >= 82 ? 3 : s >= 78 ? 3 : s >= 60 ? 2 : 0
    }
    private func pkuMap(_ s: Double) -> Double {
        s >= 90 ? 4 : s >= 85 ? 3.7 : s >= 82 ? 3.3 : s >= 78 ? 3 : s >= 75 ? 2.7 : s >= 72 ? 2.3 : s >= 68 ? 2 : s >= 64 ? 1.5 : s >= 60 ? 1 : 0
    }
    private func canadaMap(_ s: Double) -> Double {
        s >= 90 ? 4.3 : s >= 85 ? 4 : s >= 80 ? 3.7 : s >= 77 ? 3.3 : s >= 73 ? 3 : s >= 70 ? 2.7 : s >= 67 ? 2.3 : s >= 63 ? 2 : s >= 60 ? 1.7 : 0
    }
    private let fivePointMap: [String: Double] = ["5.0":95,"4.0":85,"3.0":75,"2.0":65,"0.0":0]
    private let gradeMap: [String: Double] = ["A+":95,"A":90,"A-":85,"B+":82,"B":78,"B-":75,"C+":72,"C":68,"C-":65,"D":60,"F":0]
    private func getPointsFromFivePoint(value: String) -> Double { ["5.0":4,"4.0":3,"3.0":2,"2.0":1,"0.0":0][value] ?? 0 }
    private func getPointsFromGrade(grade: String) -> Double { ["A+":4,"A":4,"A-":3.7,"B+":3.3,"B":3,"B-":2.7,"C+":2.3,"C":2,"C-":1.7,"D":1,"F":0][grade] ?? 0 }
}

// MARK: - 数据模型
struct GpaCourseInput: Identifiable {
    let id: Int
    var name = ""
    var score = ""
    var credits = ""
    var grade = ""
}

enum GpaInputMode {
    case percentage, fivePoint, grade
    
    var label: String {
        switch self {
        case .percentage: return "百分制"
        case .fivePoint: return "五分制"
        case .grade: return "等级制"
        }
    }
}
