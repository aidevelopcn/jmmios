import SwiftUI
import AVFoundation
import UIKit

// MARK: - AI 答疑界面（对齐 Android AiChatScreen）
struct AiChatView: View {
    var onNeedLogin: () -> Void = {}
    var onOpenTimetable: () -> Void = {}
    var onOpenHome: () -> Void = {}
    var onOpenMine: () -> Void = {}
    var qaRefreshTrigger: Int = 0
    var onCameraOverlayVisibleChanged: (Bool) -> Void = { _ in }
    var onHistoryVisibleChanged: (Bool) -> Void = { _ in }

    @StateObject private var apiService = ApiService.shared
    @FocusState private var isInputFocused: Bool
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var loadingText = "正在思考"
    @State private var sessionId = UUID().uuidString
    @State private var showHistory = false
    @State private var conversationList: [ConversationItem] = []
    @State private var historyLoading = false
    @State private var historySubjectFilter = "全部"
    @State private var conversationToDelete: ConversationItem?
    @State private var subjectToDelete: String?
    @State private var newSubjectPrompt: String?
    @State private var showDeleteSubjectAlert = false
    @State private var showNewSubjectAlert = false
    @State private var showNewSubjectPicker = false
    @State private var deleteInProgress = false
    @State private var agentsLoading = true
    @State private var qaMatchedSubjects: [String] = []
    @State private var selectedQaSubject = ""
    @State private var selectedQaMode = "answer"
    @State private var selectedQaProvider = "qwen"
    @State private var qaChatConfig = QaChatConfig()
    @State private var currentAgentId = 1
    @State private var currentConversationId = ""
    @State private var qaFavoriteId = 0
    @State private var qaWrongId = 0

    @State private var activeStreamMessageId: String?
    @State private var activeStreamContent = ""

    @State private var pendingImage: UIImage?
    @State private var uploadingImage = false

    @State private var showCameraOverlay = false
    @State private var showAlbumPicker = false
    @State private var showCropDialog = false
    @State private var cropFromCamera = false
    @State private var showPendingImagePreview = false
    @State private var cropSourceImage: UIImage?
    @State private var cropInitialRatio: CropRectRatio?
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
                        cropFromCamera = false
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
            if showCropDialog, let image = cropSourceImage {
                ImageCropDialogView(
                    sourceImage: image,
                    initialRatio: cropInitialRatio,
                    allowRetake: true,
                    retakeLabel: cropFromCamera ? "重拍" : "重选",
                    onRetake: {
                        let fromCamera = cropFromCamera
                        showCropDialog = false
                        cropSourceImage = nil
                        cropInitialRatio = nil
                        cropFromCamera = false
                        if fromCamera {
                            showCameraOverlay = true
                        } else {
                            showAlbumPicker = true
                        }
                    },
                    onCancel: {
                        showCropDialog = false
                        cropSourceImage = nil
                        cropInitialRatio = nil
                        cropFromCamera = false
                    },
                    onConfirm: { cropped in
                        pendingImage = cropped
                        showPendingImagePreview = false
                        showCropDialog = false
                        cropSourceImage = nil
                        cropInitialRatio = nil
                        cropFromCamera = false
                    }
                )
            }
        }
        .overlay {
            if showPendingImagePreview, let img = pendingImage {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { showPendingImagePreview = false }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("预览题目")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "1F2937"))
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 420)
                            .frame(maxWidth: .infinity)
                        Button(action: { showPendingImagePreview = false }) {
                            Text("关闭")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(hex: "00AFA4"), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 12)
                }
            }
        }
        .onChange(of: showHistory) { showing in
            onHistoryVisibleChanged(showing)
            if showing { dismissKeyboard() }
        }
        .onChange(of: qaRefreshTrigger) { _ in
            loadQaBootstrap()
        }
        .onAppear {
            onHistoryVisibleChanged(showHistory)
            MarkdownWebViewPool.shared.prewarm()
            loadQaBootstrap()
        }
        .alert("删除该会话？", isPresented: Binding(
            get: { conversationToDelete != nil },
            set: { if !$0 { conversationToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let chat = conversationToDelete {
                    deleteConversation(chat)
                }
            }
            Button("取消", role: .cancel) { conversationToDelete = nil }
        } message: {
            Text("删除后无法恢复")
        }
        .background(qaSubjectDialogs)
        .onChange(of: showCameraOverlay) { _ in
            updateCameraOverlayVisible()
        }
        .onChange(of: showCropDialog) { _ in
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
        onCameraOverlayVisibleChanged(showCameraOverlay || showCropDialog)
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

                Text(selectedQaSubject.isEmpty ? "AI答疑" : "\(selectedQaSubject)·答疑·")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "2D3748"))
                    .lineLimit(1)

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
                VStack(alignment: .leading, spacing: 0) {
                    if selectedQaSubject.isEmpty {
                        QaWelcomePanel(
                            loading: agentsLoading,
                            hasRegisteredSubjects: !qaMatchedSubjects.isEmpty,
                            onOpenTimetable: onOpenTimetable
                        )
                    }
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
                                if !message.isStreaming && !message.content.isEmpty && !QaHelpers.isStreamErrorChunk(message.content) {
                                    Text("本内容由AI生成")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "94A3B8"))
                                        .padding(.top, 8)
                                        .padding(.leading, 2)
                                }
                                if !message.isStreaming && !message.content.isEmpty {
                                    HStack(spacing: 16) {
                                        qaActionButton(system: "doc.on.doc", label: "复制", active: false) {
                                            copyText(message.content)
                                        }
                                        qaActionButton(system: (message.favoriteId > 0 || qaFavoriteId > 0) ? "star.fill" : "star", label: "收藏", active: message.favoriteId > 0 || qaFavoriteId > 0) {
                                            toggleFavorite(type: "0", message: message)
                                        }
                                        qaActionButton(system: (message.wrongId > 0 || qaWrongId > 0) ? "exclamationmark.circle.fill" : "exclamationmark.circle", label: "加入错题", active: message.wrongId > 0 || qaWrongId > 0) {
                                            toggleFavorite(type: "1", message: message)
                                        }
                                    }
                                    .padding(.top, 7)
                                    .padding(.leading, 2)
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
                HStack(spacing: 12) {
                    Button(action: { showPendingImagePreview = true }) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    Button(action: {
                        pendingImage = nil
                        showPendingImagePreview = false
                    }) {
                        Text("移除").font(.system(size: 12)).foregroundColor(Color(hex: "E53E3E"))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            if qaChatConfig.modes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(qaChatConfig.modes) { item in
                            let active = selectedQaMode == item.key
                            Button(action: {
                                selectedQaMode = item.key
                                selectedQaProvider = QaHelpers.providerForQaMode(config: qaChatConfig, modeKey: item.key)
                            }) {
                                Text(item.label)
                                    .font(.system(size: 11))
                                    .foregroundColor(active ? .white : Color(hex: "64748B"))
                                    .frame(width: 72, height: 32)
                                    .background(Capsule().fill(active ? Color(hex: "4ECDC4") : Color.white))
                                    .overlay(Capsule().stroke(active ? Color(hex: "4ECDC4") : Color(hex: "E2E8F0"), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 12)
                .background(Color(hex: "F5F7FA"))
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

                TextField("请输入问题，可拍照上传", text: $inputText)
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
            .padding(.top, 0)
            .padding(.bottom, 16)
        }
        .background(Color(hex: "F5F7FA"))
    }

    // MARK: - 历史侧边栏（对齐 Android 左滑抽屉）
    private var historyDrawer: some View {
        QaHistoryDrawerView(
            conversationList: conversationList,
            qaMatchedSubjects: qaMatchedSubjects,
            historyLoading: historyLoading,
            historySubjectFilter: $historySubjectFilter,
            onClose: { showHistory = false },
            onSelect: loadConversation,
            onDelete: { conversationToDelete = $0 },
            onCreateSubject: { createQaSubject($0) },
            onDeleteSubject: {
                subjectToDelete = $0
                showDeleteSubjectAlert = true
            },
            onOpenHome: {
                showHistory = false
                onOpenHome()
            },
            onOpenMine: {
                showHistory = false
                onOpenMine()
            }
        )
    }

    // MARK: - 气泡组件
    private struct UserBubble: View {
        let message: ChatMessage
        
        var body: some View {
            VStack(alignment: .trailing, spacing: 0) {
                if let imageURL = message.imageLocalURL, !imageURL.isEmpty {
                    chatImageView(urlString: imageURL)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 80, maxHeight: 280)
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
                        .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "4ECDC4")))
                }
            }
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
            let live = streamingContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if isStreaming {
                return live.isEmpty ? message.content : streamingContent
            }
            return message.content.isEmpty ? streamingContent : message.content
        }

        @State private var webHeight: CGFloat

        init(message: ChatMessage, isStreaming: Bool, streamingContent: String, waitingHint: String?) {
            self.message = message
            self.isStreaming = isStreaming
            self.streamingContent = streamingContent
            self.waitingHint = waitingHint
            let cached = MarkdownWebViewPool.shared.cachedHeight(for: message.id)
            _webHeight = State(initialValue: cached > 48 ? cached : 160)
        }

        private var assistantText: some View {
            Text(displayContent)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "2D3748"))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, 4)
        }
        
        var body: some View {
            ZStack(alignment: .leading) {
                if !displayContent.isEmpty || isStreaming {
                    MarkdownMathBubbleView(
                        messageId: message.id,
                        content: displayContent,
                        isStreaming: isStreaming,
                        height: $webHeight
                    )
                    .frame(maxWidth: displayContent.isEmpty ? 1 : .infinity)
                    .frame(height: displayContent.isEmpty ? 1 : max(webHeight, 80))
                    .padding(.horizontal, displayContent.isEmpty ? 0 : 12)
                    .padding(.vertical, displayContent.isEmpty ? 0 : 10)
                    .background(displayContent.isEmpty ? Color.clear : Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, displayContent.isEmpty ? 0 : 8)
                    .opacity(displayContent.isEmpty ? 0 : 1)
                    .allowsHitTesting(!displayContent.isEmpty)
                }
                if displayContent.isEmpty && isStreaming {
                    StreamingAssistantBubble(content: "", waitingHint: waitingHint)
                }
            }
            .padding(.top, 2)
        }
    }

    private func qaActionButton(system: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 13))
                    .foregroundColor(active ? Color(hex: "00AFA4") : Color(hex: "6B7280"))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "6B7280"))
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func drawerFooterButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "00786C"))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(Color(hex: "E0FAF6")))
                .overlay(Capsule().stroke(Color(hex: "00DCC8"), lineWidth: 1))
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

    private func handleCameraCapture(_ image: UIImage, _: CameraFrameSpec) {
        showCameraOverlay = false
        cropFromCamera = true
        cropSourceImage = image
        cropInitialRatio = nil
        showCropDialog = true
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
        currentConversationId = ""
        qaFavoriteId = 0
        qaWrongId = 0
        selectedQaSubject = ""
        presentToast("已在新对话中，科目已清空")
    }

    private func loadQaBootstrap() {
        Task {
            await MainActor.run { agentsLoading = true }
            guard let token = apiService.token, !token.isEmpty else {
                await MainActor.run {
                    qaMatchedSubjects = []
                    qaChatConfig = QaChatConfig()
                    selectedQaProvider = "qwen"
                    selectedQaMode = "answer"
                    agentsLoading = false
                }
                return
            }
            let result = await apiService.fetchQaAgentList()
            let hint = await AcademicApi.fetchQaSubjectHint()
            let registered = await AcademicApi.fetchRegisteredSubjectNamesAllSemesters()
            let extra = QaHelpers.mergeSubjectNames(result.subjects, hint?.subjects ?? [], hint?.unmatched ?? [], registered)
            let subjects = await AcademicApi.loadSortedQaSubjectNames(extra: extra)
            await MainActor.run {
                qaChatConfig = result.qaConfig
                selectedQaMode = QaHelpers.pickQaChoice(
                    items: result.qaConfig.modes,
                    defaultKey: result.qaConfig.defaultMode,
                    currentKey: selectedQaMode,
                    fallback: "answer"
                )
                selectedQaProvider = QaHelpers.providerForQaMode(config: result.qaConfig, modeKey: selectedQaMode)
                currentAgentId = result.agents.first?.id ?? 1
                qaMatchedSubjects = subjects
                if !selectedQaSubject.isEmpty, !subjects.contains(selectedQaSubject) {
                    selectedQaSubject = ""
                }
                agentsLoading = false
            }
            if conversationList.isEmpty {
                let result = await apiService.fetchConversationListResult()
                await MainActor.run {
                    if case .success(let list) = result {
                        conversationList = list
                    } else if case .authExpired = result {
                        handleAuthExpired()
                    }
                }
            }
        }
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

    /// token 失效：清本地登录态并跳登录页（对齐鸿蒙 QaScreen.needLogin）
    @MainActor
    private func handleAuthExpired(closeHistory: Bool = true) {
        streamTask?.cancel()
        streamTask = nil
        isLoading = false
        uploadingImage = false
        loadingText = "正在思考"
        if let id = activeStreamMessageId {
            messages.removeAll { $0.id == id }
            activeStreamMessageId = nil
            activeStreamContent = ""
        }
        if closeHistory {
            showHistory = false
            historyLoading = false
        }
        apiService.clearSessionForReLogin()
        onNeedLogin()
    }
    
    private func loadConversationList() {
        guard let token = apiService.token, !token.isEmpty else { return }
        Task {
            await MainActor.run { historyLoading = true }
            let result = await apiService.fetchConversationListResult()
            await MainActor.run {
                switch result {
                case .success(let list):
                    conversationList = list
                    historyLoading = false
                case .authExpired:
                    handleAuthExpired()
                case .failure:
                    historyLoading = false
                }
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
            let detail = await apiService.fetchConversationDetail(conversationId: chat.id)
            await MainActor.run {
                messages = detail.messages
                sessionId = detail.sessionId.isEmpty ? (chat.sessionId.isEmpty ? chat.id : chat.sessionId) : detail.sessionId
                currentConversationId = chat.id
                currentAgentId = detail.agentId > 0 ? detail.agentId : (chat.agentId > 0 ? chat.agentId : currentAgentId)
                qaFavoriteId = detail.favoriteId
                qaWrongId = detail.wrongId
                if !chat.subjectName.isEmpty { selectedQaSubject = chat.subjectName }
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
        loadingText = "正在思考"
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
        loadingText = "正在思考"

        let userMsg = ChatMessage(role: "user", content: sendText)
        let assistantId = UUID().uuidString
        messages.append(userMsg)
        let sentMode = qaChatConfig.modes.first(where: { $0.key == selectedQaMode })?.label ?? "答案模式"
        messages.append(ChatMessage(
            id: assistantId,
            role: "assistant",
            content: "",
            isStreaming: true,
            relatedQuestion: sendText,
            qaMode: sentMode
        ))
        activeStreamMessageId = assistantId
        activeStreamContent = ""

        streamTask?.cancel()
        streamTask = Task {
            var fileURL = ""
            let uploadedFromPending = pendingImage != nil
            if let image = pendingImage {
                await MainActor.run {
                    uploadingImage = true
                    loadingText = "上传图片中..."
                }
                let data = await Task.detached(priority: .userInitiated) {
                    AiImageCropProcessor.jpegForUpload(image)
                }.value
                if let data {
                    let upload = await apiService.uploadFileResult(
                        imageData: data,
                        fileName: AiImageCropProcessor.nextShortImageName(prefix: "img"),
                        mimeType: "image/jpeg"
                    )
                    switch upload {
                    case .success(let url):
                        fileURL = url
                        await MainActor.run {
                            updateUserMessageImage(messageId: userMsg.id, url: url)
                            updateAssistantRelatedImage(assistantId: assistantId, url: url)
                        }
                    case .authExpired:
                        await MainActor.run { handleAuthExpired() }
                        return
                    case .failure:
                        await MainActor.run {
                            activeStreamContent += "\n\n图片上传失败，请重试。"
                            commitActiveStream(assistantId: assistantId, markDone: true)
                            isLoading = false
                            uploadingImage = false
                        }
                        return
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
                }
            }

            let excludeIds: Set<String> = [userMsg.id, assistantId]
            var sendSubject = ""
            var history: [[String: String]] = []
            await MainActor.run {
                if fileURL.isEmpty {
                    fileURL = QaHelpers.lastReusableImageUrl(messages, excludeIds: excludeIds)
                }
                let hasCompletedAnswer = messages.contains {
                    $0.id != assistantId &&
                    $0.role == "assistant" &&
                    !$0.isStreaming &&
                    !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !QaHelpers.isStreamErrorChunk($0.content)
                }
                if uploadedFromPending && hasCompletedAnswer {
                    sessionId = UUID().uuidString
                    currentConversationId = ""
                    qaFavoriteId = 0
                    qaWrongId = 0
                }
                sendSubject = uploadedFromPending
                    ? QaHelpers.inferQaSubjectFromText(sendText, registered: qaMatchedSubjects)
                    : QaHelpers.inferQaSubject(prompt: sendText, registered: qaMatchedSubjects, selected: selectedQaSubject)
                loadingText = (sendSubject.isEmpty && !uploadedFromPending) ? "正在识别科目..." : "正在思考"
                if !uploadedFromPending {
                    history = buildQaChatHistory(excludeIds: excludeIds)
                }
            }

            let detected = NSMutableString()
            let streamResult = await apiService.streamChat(
                token: token,
                prompt: sendText,
                sessionId: sessionId,
                agentId: currentAgentId,
                fileURL: fileURL,
                subject: sendSubject,
                provider: selectedQaProvider,
                mode: qaChatConfig.modes.first(where: { $0.key == selectedQaMode })?.label ?? "答案模式",
                history: history,
                onSubject: { name in
                    let subject = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !subject.isEmpty else { return }
                    if selectedQaSubject != subject {
                        let hadSubject = !selectedQaSubject.isEmpty
                        selectedQaSubject = subject
                        historySubjectFilter = subject
                        if hadSubject { presentToast("已切换科目：\(subject)") }
                    }
                    if isLoading { loadingText = "正在思考" }
                },
                onNewSubject: { name in
                    let subject = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !subject.isEmpty else { return }
                    detected.setString(subject)
                    if selectedQaSubject != subject { selectedQaSubject = subject }
                    if isLoading { loadingText = "正在思考" }
                }
            ) { chunk in
                applyStreamChunk(assistantId: assistantId, chunk: chunk)
            }

            await MainActor.run {
                if streamResult == .authExpired {
                    handleAuthExpired()
                    return
                }
                if streamResult == .cancelled {
                    isLoading = false
                    loadingText = "正在思考"
                    streamTask = nil
                    return
                }
                if activeStreamContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    activeStreamContent = "答疑服务已连接，但没有返回内容，请再试一次"
                }
                let finalAnswer = activeStreamContent
                commitActiveStream(assistantId: assistantId, markDone: true)
                isLoading = false
                loadingText = "正在思考"
                streamTask = nil
                if detected.length > 0 {
                    newSubjectPrompt = detected as String
                    showNewSubjectAlert = true
                }
                if !finalAnswer.isEmpty, !QaHelpers.isStreamErrorChunk(finalAnswer) {
                    persistAndRefresh(
                        prompt: sendText,
                        answer: finalAnswer,
                        fileUrl: fileURL,
                        sendSubject: sendSubject
                    )
                }
            }
        }
    }

    private func persistAndRefresh(prompt: String, answer: String, fileUrl: String, sendSubject: String) {
        Task {
            let subject = QaHelpers.inferQaSubject(
                prompt: "\(answer)\n\(prompt)",
                registered: qaMatchedSubjects,
                selected: selectedQaSubject.isEmpty ? sendSubject : selectedQaSubject
            )
            let saved = await apiService.persistConversation(
                sessionId: sessionId,
                agentId: currentAgentId,
                prompt: prompt,
                answer: answer,
                fileUrl: fileUrl,
                mode: qaChatConfig.modes.first(where: { $0.key == selectedQaMode })?.label ?? "答案模式",
                subject: subject
            )
            guard saved else { return }
            let result = await apiService.fetchConversationListResult()
            await MainActor.run {
                switch result {
                case .success(let list):
                    conversationList = list
                    if let match = list.first(where: { $0.sessionId == sessionId }) {
                        currentConversationId = match.id
                    }
                case .authExpired:
                    handleAuthExpired()
                case .failure:
                    break
                }
            }
        }
    }

    private func buildQaChatHistory(excludeIds: Set<String>) -> [[String: String]] {
        messages
            .filter { !excludeIds.contains($0.id) && !$0.isStreaming && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(8)
            .map { item in
                let role = item.role == "user" ? "user" : "assistant"
                var content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if role == "user", content == "[图片]" || content.isEmpty {
                    content = "（用户上传了题目图片，上一轮已识别并作答。）"
                }
                if content.count > 1600 { content = String(content.prefix(1600)) }
                return ["role": role, "content": content]
            }
    }

    private func deleteConversation(_ chat: ConversationItem) {
        conversationToDelete = nil
        Task {
            await MainActor.run { deleteInProgress = true }
            let ok = await apiService.deleteConversation(conversationId: chat.id)
            if ok {
                let result = await apiService.fetchConversationListResult()
                await MainActor.run {
                    switch result {
                    case .success(let list):
                        conversationList = list
                        if currentConversationId == chat.id {
                            newChat()
                        }
                        deleteInProgress = false
                    case .authExpired:
                        deleteInProgress = false
                        handleAuthExpired()
                    case .failure:
                        deleteInProgress = false
                    }
                }
            } else {
                await MainActor.run {
                    deleteInProgress = false
                    presentToast("删除失败")
                }
            }
        }
    }

    @MainActor
    private func applyStreamChunk(assistantId: String, chunk: String) {
        guard !chunk.isEmpty else { return }
        isLoading = false
        activeStreamContent += chunk
        if let idx = messages.firstIndex(where: { $0.id == assistantId }), messages[idx].content.isEmpty {
            messages[idx].isStreaming = true
        }
    }

    @MainActor
    private func commitActiveStream(assistantId: String, markDone: Bool) {
        var next = messages
        guard let idx = next.firstIndex(where: { $0.id == assistantId }) else { return }
        if !activeStreamContent.isEmpty {
            next[idx].content = activeStreamContent
        }
        next[idx].isStreaming = !markDone
        messages = next
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

    private func toggleFavorite(type: String, message: ChatMessage) {
        guard apiService.token?.isEmpty == false else {
            onNeedLogin()
            return
        }
        let was = type == "1" ? qaWrongId : qaFavoriteId
        if type == "1" { qaWrongId = was > 0 ? 0 : 1 } else { qaFavoriteId = was > 0 ? 0 : 1 }
        Task {
            let result = await apiService.toggleFavorite(
                question: message.relatedQuestion,
                answer: message.content,
                imageUrl: message.relatedImageUrl,
                type: type,
                subject: selectedQaSubject,
                sessionId: sessionId,
                alreadyActive: was > 0,
                existingId: was
            )
            await MainActor.run {
                if result.ok {
                    if type == "1" {
                        qaWrongId = result.active ? max(result.id, 1) : 0
                        presentToast(result.active ? "已加入错题本" : "已移出错题本")
                    } else {
                        qaFavoriteId = result.active ? max(result.id, 1) : 0
                        presentToast(result.active ? "已加入收藏" : "已取消收藏")
                    }
                } else {
                    if type == "1" {
                        qaWrongId = was
                        presentToast("加入错题本失败")
                    } else {
                        qaFavoriteId = was
                        presentToast("收藏失败")
                    }
                }
            }
        }
    }

    private var qaSubjectDialogs: some View {
        EmptyView()
            .alert("删除科目", isPresented: $showDeleteSubjectAlert) {
                Button("取消", role: .cancel) { subjectToDelete = nil }
                Button("删除", role: .destructive) {
                    if let name = subjectToDelete { deleteQaSubject(name) }
                    subjectToDelete = nil
                }
            } message: {
                Text("该科目不再出现在科目下拉里，会话记录本身不受影响。")
            }
            .alert("发现新科目", isPresented: $showNewSubjectAlert) {
                Button("加入科目表") {
                    if let name = newSubjectPrompt { acceptNewSubject(name) }
                }
                Button("归到已有科目") { showNewSubjectPicker = true }
                Button("跳过", role: .cancel) {
                    presentToast("已跳过，科目登记不受影响")
                    newSubjectPrompt = nil
                }
            } message: {
                Text("「\(newSubjectPrompt ?? "")」要加入答疑科目列表吗？")
            }
            .confirmationDialog("归到已有科目", isPresented: $showNewSubjectPicker, titleVisibility: .visible) {
                ForEach(qaMatchedSubjects.filter { $0 != "全部" && $0 != "未归类" }, id: \.self) { name in
                    Button(name) { reassignConversationSubject(name) }
                }
                Button("其他科目") { reassignConversationSubject("其他科目") }
                Button("取消", role: .cancel) { showNewSubjectPicker = false }
            }
    }

    private func createQaSubject(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let ok = await AcademicApi.addQaSubjectName(trimmed)
            await MainActor.run {
                if ok {
                    qaMatchedSubjects = QaSubjectTombstone.filter(
                        qaMatchedSubjects.contains(trimmed) ? qaMatchedSubjects : qaMatchedSubjects + [trimmed]
                    )
                    selectedQaSubject = trimmed
                    historySubjectFilter = trimmed
                    presentToast("会话记录中已加入「\(trimmed)」")
                } else {
                    presentToast("添加科目失败，请稍后重试")
                }
            }
        }
    }

    private func deleteQaSubject(_ name: String) {
        Task {
            let ok = await AcademicApi.removeQaSubjectName(name)
            await MainActor.run {
                if ok {
                    qaMatchedSubjects = QaSubjectTombstone.filter(qaMatchedSubjects.filter { $0 != name })
                    if selectedQaSubject == name { selectedQaSubject = "" }
                    if historySubjectFilter == name { historySubjectFilter = "全部" }
                } else {
                    presentToast("删除科目失败")
                }
            }
        }
    }

    private func acceptNewSubject(_ name: String) {
        guard apiService.token?.isEmpty == false else {
            newSubjectPrompt = nil
            onNeedLogin()
            return
        }
        Task {
            let ok = await AcademicApi.addQaSubjectName(name)
            await MainActor.run {
                if ok {
                    qaMatchedSubjects = QaSubjectTombstone.filter(
                        qaMatchedSubjects.contains(name) ? qaMatchedSubjects : qaMatchedSubjects + [name]
                    )
                    selectedQaSubject = name
                    historySubjectFilter = name
                    newSubjectPrompt = nil
                    showNewSubjectAlert = false
                    showNewSubjectPicker = false
                    presentToast("会话记录中已加入「\(name)」")
                } else {
                    presentToast("添加科目失败，请稍后重试")
                }
            }
            if ok {
                _ = await apiService.setConversationSubject(sessionId: sessionId, subject: name)
            }
        }
    }

    private func reassignConversationSubject(_ name: String) {
        selectedQaSubject = name
        historySubjectFilter = name
        newSubjectPrompt = nil
        showNewSubjectAlert = false
        showNewSubjectPicker = false
        presentToast("已归到「\(name)」")
        Task {
            _ = await apiService.setConversationSubject(sessionId: sessionId, subject: name)
        }
    }

    private func conversationTimeLine(_ chat: ConversationItem) -> String {
        if chat.startedAt > 0 { return QaHelpers.formatQaListTime(chat.startedAt) }
        return QaHelpers.formatQaListTime(chat.startedAtText)
    }
}

private struct QaHistoryDrawerView: View {
    let conversationList: [ConversationItem]
    let qaMatchedSubjects: [String]
    let historyLoading: Bool
    @Binding var historySubjectFilter: String
    var onClose: () -> Void
    var onSelect: (ConversationItem) -> Void
    var onDelete: (ConversationItem) -> Void
    var onCreateSubject: (String) -> Void
    var onDeleteSubject: (String) -> Void
    var onOpenHome: () -> Void
    var onOpenMine: () -> Void

    private var chips: [String] {
        QaHelpers.buildQaSubjectFilterList(
            registered: qaMatchedSubjects,
            extra: conversationList.map(\.subjectName)
        )
    }

    private var conversationCounts: [String: Int] {
        let concrete = chips.filter { $0 != "全部" && $0 != "其他科目" && $0 != "未归类" }
        var out: [String: Int] = ["全部": conversationList.count]
        for name in concrete {
            out[name] = conversationList.filter {
                QaHelpers.conversationMatchesQaSubject(subjectName: $0.subjectName, title: $0.title, filter: name)
            }.count
        }
        out["其他科目"] = conversationList.filter { item in
            !concrete.contains {
                QaHelpers.conversationMatchesQaSubject(subjectName: item.subjectName, title: item.title, filter: $0)
            }
        }.count
        return out
    }

    private var visible: [ConversationItem] {
        if historySubjectFilter == "全部" { return conversationList }
        let concrete = chips.filter { $0 != "全部" && $0 != "其他科目" && $0 != "未归类" }
        if historySubjectFilter == "其他科目" {
            return conversationList.filter { item in
                !concrete.contains {
                    QaHelpers.conversationMatchesQaSubject(subjectName: item.subjectName, title: item.title, filter: $0)
                }
            }
        }
        return conversationList.filter {
            QaHelpers.conversationMatchesQaSubject(
                subjectName: $0.subjectName,
                title: $0.title,
                filter: historySubjectFilter
            )
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.33)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                Text("会话记录")
                    .font(.system(size: 17))
                    .foregroundColor(Color(hex: "2D3748"))
                    .padding(.horizontal, 16)
                    .padding(.top, 12 + drawerSafeInsets.top)
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
                    Spacer(minLength: 0)
                } else {
                    chipRow
                    conversationRows
                }

                VStack(spacing: 0) {
                    Divider().background(Color(hex: "F2F4F7"))
                    HStack(spacing: 10) {
                        footerButton("首页", action: onOpenHome)
                        footerButton("我的", action: onOpenMine)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 14 + drawerSafeInsets.bottom)
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.82)
            .frame(maxHeight: .infinity)
            .background(Color.white)
            .clipShape(LeadingDrawerShape(radius: 22))
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .zIndex(10)
    }

    private var drawerSafeInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?.safeAreaInsets ?? UIEdgeInsets(top: 44, left: 0, bottom: 34, right: 0)
    }

    @ViewBuilder
    private var chipRow: some View {
        QaSubjectPicker(
            subjects: chips,
            selected: historySubjectFilter,
            counts: conversationCounts,
            otherDesc: "尚未归类的会话",
            onSelect: { historySubjectFilter = $0 },
            onCreate: onCreateSubject,
            onDelete: onDeleteSubject
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .zIndex(2)
    }

    @ViewBuilder
    private var conversationRows: some View {
        if visible.isEmpty {
            Text("暂无会话记录")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "94A3B8"))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Spacer(minLength: 0)
        } else {
            List {
                ForEach(visible) { chat in
                    Button(action: { onSelect(chat) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(QaHelpers.conversationTitleLine(chat, registered: qaMatchedSubjects))
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "2D3748"))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(timeLine(chat))
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "A0AEC0"))
                            }
                            Text(QaHelpers.conversationPreviewLine(chat))
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "A0AEC0"))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(chat)
                        } label: {
                            Text("删除")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
        }
    }

    private func timeLine(_ chat: ConversationItem) -> String {
        if chat.startedAt > 0 { return QaHelpers.formatQaListTime(chat.startedAt) }
        return QaHelpers.formatQaListTime(chat.startedAtText)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "00786C"))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(Color(hex: "E0FAF6")))
                .overlay(Capsule().stroke(Color(hex: "00DCC8"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct QaWelcomePanel: View {
    let loading: Bool
    let hasRegisteredSubjects: Bool
    var onOpenTimetable: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            if loading {
                ProgressView()
                    .padding(.top, 22)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("使用技巧")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "00786C"))
                    Text(hasRegisteredSubjects ? QaHelpers.welcomeHintPlus : QaHelpers.welcomeHintEmpty)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "334155"))
                        .lineSpacing(6)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "E0FAF6"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "00DCC8"), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                )
                .padding(.horizontal, 6)
                .padding(.top, 22)
                .padding(.bottom, 8)
                .onTapGesture {
                    if !hasRegisteredSubjects { onOpenTimetable() }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LeadingDrawerShape: Shape {
    var radius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}












