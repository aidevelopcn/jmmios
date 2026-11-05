import SwiftUI
import UIKit

// MARK: - 个人中心
struct MyView: View {
    let onNeedLogin: () -> Void
    let onOpenMyAsk: () -> Void
    let onOpenAssessment: () -> Void
    let onOpenVip: () -> Void
    let onOpenAccount: () -> Void
    let onOpenStudentInfo: () -> Void
    var onOpenFeedback: () -> Void = {}
    
    @ObservedObject private var apiService = ApiService.shared
    @State private var userProfile: UserProfile?
    @State private var showNicknameDialog = false
    @State private var nicknameInput = ""
    @State private var saving = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var imageUploading = false
    
    private var loggedIn: Bool { !(apiService.token ?? "").isEmpty }
    private let customerServiceURL = URL(string: "https://work.weixin.qq.com/kfid/kfcb8e8bcd4fd690dae")!
    private let menuItems: [(title: String, icon: String)] = [
        ("基本信息", "sligo"),
        ("拾错藏珍", "myask"),
        ("我的测评", "item_c3"),
        ("联系客服", "item_c6"),
        ("账号管理", "item_c5"),
        ("问题反馈", "item_icon3"),
    ]
    
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
        .onChange(of: apiService.token) { _ in loadUserProfile() }
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if !loggedIn {
                    Text("未登录")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .onTapGesture { onNeedLogin() }
                } else {
                    HStack(spacing: 8) {
                        Text((userProfile?.nickname ?? "").isEmpty ? "用户" : userProfile!.nickname)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .onTapGesture { openNicknameEditor() }
                        Text("✎")
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .onTapGesture { openNicknameEditor() }
                    }
                    Text(userProfile?.isStudent == true ? "学员" : "非学员")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "E6FFFB"))
                }
            }
            Spacer()
            ZStack(alignment: .bottom) {
                avatarImage
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                if loggedIn {
                    Text("编辑")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.66))
                        .clipShape(Capsule())
                }
                if imageUploading {
                    Color.black.opacity(0.4)
                        .clipShape(Circle())
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 80, height: 80)
            .onTapGesture {
                if loggedIn {
                    showImagePicker = true
                } else {
                    onNeedLogin()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(height: 138)
        .background(Color(hex: "4DCDC4"))
    }

    private var avatarImage: some View {
        let raw = userProfile?.avatarUrl ?? ""
        let url = URL(string: raw.replacingOccurrences(of: "/{2,}", with: "/", options: .regularExpression))
        return Group {
            if loggedIn, let url, !raw.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image("unlogin_headpic").resizable().scaledToFill()
                    }
                }
            } else {
                Image("unlogin_headpic").resizable().scaledToFill()
            }
        }
    }

    private func openNicknameEditor() {
        nicknameInput = userProfile?.nickname ?? ""
        showNicknameDialog = true
    }
    
    // MARK: - 菜单列表
    @ViewBuilder
    private var menuList: some View {
        ForEach(Array(menuItems.enumerated()), id: \.offset) { _, item in
            Color(hex: "EEEEEE").opacity(0.5).frame(height: 0.5)
            HStack(spacing: 12) {
                Image(item.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text(item.title)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "111111"))
                Spacer()
                Image("right9")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 28)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                switch item.title {
                case "基本信息": onOpenStudentInfo()
                case "拾错藏珍":
                    if !loggedIn { onNeedLogin() } else { onOpenMyAsk() }
                case "我的测评": onOpenAssessment()
                case "联系客服": UIApplication.shared.open(customerServiceURL)
                case "账号管理": onOpenAccount()
                case "问题反馈":
                    if !loggedIn { onNeedLogin() } else { onOpenFeedback() }
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
        guard loggedIn else {
            userProfile = nil
            return
        }
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
