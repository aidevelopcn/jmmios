import SwiftUI

// MARK: - 我的答疑列表（对齐 Android MyAskListScreen）
struct MyAskListView: View {
    let onBack: () -> Void
    let onNeedLogin: () -> Void

    @StateObject private var apiService = ApiService.shared
    @State private var currentTab = 0 // 0=错题本, 1=收藏
    @State private var wrongBookList: [AskRecordItem] = []
    @State private var favoriteList: [AskRecordItem] = []
    @State private var loading = false
    @State private var previewURL = ""
    @State private var showImagePreview = false
    @State private var detailItem: AskRecordItem?
    @State private var showUploadOptions = false
    @State private var showUploadPicker = false
    @State private var uploadSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var uploading = false
    @State private var toastMessage = ""
    @State private var showToast = false

    var body: some View {
        ProfileScreenScaffold(background: AppColors.background) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "我的答疑", onBack: onBack)

                if (apiService.token ?? "").isEmpty {
                    Spacer(minLength: 0)
                    Text("请先登录")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "6B7280"))
                        .onTapGesture { onNeedLogin() }
                    Spacer(minLength: 0)
                } else {
                    tabRow

                    if currentTab == 0 {
                        uploadBar
                    }

                    contentArea
                }
            }
        }
        .confirmationDialog("上传错题", isPresented: $showUploadOptions, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照") {
                    uploadSourceType = .camera
                    showUploadPicker = true
                }
            }
            Button("从相册选择") {
                uploadSourceType = .photoLibrary
                showUploadPicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showUploadPicker) {
            StudentImagePicker(image: Binding(
                get: { nil },
                set: { image in
                    if let image { uploadWrongBookImage(image) }
                }
            ), sourceType: uploadSourceType)
        }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
        .overlay { imagePreviewOverlay }
        .overlay { detailOverlay }
        .onAppear { reload(tab: currentTab) }
        .onChange(of: currentTab) { reload(tab: $0) }
    }

    private var tabRow: some View {
        HStack(spacing: 10) {
            askTabChip(title: "错题本", active: currentTab == 0) { currentTab = 0 }
            askTabChip(title: "我的收藏", active: currentTab == 1) { currentTab = 1 }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private var uploadBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: { showUploadOptions = true }) {
                Text(uploading ? "上传中..." : "拍照/相册上传错题")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(uploading ? Color(hex: "9CA3AF") : AppColors.primary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(uploading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(AppColors.background)
    }

    @ViewBuilder
    private var contentArea: some View {
        if loading {
            Spacer(minLength: 0)
            ProgressView()
            Spacer(minLength: 0)
        } else {
            let list = currentTab == 0 ? wrongBookList : favoriteList
            if list.isEmpty {
                Spacer(minLength: 0)
                Text(currentTab == 0 ? "暂无错题记录" : "暂无收藏记录")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "94A3B8"))
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(list) { item in
                            askRecordCard(item: item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var imagePreviewOverlay: some View {
        if showImagePreview, !previewURL.isEmpty {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { showImagePreview = false }

                VStack(spacing: 14) {
                    AskNetworkImage(urlString: previewURL, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("关闭") { showImagePreview = false }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppColors.primary))
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var detailOverlay: some View {
        if let item = detailItem {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { detailItem = nil }

                VStack(spacing: 0) {
                    Text("答疑详情")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "111111"))
                        .padding(.top, 18)
                        .padding(.bottom, 12)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            if !item.timeText.isEmpty {
                                Text(item.timeText)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "9CA3AF"))
                                Spacer().frame(height: 6)
                            }
                            if !item.questionText.isEmpty {
                                Text("题目")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(hex: "334155"))
                                Spacer().frame(height: 4)
                                Text(item.questionText)
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "0F172A"))
                                Spacer().frame(height: 10)
                            }
                            if !item.imageUrl.isEmpty {
                                AskNetworkImage(urlString: item.imageUrl, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .background(Color(hex: "F3F4F6"))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        previewURL = item.imageUrl
                                        showImagePreview = true
                                    }
                                Spacer().frame(height: 10)
                            }
                            Text("当前仅展示题目与图片，文本答疑可在AI会话中查看渲染内容")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "94A3B8"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 360)

                    Button("关闭") { detailItem = nil }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppColors.primary))
                        .padding(.vertical, 16)
                }
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    private func askTabChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(active ? .white : Color(hex: "64748B"))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(active ? Color(hex: "4ECDC4") : Color(hex: "F1F5F9")))
        }
        .buttonStyle(.plain)
    }

    private func askRecordCard(item: AskRecordItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.timeText)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "9CA3AF"))

            if !item.questionText.isEmpty {
                Spacer().frame(height: 6)
                Text(item.questionText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "111111"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !item.imageUrl.isEmpty {
                Spacer().frame(height: 8)
                AskNetworkImage(urlString: item.imageUrl, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background(Color(hex: "F3F4F6"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        previewURL = item.imageUrl
                        showImagePreview = true
                    }
            }

            Spacer().frame(height: 10)
            HStack {
                Spacer(minLength: 0)
                Button(action: { detailItem = item }) {
                    Text("查看解答")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }

    private func reload(tab: Int) {
        guard let token = apiService.token, !token.isEmpty else { return }
        Task {
            await MainActor.run { loading = true }
            let type = tab == 0 ? "1" : "0"
            let list = await ApiService.shared.fetchFavoriteRecords(type: type)
            await MainActor.run {
                if tab == 0 {
                    wrongBookList = list
                } else {
                    favoriteList = list
                }
                loading = false
            }
        }
    }

    private func uploadWrongBookImage(_ image: UIImage) {
        guard apiService.token != nil else {
            onNeedLogin()
            return
        }
        uploading = true
        Task {
            var ok = false
            if let data = image.jpegData(compressionQuality: 0.92),
               let url = await apiService.uploadFile(
                imageData: data,
                fileName: "wrong_\(Int(Date().timeIntervalSince1970)).jpg",
                mimeType: "image/jpeg"
               ) {
                ok = await apiService.addWrongBookFromImage(imageUrl: url)
            }
            await MainActor.run {
                uploading = false
                toastMessage = ok ? "已加入错题本" : "上传失败"
                showToast = true
                if ok { reload(tab: 0) }
            }
        }
    }
}

// MARK: - 网络图片（对齐 Android NetworkImage + normalizeUrl）
private struct AskNetworkImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: URL(string: AskMediaURL.normalize(urlString))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                Rectangle().fill(Color(hex: "F3F4F6"))
            default:
                Rectangle()
                    .fill(Color(hex: "F3F4F6"))
                    .overlay(ProgressView().scaleEffect(0.8))
            }
        }
    }
}

private enum AskMediaURL {
    static func normalize(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        return text.replacingOccurrences(
            of: "(?<!:)/{2,}",
            with: "/",
            options: .regularExpression
        )
    }
}
