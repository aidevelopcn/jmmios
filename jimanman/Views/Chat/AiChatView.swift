import SwiftUI
import AVFoundation

// MARK: - AI 答疑界面（对齐 Android AiChatScreen）
struct AiChatView: View {
    var onNeedLogin: () -> Void = {}
    var onCameraOverlayVisibleChanged: (Bool) -> Void = { _ in }

    @StateObject private var apiService = ApiService.shared
    @FocusState private var isInputFocused: Bool
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var loadingText = "思考中..."
    @State private var sessionId = UUID().uuidString
    @State private var showHistory = false
    @State private var conversationList: [ConversationItem] = []
    @State private var historyLoading = false

    @State private var activeStreamMessageId: String?
    @State private var activeStreamContent = ""

    @State private var pendingImage: UIImage?
    @State private var uploadingImage = false

    @State private var showCameraOverlay = false
    @State private var showAlbumPicker = false
    @State private var showCropDialog = false
    @State private var showCameraConfirm = false
    @State private var cropSourceImage: UIImage?
    @State private var cropInitialRatio: CropRectRatio?
    @State private var capturedImage: UIImage?
    @State private var capturedFrameSpec: CameraFrameSpec?
    @State private var streamTask: Task<Void, Never>?

    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var toastTask: Task<Void, Never>?
    @State private var showCameraPermissionAlert = false

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                chatTopBar
                messageList
                if isLoading && uploadingImage {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text(loadingText)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "94A3B8"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                inputBar
            }
            .background(Color(hex: "F5F7FA"))

            if showHistory {
                historyDrawer
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            ChatAlbumPicker(image: Binding(
                get: { nil },
                set: { image in
                    if let image {
                        cropSourceImage = image
                        cropInitialRatio = nil
                        showCropDialog = true
                    }
                }
            ))
        }
        .fullScreenCover(isPresented: $showCameraOverlay) {
            CameraCaptureOverlayView(
                onDismiss: { showCameraOverlay = false },
                onPickFromAlbum: {
                    showCameraOverlay = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showAlbumPicker = true
                    }
                },
                onImageCaptured: handleCameraCapture,
                onCaptureFailed: { message in
                    presentToast(message)
                }
            )
        }
        .overlay {
            if showCameraConfirm, let image = capturedImage {
                CameraCaptureConfirmView(
                    image: image,
                    onRetake: {
                        showCameraConfirm = false
                        capturedImage = nil
                        capturedFrameSpec = nil
                        showCameraOverlay = true
                    },
                    onCancel: {
                        showCameraConfirm = false
                        capturedImage = nil
                        capturedFrameSpec = nil
                    },
                    onConfirm: confirmFullPageCapture
                )
            }
        }
        .overlay {
            if showCropDialog, let image = cropSourceImage {
                ImageCropDialogView(
                    sourceImage: image,
                    initialRatio: cropInitialRatio,
                    onCancel: {
                        showCropDialog = false
                        cropSourceImage = nil
                        cropInitialRatio = nil
                    },
                    onConfirm: { cropped in
                        pendingImage = cropped
                        showCropDialog = false
                        cropSourceImage = nil
                        cropInitialRatio = nil
                    }
                )
            }
        }
        .onChange(of: showHistory) { showing in
            if showing { dismissKeyboard() }
        }
        .onChange(of: showCameraOverlay) { visible in
            updateCameraOverlayVisible()
        }
        .onChange(of: showCameraConfirm) { _ in
            updateCameraOverlayVisible()
        }
        .onDisappear {
            streamTask?.cancel()
            toastTask?.cancel()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .toastOverlay(message: toastMessage, isShowing: showToast)
        .alert("需要相机权限", isPresented: $showCameraPermissionAlert) {
            Button("去设置") { AppSettingsOpener.open() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许「绩满满」访问相机，以便拍摄题目。")
        }
    }

    private func updateCameraOverlayVisible() {
        onCameraOverlayVisibleChanged(showCameraOverlay || showCameraConfirm)
    }

    private func dismissKeyboard() {
        isInputFocused = false
    }

    // MARK: - 顶部导航栏
    private var chatTopBar: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(action: openHistory) {
                        Image("list")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }

                Text("AI答疑")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "2D3748"))

                HStack {
                    Spacer(minLength: 0)
                    Button(action: newChat) {
                        newChatIcon
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider().background(Color(hex: "E8ECF0"))
        }
        .background(Color.white)
    }

    @ViewBuilder
    private var newChatIcon: some View {
        if UIImage(named: "ic_ai_new_chat") != nil {
            Image("ic_ai_new_chat")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
        } else {
            Image(systemName: "square.and.pencil")
                .resizable()
                .scaledToFit()
                .foregroundColor(AppColors.primary)
        }
    }

    // MARK: - 消息列表
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(messages) { message in
                        if message.role == "user" {
                            HStack {
                                Spacer(minLength: 0)
                                UserBubble(message: message)
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: .trailing)
                            }
                            .padding(.top, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                AssistantBubble(
                                    message: message,
                                    isStreaming: message.isStreaming && message.id == activeStreamMessageId,
                                    streamingContent: activeStreamContent,
                                    waitingHint: uploadingImage ? "上传图片中" : (isLoading ? "正在思考" : nil)
                                )

                                if !message.isStreaming && !message.content.isEmpty {
                                    HStack(spacing: 8) {
                                        actionButton(title: "复制") { copyText(message.content) }
                                        actionButton(title: "收藏") {
                                            addToFavorites(type: "0", question: message.relatedQuestion, answer: message.content, image: message.relatedImageUrl)
                                        }
                                        actionButton(title: "错题本") {
                                            addToFavorites(type: "1", question: message.relatedQuestion, answer: message.content, image: message.relatedImageUrl)
                                        }
                                    }
                                    .padding(.top, 4)
                                    .padding(.leading, 4)
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 10)
            }
            .dismissKeyboardOnScrollIfAvailable()
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            .onChange(of: messages.count) { _ in scrollToBottom(proxy: proxy) }
            .onChange(of: activeStreamContent) { _ in scrollToBottom(proxy: proxy) }
        }
    }

    // MARK: - 输入栏
    private var inputBar: some View {
        VStack(spacing: 0) {
            if let img = pendingImage {
                HStack(spacing: 8) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .background(Color(hex: "E2E8F0"))
                    Button(action: { pendingImage = nil }) {
                        Text("移除").font(.system(size: 12)).foregroundColor(Color(hex: "E53E3E"))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            HStack(alignment: .center, spacing: 0) {
                Button(action: openCamera) {
                    Group {
                        if uploadingImage {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 18, height: 18)
                        } else {
                            Image("chat_carmer")
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(isLoading || uploadingImage)

                TextField("请输入问题", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(3)
                    .frame(minHeight: 40)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { handleSendOrStop() }
                    .padding(.leading, 8)

                Button(action: handleSendOrStop) {
                    Image(isLoading ? "ai_pause" : "ai_send")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .offset(x: -4)
            }
            .padding(.leading, 14)
            .padding(.trailing, 2)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 26).fill(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(hex: "F5F7FA"))
    }

    // MARK: - 历史侧边栏（对齐 Android 左滑抽屉）
    private var historyDrawer: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.33)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { showHistory = false }

            VStack(alignment: .leading, spacing: 0) {
                Text("会话记录")
                    .font(.system(size: 17))
                    .foregroundColor(Color(hex: "2D3748"))
                    .padding(.horizontal, 16)
                    .padding(.top, 40)
                    .padding(.bottom, 12)

                if historyLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("加载中...")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "94A3B8"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else if conversationList.isEmpty {
                    Text("暂无会话记录")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "94A3B8"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(conversationList) { chat in
                                Button(action: { loadConversation(chat) }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chat.title.isEmpty ? "未命名会话" : chat.title)
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "2D3748"))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(chat.messageCount) 条消息")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(hex: "A0AEC0"))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)

                                Divider().background(Color(hex: "EDF2F7"))
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: UIScreen.main.bounds.width * 0.82)
            .frame(maxHeight: .infinity)
            .background(Color.white)
        }
        .transition(.opacity)
        .zIndex(10)
    }

    // MARK: - 气泡组件
    private struct UserBubble: View {
        let message: ChatMessage

        var body: some View {
            VStack(alignment: .trailing, spacing: 0) {
                if let imageURL = message.imageLocalURL, !imageURL.isEmpty {
                    chatImageView(urlString: imageURL)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 80, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .background(Color.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                    if !message.content.isEmpty && message.content != "[图片]" {
                        Spacer().frame(height: 8)
                    }
                }

                if !message.content.isEmpty && message.content != "[图片]" {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "4ECDC4")))
        }

        @ViewBuilder
        private func chatImageView(urlString: String) -> some View {
            let normalized = urlString.replacingOccurrences(of: "(?<!:)/{2,}", with: "/", options: .regularExpression)
            if normalized.hasPrefix("http://") || normalized.hasPrefix("https://"), let url = URL(string: normalized) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Rectangle().fill(Color.white.opacity(0.2)).overlay(ProgressView())
                    }
                }
            } else if let url = URL(string: urlString), url.isFileURL, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Rectangle().fill(Color.white.opacity(0.2))
            }
        }
    }

    private struct StreamingAssistantBubble: View {
        let content: String
        let waitingHint: String?

        var body: some View {
            Group {
                if content.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text(waitingHint ?? "正在思考")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "94A3B8"))
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                } else {
                    Text(content)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "2D3748"))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private struct AssistantBubble: View {
        let message: ChatMessage
        let isStreaming: Bool
        let streamingContent: String
        let waitingHint: String?

        private var displayContent: String {
            isStreaming ? streamingContent : message.content
        }

        @State private var webHeight: CGFloat

        init(message: ChatMessage, isStreaming: Bool, streamingContent: String, waitingHint: String?) {
            self.message = message
            self.isStreaming = isStreaming
            self.streamingContent = streamingContent
            self.waitingHint = waitingHint
            _webHeight = State(initialValue: MarkdownWebViewPool.shared.cachedHeight(for: message.id))
        }

        var body: some View {
            Group {
                if displayContent.isEmpty && isStreaming {
                    StreamingAssistantBubble(content: "", waitingHint: waitingHint)
                } else if MathHTMLBuilder.needsRichRendering(displayContent) {
                    MarkdownMathBubbleView(
                        messageId: message.id,
                        content: displayContent,
                        isStreaming: isStreaming,
                        height: $webHeight
                    )
                    .frame(height: webHeight)
                } else if !displayContent.isEmpty {
                    Text(displayContent)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "2D3748"))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, isStreaming ? 8 : 0)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.top, 2)
        }
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "334155"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(hex: "E2E8F0")))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 相机流程
    private func openCamera() {
        guard let token = apiService.token, !token.isEmpty else {
            onNeedLogin()
            return
        }
        dismissKeyboard()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraOverlay = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCameraOverlay = true
                    } else {
                        presentToast("未开启相机权限")
                    }
                }
            }
        default:
            showCameraPermissionAlert = true
        }
    }

    private func presentToast(_ message: String) {
        toastMessage = message
        showToast = true
        ToastPresenter.scheduleAutoHide(task: &toastTask, isShowing: $showToast)
    }

    private func handleCameraCapture(_ image: UIImage, frameSpec: CameraFrameSpec) {
        showCameraOverlay = false
        if frameSpec.mode == .single {
            cropSourceImage = image
            cropInitialRatio = AiImageCropProcessor.mapFrameToImageRatio(image: image, frameSpec: frameSpec)
            showCropDialog = true
            return
        }
        capturedImage = image
        capturedFrameSpec = frameSpec
        showCameraConfirm = true
    }

    private func confirmFullPageCapture() {
        guard let image = capturedImage, let frameSpec = capturedFrameSpec else { return }
        showCameraConfirm = false
        if let cropped = AiImageCropProcessor.cropCapturedPhotoByFrame(image: image, frameSpec: frameSpec) {
            pendingImage = cropped
        } else {
            pendingImage = image
        }
        capturedImage = nil
        capturedFrameSpec = nil
    }

    // MARK: - 会话与发送
    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func newChat() {
        dismissKeyboard()
        streamTask?.cancel()
        streamTask = nil
        messages.removeAll()
        inputText = ""
        pendingImage = nil
        activeStreamMessageId = nil
        activeStreamContent = ""
        isLoading = false
        sessionId = UUID().uuidString
    }

    private func openHistory() {
        guard let token = apiService.token, !token.isEmpty else {
            onNeedLogin()
            return
        }
        dismissKeyboard()
        showHistory = true
        loadConversationList()
    }

    private func loadConversationList() {
        guard let token = apiService.token, !token.isEmpty else { return }
        Task {
            await MainActor.run { historyLoading = true }
            let list = await apiService.fetchConversationList()
            await MainActor.run {
                conversationList = list
                historyLoading = false
            }
        }
    }

    private func loadConversation(_ chat: ConversationItem) {
        guard let token = apiService.token, !token.isEmpty else {
            onNeedLogin()
            return
        }
        Task {
            await MainActor.run { historyLoading = true }
            let msgs = await apiService.fetchConversationDetail(conversationId: chat.id)
            await MainActor.run {
                messages = msgs
                sessionId = chat.id
                activeStreamMessageId = nil
                activeStreamContent = ""
                showHistory = false
                historyLoading = false
            }
        }
    }

    private func handleSendOrStop() {
        if isLoading {
            stopStreaming()
            return
        }
        sendMessage()
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        if let id = activeStreamMessageId {
            commitActiveStream(assistantId: id, markDone: true)
        } else {
            markLastStreamingDone()
        }
        isLoading = false
        loadingText = "思考中..."
    }

    private func sendMessage() {
        guard let token = apiService.token, !token.isEmpty else {
            onNeedLogin()
            return
        }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImage != nil else { return }

        let sendText = text.isEmpty ? "[图片]" : text
        inputText = ""
        dismissKeyboard()
        isLoading = true
        loadingText = "思考中..."

        let userMsg = ChatMessage(role: "user", content: sendText)
        let assistantId = UUID().uuidString
        messages.append(userMsg)
        messages.append(ChatMessage(
            id: assistantId,
            role: "assistant",
            content: "",
            isStreaming: true,
            relatedQuestion: sendText
        ))
        activeStreamMessageId = assistantId
        activeStreamContent = ""

        streamTask?.cancel()
        streamTask = Task {
            var fileURL = ""
            if let image = pendingImage {
                await MainActor.run {
                    uploadingImage = true
                    loadingText = "上传图片中..."
                }
                if let data = image.jpegData(compressionQuality: 0.92),
                   let url = await apiService.uploadFile(
                    imageData: data,
                    fileName: AiImageCropProcessor.nextShortImageName(prefix: "img"),
                    mimeType: "image/jpeg"
                   ) {
                    fileURL = url
                    await MainActor.run {
                        updateUserMessageImage(messageId: userMsg.id, url: url)
                        updateAssistantRelatedImage(assistantId: assistantId, url: url)
                    }
                } else {
                    await MainActor.run {
                        activeStreamContent += "\n\n图片上传失败，请重试。"
                        commitActiveStream(assistantId: assistantId, markDone: true)
                        isLoading = false
                        uploadingImage = false
                    }
                    return
                }
                await MainActor.run {
                    pendingImage = nil
                    uploadingImage = false
                    loadingText = "思考中..."
                }
            }

            await apiService.streamChat(token: token, prompt: sendText, sessionId: sessionId, fileURL: fileURL) { chunk in
                Task { @MainActor in
                    guard !chunk.isEmpty else { return }
                    isLoading = false
                    activeStreamContent += chunk
                }
            }

            await MainActor.run {
                commitActiveStream(assistantId: assistantId, markDone: true)
                isLoading = false
                loadingText = "思考中..."
                streamTask = nil
            }
        }
    }

    @MainActor
    private func commitActiveStream(assistantId: String, markDone: Bool) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        var msg = messages[idx]
        if !activeStreamContent.isEmpty {
            msg.content = activeStreamContent
        }
        msg.isStreaming = !markDone
        messages[idx] = msg
        if markDone {
            activeStreamMessageId = nil
            activeStreamContent = ""
        }
    }

    @MainActor
    private func markLastStreamingDone() {
        guard let idx = messages.lastIndex(where: { $0.isStreaming }) else { return }
        var msg = messages[idx]
        msg.isStreaming = false
        messages[idx] = msg
    }

    @MainActor
    private func updateUserMessageImage(messageId: String, url: String) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        var msg = messages[idx]
        msg.imageLocalURL = url
        messages[idx] = msg
    }

    @MainActor
    private func updateAssistantRelatedImage(assistantId: String, url: String) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        var msg = messages[idx]
        msg.relatedImageUrl = url
        messages[idx] = msg
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        presentToast("已复制")
    }

    private func addToFavorites(type: String, question: String, answer: String, image: String) {
        guard let token = apiService.token, !token.isEmpty else {
            onNeedLogin()
            return
        }
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else { return }
        var normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuestion == "[图片]" {
            normalizedQuestion = type == "1" ? "图片错题" : "图片题目"
        }
        let titleSource = !normalizedQuestion.isEmpty ? normalizedQuestion : (image.isEmpty ? trimmedAnswer : "图片题目")
        Task {
            var items: [[String: Any]] = []
            if !normalizedQuestion.isEmpty {
                items.append(["content": normalizedQuestion, "content_type": "user", "sort": 0])
            }
            items.append(["content": trimmedAnswer, "content_type": "assistant", "sort": normalizedQuestion.isEmpty ? 0 : 1])
            let ok = await apiService.addFavorite(
                type: type,
                title: String(titleSource.prefix(50)),
                image: image,
                items: items
            )
            await MainActor.run {
                if type == "1" {
                    presentToast(ok ? "已加入错题本" : "加入错题本失败")
                } else {
                    presentToast(ok ? "已加入收藏" : "收藏失败")
                }
            }
        }
    }
}












