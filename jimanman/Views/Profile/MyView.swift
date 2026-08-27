import SwiftUI

// MARK: - 个人中心
struct MyView: View {
    let onNeedLogin: () -> Void
    let onOpenMyAsk: () -> Void
    let onOpenAssessment: () -> Void
    let onOpenVip: () -> Void
    let onOpenAccount: () -> Void
    let onOpenStudentInfo: () -> Void
    
    @StateObject private var apiService = ApiService.shared
    @State private var userProfile: UserProfile?
    @State private var showNicknameDialog = false
    @State private var nicknameInput = ""
    @State private var saving = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var imageUploading = false
    
    private var menuItems: [(title: String, icon: String)] {
        var items: [(title: String, icon: String)] = [
            ("基本信息", "sligo"),
            ("我的答疑", "myask"),
            ("我的测评", "item_c3"),
        ]
        if AppFeatures.showMembership {
            items.append(("会员中心", "item_c2"))
        }
        items.append(("账号管理", "item_c5"))
        return items
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                pageTitleBar(title: "个人中心")
                
                // 用户信息头部
                userHeader
                
                // 菜单列表
                menuList
            }
        }
        .background(Color.white)
        .onAppear { loadUserProfile() }
        .sheet(isPresented: $showNicknameDialog) {
            nicknameEditSheet
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage, sourceType: .photoLibrary)
        }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                uploadAvatar(image: image)
            }
        }
    }
    
    // MARK: - 页面标题栏
    private func pageTitleBar(title: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "2D3748"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            Divider().background(Color(hex: "E8ECF0"))
        }
        .background(Color.white)
    }
    
    // MARK: - 用户头部
    private var userHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if apiService.token == nil {
                    Text("未登录")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .onTapGesture { onNeedLogin() }
                } else {
                    HStack(spacing: 4) {
                        Text((userProfile?.nickname ?? "").isEmpty ? "用户" : userProfile!.nickname)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .onTapGesture {
                                nicknameInput = userProfile?.nickname ?? ""
                                showNicknameDialog = true
                            }
                        Text("(ID:\(userProfile?.id ?? 0))")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "E6FFFB"))
                        
                        Button(action: {
                            nicknameInput = userProfile?.nickname ?? ""
                            showNicknameDialog = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                    }

                    if AppFeatures.showMembership {
                        let vipText = userProfile?.isVip == true ? "VIP\(userProfile?.vipTime ?? "")到期" : "VIP已过期"
                        Text(vipText)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "E6FFFB"))
                    }
                }
            }
            
            Spacer()
            
            AsyncImage(url: URL(string: userProfile?.avatarUrl.replacingOccurrences(of: "/{2,}", with: "/", options: .regularExpression) ?? "")) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Circle().fill(Color.gray.opacity(0.3)).overlay(Text("头像").font(.caption))
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .onTapGesture {
                        if apiService.token != nil {
                            showImagePicker = true
                        } else {
                            onNeedLogin()
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if apiService.token != nil {
                            if imageUploading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Capsule())
                                    .offset(y: 10)
                            } else {
                                Text("编辑")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Capsule())
                                    .offset(y: 10)
                            }
                        }
                    }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(AppColors.primary)
    }
    
    // MARK: - 菜单列表
    @ViewBuilder
    private var menuList: some View {
        ForEach(Array(menuItems.enumerated()), id: \.offset) { index, item in
            if index > 0 { Divider().padding(.leading, 16).background(Color(hex: "EEEEEE").opacity(0.5)) }

            HStack(spacing: 12) {
                Image(item.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)

                Text(item.title)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Image("right9")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                switch item.title {
                case "基本信息": onOpenStudentInfo()
                case "我的答疑":
                    if apiService.token == nil { onNeedLogin() } else { onOpenMyAsk() }
                case "我的测评": onOpenAssessment()
                case "会员中心":
                    if apiService.token == nil { onNeedLogin() } else { onOpenVip() }
                case "账号管理": onOpenAccount()
                default: break
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }

        Spacer().frame(height: 24)
    }
    
    // MARK: - 昵称编辑弹窗
    private var nicknameEditSheet: some View {
        NavigationView {
            Form {
                Section("修改昵称") {
                    TextField("请输入昵称", text: $nicknameInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .navigationTitle("修改昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showNicknameDialog = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中..." : "确定") {
                        saveNickname()
                    }.disabled(saving || nicknameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    // MARK: - 方法
    private func loadUserProfile() {
        Task {
            let profile = await apiService.fetchUserProfile()
            await MainActor.run { self.userProfile = profile }
        }
    }
    
    private func saveNickname() {
        let next = nicknameInput.trimmingCharacters(in: .whitespaces)
        guard !next.isEmpty else { return }
        saving = true
        Task {
            let ok = await apiService.updateProfileInfo(nickname: next,
                                                         school: userProfile?.school ?? "",
                                                         major: userProfile?.major ?? "")
            await MainActor.run {
                saving = false
                if ok {
                    userProfile?.nickname = next
                    showNicknameDialog = false
                }
            }
        }
    }
    
    // MARK: - 头像上传
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
                let normalizedPath = filePath.replacingOccurrences(of: "/{2,}", with: "/", options: .regularExpression)
                let ok = await apiService.updateUserInfo(params: ["avatarUrl": normalizedPath])
                await MainActor.run {
                    imageUploading = false
                    if ok {
                        loadUserProfile()
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
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
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
