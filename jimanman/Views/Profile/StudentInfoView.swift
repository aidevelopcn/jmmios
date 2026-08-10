import SwiftUI

// MARK: - 学生信息（基本信息）
struct StudentInfoView: View {
    let onBack: () -> Void
    let onOpenCertification: () -> Void
    
    @StateObject private var apiService = ApiService.shared
    @State private var userProfile: UserProfile?
    @State private var nickname = ""
    @State private var school = ""
    @State private var major = ""
    @State private var schoolYear = ""
    @State private var invitationCode = ""
    @State private var showYearPicker = false
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
        .sheet(isPresented: $showImagePicker) {
            StudentImagePicker(image: $selectedImage, sourceType: .photoLibrary)
        }
        .sheet(isPresented: $showYearPicker) { yearPickerSheet }
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
            if isEditing {
                infoRow(title: "入学年份", text: $schoolYear, editable: true)
            } else {
                Button(action: { showYearPicker = true }) {
                    HStack {
                        Text("入学年份")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "666666"))
                            .frame(width: 60, alignment: .leading)
                        Spacer()
                        Text(schoolYear.isEmpty ? "未填写" : "\(schoolYear)年")
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
            }
            Divider().padding(.leading, 16)
            infoRow(title: "邀请码", text: $invitationCode, editable: isEditing)
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
    
    // MARK: - 学生认证入口
    private var certificationSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("学生认证")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "CCCCCC"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture { onOpenCertification() }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
    
    private var yearOptions: [String] {
        let current = Calendar.current.component(.year, from: Date())
        return (0...10).map { String(current - $0) }
    }

    private var yearPickerSheet: some View {
        NavigationView {
            List(yearOptions, id: \.self) { year in
                Button(action: {
                    schoolYear = year
                    showYearPicker = false
                    Task {
                        _ = await apiService.updateUserInfo(params: ["schoolyear": year])
                    }
                }) {
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

    // MARK: - 方法
    private func loadProfile() {
        Task {
            let profile = await apiService.fetchUserProfile()
            await MainActor.run {
                self.userProfile = profile
                self.nickname = profile?.nickname ?? ""
                self.school = profile?.school ?? ""
                self.major = profile?.major ?? ""
                self.schoolYear = profile?.schoolYear ?? ""
                self.invitationCode = profile?.invitationCode ?? ""
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
                ok = await apiService.updateUserInfo(params: ["invitation_code": invitationCode])
            }
            if ok && !schoolYear.isEmpty {
                ok = await apiService.updateUserInfo(params: ["schoolyear": schoolYear])
            }
            await MainActor.run {
                saving = false
                if ok {
                    isEditing = false
                    loadProfile() // 重新加载
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
