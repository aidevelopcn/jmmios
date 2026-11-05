import SwiftUI
import AVFoundation

// MARK: - 我的答疑列表（对齐 Android MyAskListScreen）
struct MyAskListView: View {
    let onBack: () -> Void
    let onNeedLogin: () -> Void
    var onOpenTimetable: (() -> Void)? = nil

    @StateObject private var apiService = ApiService.shared
    @AppStorage("jmm_ask_last_tab") private var storedTab = 0
    @State private var currentTab = 0
    @State private var wrongBookList: [AskRecordItem] = []
    @State private var favoriteList: [AskRecordItem] = []
    @State private var conversationList: [ConversationItem] = []
    @State private var registeredSubjects: [String] = []
    @State private var subjectHint: QaSubjectHint?
    @State private var subjectFilter = "全部"
    @State private var loading = false
    @State private var previewURL = ""
    @State private var showImagePreview = false
    @State private var detailItem: AskRecordItem?
    @State private var showCameraOverlay = false
    @State private var showAlbumPicker = false
    @State private var showCropDialog = false
    @State private var cropFromCamera = false
    @State private var cropSourceImage: UIImage?
    @State private var uploading = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var deletingId: String?
    @State private var subjectToDelete: String?
    @State private var masteringId: String?
    @State private var recordToReassign: AskRecordItem?
    @State private var detailLoadFailed = false

    private let subjectActive = Color(hex: "4ECDC4")

    var body: some View {
        ProfileScreenScaffold(background: AppColors.background) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "拾错藏珍", onBack: onBack, barBackground: .clear)

                if (apiService.token ?? "").isEmpty {
                    Spacer(minLength: 0)
                    Text("请先登录")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "6B7280"))
                        .onTapGesture { onNeedLogin() }
                    Spacer(minLength: 0)
                } else {
                    segmentBar
                    subjectFilterBar
                    timetableHint
                    contentArea
                    if currentTab == 0 {
                        uploadBar
                    }
                }
            }
        }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
        .alert("删除科目", isPresented: Binding(
            get: { subjectToDelete != nil },
            set: { if !$0 { subjectToDelete = nil } }
        )) {
            Button("取消", role: .cancel) { subjectToDelete = nil }
            Button("删除", role: .destructive) {
                if let name = subjectToDelete { deleteSubject(name) }
                subjectToDelete = nil
            }
        } message: {
            Text("该科目不再出现在科目下拉里，错题本和收藏记录本身不受影响。")
        }
        .confirmationDialog("归到科目", isPresented: Binding(
            get: { recordToReassign != nil },
            set: { if !$0 { recordToReassign = nil } }
        ), titleVisibility: .visible) {
            ForEach(filterSubjects.filter { $0 != "全部" }, id: \.self) { name in
                Button(name) {
                    if let record = recordToReassign { reassignAskRecord(record, name) }
                }
            }
            Button("取消", role: .cancel) { recordToReassign = nil }
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
                onImageCaptured: { image, _ in
                    showCameraOverlay = false
                    cropFromCamera = true
                    cropSourceImage = image
                    showCropDialog = true
                },
                onCaptureFailed: { message in
                    toastMessage = message
                    showToast = true
                }
            )
        }
        .sheet(isPresented: $showAlbumPicker) {
            ChatAlbumPicker(image: Binding(
                get: { nil },
                set: { image in
                    if let image {
                        cropFromCamera = false
                        cropSourceImage = image
                        showCropDialog = true
                    }
                }
            ))
        }
        .overlay {
            if showCropDialog, let image = cropSourceImage {
                ImageCropDialogView(
                    sourceImage: image,
                    initialRatio: nil,
                    allowRetake: true,
                    retakeLabel: cropFromCamera ? "重拍" : "重选",
                    onRetake: {
                        let fromCamera = cropFromCamera
                        showCropDialog = false
                        cropSourceImage = nil
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
                        cropFromCamera = false
                    },
                    onConfirm: { cropped in
                        showCropDialog = false
                        cropSourceImage = nil
                        cropFromCamera = false
                        uploadWrongBookImage(cropped)
                    }
                )
            }
        }
        .overlay { imagePreviewOverlay }
        .overlay { detailOverlay }
        .onAppear {
            currentTab = storedTab == 1 ? 1 : 0
            bootstrap()
            reload(tab: currentTab)
        }
        .onChange(of: currentTab) { tab in
            storedTab = tab
            reload(tab: tab)
        }
        .onChange(of: detailItem?.id) { _ in
            hydrateFavoriteDetail()
        }
    }

    private var filterSubjects: [String] {
        QaHelpers.buildQaSubjectFilterList(
            registered: registeredSubjects.isEmpty ? (subjectHint?.subjects ?? []) : registeredSubjects,
            extra: conversationList.map(\.subjectName)
        )
    }

    private var filteredList: [AskRecordItem] {
        let raw = currentTab == 0 ? wrongBookList : favoriteList
        if subjectFilter == "全部" { return raw }
        let concrete = filterSubjects.filter { $0 != "全部" && $0 != "其他科目" && $0 != "未归类" }
        if subjectFilter == "其他科目" {
            return raw.filter { item in
                !concrete.contains { name in
                    QaHelpers.conversationMatchesQaSubject(subjectName: item.subjectName, title: item.title, filter: name)
                }
            }
        }
        return raw.filter { item in
            QaHelpers.conversationMatchesQaSubject(subjectName: item.subjectName, title: item.title, filter: subjectFilter)
                || item.questionText.contains(subjectFilter)
                || item.answerText.contains(subjectFilter)
        }
    }

    private var recordCounts: [String: Int] {
        let raw = currentTab == 0 ? wrongBookList : favoriteList
        let concrete = filterSubjects.filter { $0 != "全部" && $0 != "其他科目" && $0 != "未归类" }
        var out: [String: Int] = ["全部": raw.count]
        for name in concrete {
            out[name] = raw.filter { item in
                QaHelpers.conversationMatchesQaSubject(subjectName: item.subjectName, title: item.title, filter: name)
                    || item.questionText.contains(name)
                    || item.answerText.contains(name)
            }.count
        }
        out["其他科目"] = raw.filter { item in
            !concrete.contains { name in
                QaHelpers.conversationMatchesQaSubject(subjectName: item.subjectName, title: item.title, filter: name)
            }
        }.count
        return out
    }

    private var segmentBar: some View {
        AcademicSegmentControl(
            options: ["错题本", "我的收藏"],
            selectedIndex: currentTab,
            onSelect: { currentTab = $0 }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    @ViewBuilder
    private var subjectFilterBar: some View {
        QaSubjectPicker(
            subjects: filterSubjects,
            selected: subjectFilter,
            counts: recordCounts,
            otherDesc: "尚未归类的记录",
            onSelect: { subjectFilter = $0 },
            onCreate: { createSubjectAndSelect($0) },
            onDelete: { subjectToDelete = $0 }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white)
        .zIndex(2)
    }

    @ViewBuilder
    private var timetableHint: some View {
        if let hint = subjectHint, hint.status == "no_timetable", hint.subjects.isEmpty {
            Text(hint.message.isEmpty ? "请先登记科目再发起答疑，方便按科目留存你的答疑记录。" : hint.message)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "00AFA4"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white)
                .onTapGesture {
                    if onOpenTimetable != nil { onOpenTimetable?() }
                }
        }
    }

    private var uploadBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: openWrongBookCamera) {
                Text(uploading ? "上传中..." : "上传错题")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(uploading ? Color(hex: "9CA3AF") : subjectActive))
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
        } else if filteredList.isEmpty {
            Spacer(minLength: 0)
            Text(currentTab == 0 ? "暂无错题记录" : "暂无收藏记录")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "94A3B8"))
            Spacer(minLength: 0)
        } else {
            List {
                ForEach(filteredList) { item in
                    askRecordCard(item: item)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .background(AppColors.background)
            .modifier(HiddenListBackground())
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
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            AskRecordDetailView(
                item: item,
                conversations: conversationList,
                registered: registeredSubjects,
                canMaster: currentTab == 0,
                mastering: masteringId == item.id,
                detailLoadFailed: detailLoadFailed,
                onBack: { if masteringId == nil { detailItem = nil } },
                onPreviewImage: { url in
                    previewURL = url
                    showImagePreview = true
                },
                onMaster: { applyMastered(item, $0) }
            )
            .background(Color(hex: "F5F7FA"))
        }
    }

    private func askRecordCard(item: AskRecordItem) -> some View {
        let photoUpload = currentTab == 0 && QaHelpers.isWrongBookCameraUpload(item)
        let subject = QaHelpers.askRecordSubjectLine(item, conversations: conversationList, registered: registeredSubjects)
        let title = QaHelpers.askRecordHeadline(item, conversations: conversationList, registered: registeredSubjects)
        let itemTime = QaHelpers.formatQaListTime(item.timeText)
        let done = currentTab == 0 && item.mastered
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if !subject.isEmpty {
                    Text(subject)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "0F766E"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "EEFAFA"))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                if !itemTime.isEmpty {
                    Text(itemTime)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "6B7280"))
                        .lineLimit(1)
                }
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(done ? Color(hex: "6B7280") : Color(hex: "1A1F26"))
                .lineLimit(2)
            HStack {
                if currentTab == 0 {
                    askStatusPill(item.mastered)
                }
                Spacer(minLength: 0)
                Button(action: { detailItem = item }) {
                    Text(photoUpload ? "查看照片" : "查看解析")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(done ? Color(hex: "FBFCFC") : Color.white))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                recordToReassign = item
            } label: {
                Text("归类")
            }
            .tint(Color(hex: "00AFA4"))
            Button(role: .destructive) {
                deleteRecord(item)
            } label: {
                Text(currentTab == 0 ? "移出" : "取消")
            }
            .disabled(deletingId != nil)
        }
    }

    private func askStatusPill(_ mastered: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(mastered ? Color(hex: "00AFA4") : Color(hex: "F59E0B"))
                .frame(width: 5, height: 5)
            Text(mastered ? "已掌握" : "待复习")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(mastered ? Color(hex: "3FBFB5") : Color(hex: "B45309"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(mastered ? Color(hex: "EEFAFA") : Color(hex: "FFF7E6")))
    }

    private func createSubjectAndSelect(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let ok = await AcademicApi.addQaSubjectName(trimmed)
            await MainActor.run {
                if ok {
                    registeredSubjects = QaSubjectTombstone.filter(
                        registeredSubjects.contains(trimmed) ? registeredSubjects : registeredSubjects + [trimmed]
                    )
                    subjectFilter = trimmed
                } else {
                    toastMessage = "添加科目失败，请稍后重试"
                    showToast = true
                }
            }
        }
    }

    private func deleteSubject(_ name: String) {
        Task {
            let ok = await AcademicApi.removeQaSubjectName(name)
            await MainActor.run {
                if ok {
                    registeredSubjects = QaSubjectTombstone.filter(registeredSubjects.filter { $0 != name })
                    if subjectFilter == name { subjectFilter = "全部" }
                } else {
                    toastMessage = "删除科目失败"
                    showToast = true
                }
            }
        }
    }

    private func bootstrap() {
        guard let token = apiService.token, !token.isEmpty else { return }
        Task {
            async let hint = AcademicApi.fetchQaSubjectHint()
            async let chats = ApiService.shared.fetchConversationList()
            let fetchedHint = await hint
            let extra = (fetchedHint?.subjects ?? []) + (fetchedHint?.unmatched ?? [])
            let subjects = await AcademicApi.loadSortedQaSubjectNames(extra: extra)
            let fetchedChats = await chats
            await MainActor.run {
                subjectHint = fetchedHint
                registeredSubjects = subjects
                conversationList = fetchedChats
            }
        }
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
                if let open = detailItem, let fresh = list.first(where: { $0.id == open.id }) {
                    if !fresh.previewOnly || open.answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailItem = fresh
                    }
                }
                loading = false
            }
        }
    }

    private func hydrateFavoriteDetail() {
        guard let current = detailItem else {
            detailLoadFailed = false
            return
        }
        if !current.previewOnly {
            detailLoadFailed = false
            return
        }
        if QaHelpers.isWrongBookCameraUpload(current) { return }
        detailLoadFailed = false
        let currentId = current.id
        Task {
            let full = await ApiService.shared.fetchFavoriteDetail(id: currentId)
            await MainActor.run {
                guard detailItem?.id == currentId else { return }
                guard let full else {
                    detailLoadFailed = true
                    return
                }
                detailItem = full
                if currentTab == 0 {
                    wrongBookList = wrongBookList.map { $0.id == full.id ? full : $0 }
                } else {
                    favoriteList = favoriteList.map { $0.id == full.id ? full : $0 }
                }
            }
        }
    }

    private func openWrongBookCamera() {
        guard apiService.token != nil else {
            onNeedLogin()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraOverlay = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCameraOverlay = true }
                    else {
                        toastMessage = "未开启相机权限"
                        showToast = true
                    }
                }
            }
        default:
            toastMessage = "未开启相机权限"
            showToast = true
        }
    }

    private func patchRecord(id: String, _ transform: (inout AskRecordItem) -> Void) {
        if let idx = wrongBookList.firstIndex(where: { $0.id == id }) {
            transform(&wrongBookList[idx])
            if detailItem?.id == id { detailItem = wrongBookList[idx] }
        }
        if let idx = favoriteList.firstIndex(where: { $0.id == id }) {
            transform(&favoriteList[idx])
            if detailItem?.id == id { detailItem = favoriteList[idx] }
        }
    }

    private func applyMastered(_ item: AskRecordItem, _ mastered: Bool) {
        guard let recordId = Int(item.id), recordId > 0 else {
            toastMessage = "该记录缺少 ID，已为你刷新，请重试"
            showToast = true
            reload(tab: currentTab)
            return
        }
        guard apiService.token != nil else {
            onNeedLogin()
            return
        }
        if masteringId != nil { return }
        masteringId = item.id
        Task {
            let result = await apiService.setFavoriteMastered(id: recordId, mastered: mastered)
            await MainActor.run {
                masteringId = nil
                if result.ok {
                    patchRecord(id: item.id) { $0.mastered = mastered }
                    toastMessage = mastered ? "已标记为已掌握" : "已撤销，回到待复习"
                } else {
                    toastMessage = result.message
                }
                showToast = true
            }
        }
    }

    private func reassignAskRecord(_ item: AskRecordItem, _ rawName: String) {
        guard let recordId = Int(item.id), recordId > 0 else {
            toastMessage = "该记录缺少 ID，已为你刷新，请重试"
            showToast = true
            recordToReassign = nil
            reload(tab: currentTab)
            return
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = (name.isEmpty || name == "其他科目" || name == "未归类") ? "" : name
        recordToReassign = nil
        Task {
            let result = await apiService.setFavoriteSubject(id: recordId, subject: payload.isEmpty ? "其他科目" : payload)
            await MainActor.run {
                if result.ok {
                    let stored = result.subject
                    patchRecord(id: item.id) { $0.subjectName = stored }
                    conversationList = conversationList.map { chat in
                        let hit = (!item.conversationId.isEmpty && chat.id == item.conversationId)
                            || (!item.sessionId.isEmpty && chat.sessionId == item.sessionId)
                        guard hit else { return chat }
                        return ConversationItem(
                            id: chat.id,
                            title: chat.title,
                            messageCount: chat.messageCount,
                            sessionId: chat.sessionId,
                            agentId: chat.agentId,
                            subjectName: stored,
                            knowledgePoint: chat.knowledgePoint,
                            agentName: chat.agentName,
                            startedAt: chat.startedAt,
                            startedAtText: chat.startedAtText,
                            preview: chat.preview,
                            hasImage: chat.hasImage
                        )
                    }
                    toastMessage = "已归类到「\(stored.isEmpty ? "其他科目" : stored)」"
                } else {
                    toastMessage = result.message
                }
                showToast = true
            }
        }
    }

    private func deleteRecord(_ item: AskRecordItem) {
        guard let id = Int(item.id), id > 0 else {
            toastMessage = "删除失败"
            showToast = true
            return
        }
        deletingId = item.id
        Task {
            let ok = await ApiService.shared.deleteFavorite(id: id)
            await MainActor.run {
                deletingId = nil
                if ok {
                    if currentTab == 0 {
                        wrongBookList.removeAll { $0.id == item.id }
                    } else {
                        favoriteList.removeAll { $0.id == item.id }
                    }
                    if detailItem?.id == item.id { detailItem = nil }
                    toastMessage = currentTab == 0 ? "已移出错题本" : "已取消收藏"
                } else {
                    toastMessage = "删除失败"
                }
                showToast = true
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
                if ok {
                    subjectFilter = "全部"
                    reload(tab: 0)
                }
            }
        }
    }
}

private struct AskRecordDetailView: View {
    let item: AskRecordItem
    let conversations: [ConversationItem]
    let registered: [String]
    let canMaster: Bool
    let mastering: Bool
    var detailLoadFailed: Bool = false
    let onBack: () -> Void
    let onPreviewImage: (String) -> Void
    let onMaster: (Bool) -> Void

    @State private var questionHeight: CGFloat = 80
    @State private var answerHeight: CGFloat = 80

    private var questionShown: String {
        let text = item.questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return QaHelpers.isQaImagePlaceholder(text) ? "" : text
    }

    private var linkedChat: ConversationItem? {
        conversations.first { chat in
            (!item.conversationId.isEmpty && chat.id == item.conversationId) ||
            (!item.sessionId.isEmpty && chat.sessionId == item.sessionId)
        }
    }

    private var detailSubject: String {
        QaHelpers.askRecordSubjectLine(item, conversations: conversations, registered: registered)
    }

    private var detailKnowledge: String {
        var knowledge = QaHelpers.sanitizeQaKnowledgeName(item.knowledgePoint)
        if knowledge.isEmpty {
            knowledge = QaHelpers.sanitizeQaKnowledgeName(linkedChat?.knowledgePoint ?? "")
        }
        return knowledge
    }

    var body: some View {
        ProfileScreenScaffold(background: Color(hex: "F5F7FA")) {
        VStack(spacing: 0) {
            ProfileSimpleTopBar(title: "答疑详情", onBack: onBack)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    let detailTime = QaHelpers.formatQaListTime(item.timeText)
                    if !detailTime.isEmpty {
                        Text(detailTime)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "94A3B8"))
                        Spacer().frame(height: 6)
                    }
                    if !detailSubject.isEmpty {
                        detailField("科目", detailSubject)
                        Spacer().frame(height: 6)
                    }
                    if !detailKnowledge.isEmpty {
                        detailField("知识点", detailKnowledge)
                        Spacer().frame(height: 6)
                    }
                    if !questionShown.isEmpty {
                        Text("题目")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "334155"))
                        Spacer().frame(height: 4)
                        askRichText(id: "ask-q-\(item.id)", content: questionShown, height: $questionHeight)
                        Spacer().frame(height: 10)
                    }
                    if !item.imageUrl.isEmpty {
                        AskNetworkImage(urlString: item.imageUrl, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { onPreviewImage(AskMediaURL.normalize(item.imageUrl)) }
                        Spacer().frame(height: 10)
                    }
                    if !item.answerText.isEmpty {
                        Text("解答")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "334155"))
                        Spacer().frame(height: 4)
                        askRichText(id: "ask-a-\(item.id)", content: item.answerText, height: $answerHeight)
                    } else if item.previewOnly && !QaHelpers.isWrongBookCameraUpload(item) {
                        Text("解答")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "334155"))
                        Spacer().frame(height: 4)
                        Text(detailLoadFailed ? "解答加载失败，请返回后重试" : "正在加载解答…")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "6B7280"))
                    }
                    Spacer().frame(height: 18)
                    Text("本内容由AI生成")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "6B7280"))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            if canMaster {
                askMasterBar
            }
        }
        }
    }

    private func detailField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "6B7280"))
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "1A1F26"))
            Spacer(minLength: 0)
        }
    }

    private var askMasterBar: some View {
        HStack(spacing: 10) {
            if item.mastered {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("已掌握")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(Color(hex: "15803D"))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color(hex: "E8F8EE"))
                .clipShape(Capsule())
                Button("撤销") { onMaster(false) }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(mastering ? Color(hex: "9CA3AF") : Color(hex: "6B7280"))
                    .disabled(mastering)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                Button(action: { onMaster(true) }) {
                    HStack(spacing: 7) {
                        if mastering {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(mastering ? "处理中..." : "标记为已掌握")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(mastering ? Color(hex: "7FD6D0") : Color(hex: "35BDB4"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(mastering)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color.white)
        .overlay(Divider(), alignment: .top)
    }

    @ViewBuilder
    private func askRichText(id: String, content: String, height: Binding<CGFloat>) -> some View {
        if MathHTMLBuilder.needsRichRendering(content) {
            MarkdownMathBubbleView(messageId: id, content: content, isStreaming: false, height: height)
                .frame(minHeight: 64, idealHeight: max(64, height.wrappedValue))
                .frame(height: max(64, height.wrappedValue))
        } else {
            Text(content)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "0F172A"))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AskNetworkImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: URL(string: AskMediaURL.normalize(urlString))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Rectangle().fill(Color(hex: "E0E0E0"))
            default:
                Rectangle()
                    .fill(Color(hex: "E0E0E0"))
                    .overlay(Text("加载中").font(.system(size: 12)).foregroundColor(Color(hex: "999999")))
            }
        }
    }
}

private struct HiddenListBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

private enum AskMediaURL {
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        text = text.replacingOccurrences(of: "(?<!:)/{2,}", with: "/", options: .regularExpression)
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return text }
        if text.hasPrefix("/") { return ApiConfig.baseURL + text }
        return text
    }
}
