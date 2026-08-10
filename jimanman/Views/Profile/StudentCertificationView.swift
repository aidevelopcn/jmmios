import SwiftUI

// MARK: - 学员认证（对齐 Android StudentCertificationScreen）
struct StudentCertificationView: View {
    let onBack: () -> Void

    @StateObject private var apiService = ApiService.shared
    @State private var parentName = ""
    @State private var parentPhone = ""
    @State private var examLocation = ""
    @State private var totalScore = ""
    @State private var mathScore = ""
    @State private var englishScore = ""
    @State private var englishLevel = ""
    @State private var englishLevelScore = ""
    @State private var strongSubjects = ""
    @State private var weakSubjects = ""
    @State private var saving = false
    @State private var showLevelPicker = false
    @State private var toastMessage = ""
    @State private var showToast = false

    private let levelOptions = ["四级", "六级", "无"]

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(spacing: 0) {
                    formCard
                    submitButton
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "F5F5F5"))
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showLevelPicker) { levelPickerSheet }
        .alert("提示", isPresented: $showToast) {
            Button("确定") { if toastMessage.contains("成功") { onBack() } }
        } message: {
            Text(toastMessage)
        }
    }

    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("认证学员")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color(hex: "2D3748"))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.white)
        .overlay(Divider(), alignment: .bottom)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            parentInfoSection
            gaokaoInfoSection
            englishInfoSection
            subjectInfoSection
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var parentInfoSection: some View {
        Group {
            sectionTitle("家长信息", isFirst: true)
            certField(label: "家长姓名", text: $parentName, placeholder: "请输入家长姓名")
            certField(label: "家长联系电话", text: $parentPhone, placeholder: "请输入家长联系电话", digitsOnly: true, maxLength: 11)
        }
    }

    private var gaokaoInfoSection: some View {
        Group {
            sectionTitle("高考信息")
            certField(label: "高考生源地", text: $examLocation, placeholder: "请输入省份和城市，如：北京市")
            certField(label: "高考总成绩", text: $totalScore, placeholder: "请输入高考总成绩", digitsOnly: true)
            HStack(spacing: 12) {
                certField(label: "数学成绩", text: $mathScore, placeholder: "数学成绩", digitsOnly: true)
                certField(label: "英语成绩", text: $englishScore, placeholder: "英语成绩", digitsOnly: true)
            }
        }
    }

    private var englishInfoSection: some View {
        Group {
            sectionTitle("英语能力")
            pickerField(label: "英语等级", value: englishLevel.isEmpty ? "请选择英语等级" : englishLevel) {
                showLevelPicker = true
            }
            certField(label: "英语等级考试成绩", text: $englishLevelScore, placeholder: "请输入成绩，无则填无")
        }
    }

    private var subjectInfoSection: some View {
        Group {
            sectionTitle("学科情况")
            certField(label: "优势科目", text: $strongSubjects, placeholder: "请输入优势科目，如：数学、物理")
            certField(label: "弱势科目", text: $weakSubjects, placeholder: "请输入弱势科目，如：英语、化学")
        }
    }

    private var submitButton: some View {
        Button(action: submitCertification) {
            Text(saving ? "提交中..." : "提交认证")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 24).fill(saving ? AppColors.primary.opacity(0.5) : AppColors.primary))
        }
        .disabled(saving)
    }

    private var levelPickerSheet: some View {
        NavigationView {
            List(levelOptions, id: \.self) { level in
                Button(action: {
                    englishLevel = level
                    showLevelPicker = false
                }) {
                    HStack {
                        Text(level)
                        Spacer()
                        if englishLevel == level {
                            Image(systemName: "checkmark").foregroundColor(AppColors.primary)
                        }
                    }
                }
            }
            .navigationTitle("选择英语等级")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showLevelPicker = false }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, isFirst: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(Color(hex: "333333"))
            .padding(.top, isFirst ? 0 : 18)
            .padding(.bottom, 10)
    }

    private func certField(label: String, text: Binding<String>, placeholder: String,
                           digitsOnly: Bool = false, maxLength: Int = 50) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "666666"))
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .keyboardType(digitsOnly ? .numberPad : .default)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(hex: "F9FAFB"))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.bottom, 15)
    }

    private func pickerField(label: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "666666"))
            Button(action: action) {
                HStack {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundColor(value.hasPrefix("请") ? Color(hex: "999999") : AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "CCCCCC"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(hex: "F9FAFB"))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 15)
    }

    private func submitCertification() {
        guard let token = apiService.token, !token.isEmpty else {
            toastMessage = "请先登录"
            showToast = true
            return
        }
        if parentName.trimmingCharacters(in: .whitespaces).isEmpty ||
            parentPhone.count != 11 ||
            examLocation.trimmingCharacters(in: .whitespaces).isEmpty ||
            totalScore.isEmpty || mathScore.isEmpty || englishScore.isEmpty ||
            englishLevel.isEmpty || englishLevelScore.isEmpty ||
            strongSubjects.trimmingCharacters(in: .whitespaces).isEmpty ||
            weakSubjects.trimmingCharacters(in: .whitespaces).isEmpty {
            toastMessage = "请完整填写信息"
            showToast = true
            return
        }

        saving = true
        Task {
            let ok = await apiService.updateUserInfo(params: [
                "parent_name": parentName.trimmingCharacters(in: .whitespaces),
                "parent_phone": parentPhone.trimmingCharacters(in: .whitespaces),
                "gaokao_source": examLocation.trimmingCharacters(in: .whitespaces),
                "gaokao_score": totalScore,
                "gaokao_math_score": mathScore,
                "gaokao_english_score": englishScore,
                "english_level": englishLevel,
                "english_score": englishLevelScore,
                "advantage_subjects": strongSubjects.trimmingCharacters(in: .whitespaces),
                "weak_subjects": weakSubjects.trimmingCharacters(in: .whitespaces)
            ])
            await MainActor.run {
                saving = false
                toastMessage = ok ? "认证提交成功" : "提交失败"
                showToast = true
            }
        }
    }
}
