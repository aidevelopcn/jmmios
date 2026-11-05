import SwiftUI

// MARK: - 学生信息（基本信息）
struct StudentInfoView: View {
    let onBack: () -> Void
    let onOpenCertification: () -> Void
    
    @EnvironmentObject private var session: AcademicSession
    @StateObject private var apiService = ApiService.shared
    @State private var userProfile: UserProfile?
    @State private var nickname = ""
    @State private var school = ""
    @State private var major = ""
    @State private var schoolYear = ""
    @State private var invitationCode = ""
    @State private var educationSystem = ""
    @State private var invitationValid = false
    @State private var certified = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var showYearPicker = false
    @State private var showYearLockConfirm = false
    @State private var pendingLockYear = ""
    @State private var schoolyearLocked = false
    @State private var showSystemPicker = false
    @State private var isEditing = false
    @State private var saving = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var imageUploading = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 导航栏
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                Text("基本信息")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color(hex: "2D3748"))
                
                Spacer()
                
                if !isEditing {
                    Button("编辑") {
                        isEditing = true
                    }
                    .foregroundColor(AppColors.primary)
                    .frame(width: 44, height: 44)
                } else {
                    Button(saving ? "保存中..." : "保存") {
                        saveProfile()
                    }
                    .foregroundColor(AppColors.primary)
                    .disabled(saving)
                    .frame(width: 60, height: 44)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(Color.white)
            
            Divider().background(Color(hex: "E8ECF0"))
            
            ScrollView {
                VStack(spacing: 0) {
                    // 头像
                    avatarSection
                        .padding(.top, 20)
                    
                    // 信息表单
                    infoForm
                        .padding(.top, 20)
                    
                    // 学生认证入口
                    certificationSection
                        .padding(.top, 20)
                    
                    Spacer().frame(height: 40)
                }
            }
            .background(Color(hex: "F5F7FA"))
        }
        .navigationBarHidden(true)
        .onAppear { loadProfile() }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
        .alert("确认入学年份", isPresented: $showYearLockConfirm) {
            Button("取消", role: .cancel) { pendingLockYear = "" }
            Button("确认保存") { confirmLockSchoolYear() }
        } message: {
            Text("您的入学年份为 \(pendingLockYear)，保存后该数据不可修改！")
        }
        .sheet(isPresented: $showImagePicker) {
            StudentImagePicker(image: $selectedImage, sourceType: .photoLibrary)
        }
        .sheet(isPresented: $showYearPicker) { yearPickerSheet }
        .sheet(isPresented: $showSystemPicker) { systemPickerSheet }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                uploadAvatar(image: image)
            }
        }
    }
    
    // MARK: - 头像区域
    private var avatarSection: some View {
        VStack {
            if imageUploading {
                ProgressView()
                    .scaleEffect(1.2)
                    .frame(width: 80, height: 80)
            } else if let profile = userProfile, !profile.avatarUrl.isEmpty {
                AsyncImage(url: URL(string: profile.avatarUrl.replacingOccurrences(of: "//{2,}", with: "/", options: .regularExpression))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(Text("头像").foregroundColor(.gray))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                showImagePicker = true
            }
        }
        .overlay(alignment: .bottom) {
            if isEditing {
                Text("更换头像")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .offset(y: 8)
            }
        }
    }
    
    // MARK: - 信息表单
    private var infoForm: some View {
        VStack(spacing: 0) {
            infoRow(title: "昵称", text: $nickname, editable: isEditing)
            Divider().padding(.leading, 16)
            infoRow(title: "学校", text: $school, editable: isEditing)
            Divider().padding(.leading, 16)
            infoRow(title: "专业", text: $major, editable: isEditing)
            Divider().padding(.leading, 16)
            Button(action: openYearPicker) {
                    HStack {
                        Text("入学年份")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "666666"))
                            .frame(width: 60, alignment: .leading)
                        Spacer()
                        Text(schoolYearDisplay)
                            .font(.system(size: 14))
                            .foregroundColor(schoolYear.isEmpty ? Color(hex: "999999") : AppColors.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "CCCCCC"))
                            .padding(.leading, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            Group {
                Divider().padding(.leading, 16)
                systemRow
                Divider().padding(.leading, 16)
                inviteRow
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
    
    private func infoRow(title: String, text: Binding<String>, editable: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "666666"))
                .frame(width: 60, alignment: .leading)
            
            Spacer()
            
            if editable {
                TextField("请输入\(title)", text: text)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(text.wrappedValue.isEmpty ? "未设置" : text.wrappedValue)
                    .font(.system(size: 14))
                    .foregroundColor(text.wrappedValue.isEmpty ? Color(hex: "999999") : AppColors.textPrimary)
            }
            
            if !editable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "CCCCCC"))
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var inviteRow: some View {
        infoRow(title: "邀请码", text: $invitationCode, editable: isEditing)
    }

    private var systemRow: some View {
        Button(action: { showSystemPicker = true }) {
            HStack {
                Text("学制")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "666666"))
                    .frame(width: 60, alignment: .leading)
                Spacer()
                Text(educationSystem.isEmpty ? "未填写" : educationSystem)
                    .font(.system(size: 14))
                    .foregroundColor(educationSystem.isEmpty ? Color(hex: "999999") : AppColors.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "CCCCCC"))
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 学生认证入口
    private var certificationSection: some View {
        let enabled = invitationValid || certified
        return Button(action: {
            if enabled {
                onOpenCertification()
            } else {
                toastMessage = "请先填写有效邀请码，认证后才会同步到绩满满教育后台"
                showToast = true
            }
        }) {
            Text(certified ? "已认证学员" : "认证学员")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(enabled ? .white : Color(hex: "9CA3AF"))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 24).fill(enabled ? Color(hex: "00D7CD") : Color(hex: "D1D5DB")))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
    
    private var schoolYearDisplay: String {
        if schoolYear.isEmpty { return "未填写" }
        return schoolyearLocked ? "\(schoolYear)年 · 已锁定" : "\(schoolYear)年"
    }

    private func openYearPicker() {
        if schoolyearLocked {
            toastMessage = "入学年份已锁定，不可修改"
            showToast = true
            return
        }
        showYearPicker = true
    }

    private var yearPickerSheet: some View {
        NavigationView {
            List(AcademicCalc.enrollmentYearOptions(), id: \.self) { year in
                Button(action: { selectEnrollmentYear(year) }) {
                    HStack {
                        Text("\(year)年")
                        Spacer()
                        if schoolYear == year {
                            Image(systemName: "checkmark").foregroundColor(AppColors.primary)
                        }
                    }
                }
            }
            .navigationTitle("选择入学年份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showYearPicker = false }
                }
            }
        }
    }

    private func selectEnrollmentYear(_ year: String) {
        let normalized = AcademicCalc.normalizeEnrollmentYear(year)
        guard !normalized.isEmpty else {
            toastMessage = "请选择有效入学年份"
            showToast = true
            return
        }
        if !schoolyearLocked && schoolYear.isEmpty {
            pendingLockYear = normalized
            showYearPicker = false
            showYearLockConfirm = true
            return
        }
        Task { await saveSchoolYear(normalized, lock: false) }
    }

    private func confirmLockSchoolYear() {
        let year = AcademicCalc.normalizeEnrollmentYear(pendingLockYear)
        guard !year.isEmpty else { return }
        Task { await saveSchoolYear(year, lock: true) }
    }

    private func saveSchoolYear(_ year: String, lock: Bool) async {
        var params = ["schoolyear": year]
        if lock { params["lock_schoolyear"] = "1" }
        let ok = await apiService.updateUserInfo(params: params)
        await MainActor.run {
            if ok {
                schoolYear = year
                if lock { schoolyearLocked = true }
                session.apply(schoolyear: Int(year) ?? AcademicCalc.defaultEnrollmentYear())
                showYearPicker = false
                showYearLockConfirm = false
                pendingLockYear = ""
                toastMessage = lock ? "入学年份已锁定" : "保存成功"
            } else {
                toastMessage = "保存失败"
            }
            showToast = true
        }
    }

    private var systemPickerSheet: some View {
        NavigationView {
            List(educationSystemOptions, id: \.self) { item in
                Button(action: {
                    educationSystem = item
                    showSystemPicker = false
                    Task {
                        _ = await apiService.updateUserInfo(params: ["education_system": item])
                        await MainActor.run { session.apply(educationSystem: item) }
                    }
                }) {
                    HStack {
                        Text(item)
                        Spacer()
                        if educationSystem == item {
                            Image(systemName: "checkmark").foregroundColor(AppColors.primary)
                        }
                    }
                }
            }
            .navigationTitle("选择学制")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showSystemPicker = false }
                }
            }
        }
    }

    // MARK: - 方法
    private func loadProfile() {
        Task {
            let data = await apiService.fetchUserInfoData()
            let profile = await apiService.fetchUserProfile()
            await MainActor.run {
                self.userProfile = profile
                self.nickname = profile?.nickname ?? ""
                let schoolValue = (profile?.school ?? "").isEmpty ? session.school : (profile?.school ?? "")
                let majorValue = (profile?.major ?? "").isEmpty ? session.major : (profile?.major ?? "")
                self.school = schoolValue
                self.major = majorValue
                let year = profile?.schoolYear ?? ""
                self.schoolYear = year.isEmpty && session.schoolyear > 0 ? String(session.schoolyear) : year
                self.invitationCode = profile?.invitationCode ?? ""
                if let data {
                    let edu = AcademicCalc.normalizeEducationSystem(AcademicApi.stringValue(data["education_system"]))
                    educationSystem = edu.isEmpty ? session.educationSystem : edu
                    let teacherId = data["class_teacher_id"] as? Int ?? 0
                    invitationValid = AcademicApi.stringValue(data["invitation_valid"]) == "1"
                        || teacherId > 0
                        || (data["invitation_valid"] as? Bool == true)
                    schoolyearLocked = AcademicApi.boolValue(data["schoolyear_locked"])
                    let parentName = AcademicApi.stringValue(data["parent_name"])
                    let parentPhone = AcademicApi.stringValue(data["parent_phone"])
                    let source = AcademicApi.stringValue(data["gaokao_source"])
                    certified = !parentName.isEmpty && !parentPhone.isEmpty && !source.isEmpty
                }
                session.apply(
                    school: schoolValue,
                    major: majorValue,
                    schoolyear: Int(schoolYear) ?? session.schoolyear,
                    educationSystem: educationSystem
                )
            }
        }
    }
    
    private func saveProfile() {
        saving = true
        Task {
            var ok = await apiService.updateProfileInfo(
                nickname: nickname,
                school: school,
                major: major
            )
            if ok && !invitationCode.isEmpty {
                let invite = await apiService.updateUserInfoDetailed(params: ["invitation_code": invitationCode])
                ok = invite.ok
                if !invite.ok {
                    await MainActor.run {
                        saving = false
                        invitationValid = false
                        toastMessage = invite.message
                        showToast = true
                    }
                    return
                }
            }
            if ok && !schoolYear.isEmpty && !schoolyearLocked {
                ok = await apiService.updateUserInfo(params: ["schoolyear": schoolYear])
            }
            if ok && !educationSystem.isEmpty {
                ok = await apiService.updateUserInfo(params: ["education_system": educationSystem])
            }
            await MainActor.run {
                saving = false
                if ok {
                    isEditing = false
                    session.apply(school: school, major: major, schoolyear: Int(schoolYear) ?? 0, educationSystem: educationSystem)
                    loadProfile()
                } else {
                    toastMessage = "保存失败"
                    showToast = true
                }
            }
        }
    }
    
    private func uploadAvatar(image: UIImage) {
        imageUploading = true
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            imageUploading = false
            return
        }
        
        Task {
            let filePath = await apiService.uploadFile(
                imageData: imageData,
                fileName: "avatar_\(Int(Date().timeIntervalSince1970)).jpg",
                mimeType: "image/jpeg"
            )
            
            if let filePath = filePath {
                let normalizedPath = filePath.replacingOccurrences(of: "//{2,}", with: "/", options: .regularExpression)
                let ok = await apiService.updateUserInfo(params: ["avatarUrl": normalizedPath])
                await MainActor.run {
                    imageUploading = false
                    if ok {
                        loadProfile()
                    }
                }
            } else {
                await MainActor.run {
                    imageUploading = false
                }
            }
        }
    }
}

// MARK: - 图片选择器
struct StudentImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var image: Binding<UIImage?>
        
        init(image: Binding<UIImage?>) {
            self.image = image
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let selectedImage = info[.originalImage] as? UIImage {
                image.wrappedValue = selectedImage
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

//// #Preview {
//    StudentInfoView(onBack: {}, onOpenCertification: {})
//}
