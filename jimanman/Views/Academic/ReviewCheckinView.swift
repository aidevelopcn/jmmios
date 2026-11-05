import SwiftUI
import UIKit

struct ReviewCheckinView: View {
    let onBack: () -> Void

    @State private var loading = true
    @State private var board: ReviewBoard?
    @State private var errorText = ""
    @State private var selectedDate = ""
    @State private var showDates = false
    @State private var sheetTask: ReviewTask?
    @State private var toast = ""

    var body: some View {
        ZStack {
            Color(hex: "F5F7F8").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(hex: "1A1F26"))
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("复习打卡")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "1A1F26"))
                    Spacer()
                    Button { showDates = true } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "1A1F26"))
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 6)

                if loading {
                    Spacer()
                    ProgressView().tint(Color(hex: "14C8B4"))
                    Spacer()
                } else if let board {
                    ScrollView(showsIndicators: false) {
                        ReviewBoardBody(board: board, onOpenTask: { key in
                            let task = board.groups.flatMap(\.tasks).first { $0.taskKey == key }
                            if let task, task.canCheckin {
                                sheetTask = task
                            } else if task != nil, !board.canCheckin {
                                toast = "这一天只能查看"
                            }
                        })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                } else {
                    Spacer()
                    Text(errorText.isEmpty ? "复习计划加载失败" : errorText)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "6B7280"))
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Spacer()
                }
            }
            if !toast.isEmpty {
                Text(toast)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(hex: "0F172A").opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 80)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .task { await reload("") }
        .sheet(isPresented: $showDates) {
            DatePicker(
                "选择日期",
                selection: Binding(
                    get: { dateFrom(selectedDate) },
                    set: { newDate in
                        showDates = false
                        Task { await reload(formatDate(newDate)) }
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
        }
        .overlay {
            if let task = sheetTask, let board {
                ReviewCheckinSheet(
                    task: task,
                    date: board.today,
                    onClose: { sheetTask = nil },
                    onDone: { text in
                        sheetTask = nil
                        toast = text
                        Task { await reload(board.today) }
                    }
                )
            }
        }
        .onChange(of: toast) { value in
            guard !value.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if toast == value { toast = "" }
            }
        }
    }

    private func reload(_ date: String) async {
        loading = board == nil
        let result = await AcademicApi.fetchReviewBoard(date: date)
        switch result {
        case .success(let data):
            board = data
            selectedDate = data.date
            errorText = ""
        case .failure(let error):
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func dateFrom(_ value: String) -> Date {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: value) ?? Date()
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

struct ReviewBoardBody: View {
    let board: ReviewBoard
    let onOpenTask: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            reviewHero
            if let alert = board.alert {
                alertBar(alert)
            }
            if board.summary.total > 0 {
                HStack {
                    Text("今日任务")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(Color(hex: "1A1F26"))
                    Text("\(board.summary.total)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Color(hex: "14C8B4"))
                        .clipShape(Capsule())
                    Spacer()
                    Text(board.dateLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color(hex: "00695A"))
                }
                ForEach(board.groups) { group in
                    groupCard(group)
                }
            } else if !board.hasPlan {
                emptyPlan
            }
            if !board.countdown.isEmpty {
                countdownCard
            }
        }
    }

    private var reviewHero: some View {
        let summary = board.summary
        let subline = summary.subline.contains("请联系教务老师") ? "" : summary.subline.trimmingCharacters(in: .whitespaces)
        let ink = Color(hex: "08352D")
        return VStack(alignment: .leading, spacing: 14) {
            Text("今日复习完成率")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ink.opacity(0.62))
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.42), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(summary.rate) / 100)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(summary.rate)%")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(ink)
                        Text("完成率")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ink.opacity(0.55))
                    }
                }
                .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.headline)
                        .font(.system(size: subline.isEmpty ? 20 : 16, weight: .bold))
                        .foregroundColor(ink)
                    if !subline.isEmpty {
                        Text(subline)
                            .font(.system(size: 13))
                            .foregroundColor(ink.opacity(0.72))
                    }
                }
            }
            HStack {
                stat("\(summary.done)", "已完成", warn: false)
                divider
                stat("\(summary.pending)", "待完成", warn: false)
                divider
                stat("\(summary.overdue)", "逾期", warn: summary.overdue > 0)
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(18)
        .background(
            ZStack {
                AcademicPalette.hero
                JmmHeroDecor()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: AcademicPalette.hero.opacity(0.42), radius: 18, y: 10)
    }

    private var divider: some View {
        Color(hex: "08352D").opacity(0.12).frame(width: 1, height: 28)
    }

    private func stat(_ value: String, _ label: String, warn: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(warn ? Color(hex: "B45309") : Color(hex: "08352D"))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "08352D").opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private func alertBar(_ alert: ReviewAlert) -> some View {
        HStack(spacing: 10) {
            Text("!")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color(hex: "F59E0B"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "7C2D12"))
                        .lineLimit(1)
                    if !alert.overdueLabel.isEmpty {
                        Text(alert.overdueLabel)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .background(Color(hex: "DC2626"))
                            .clipShape(Capsule())
                    }
                }
                Text(alert.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "9A3412"))
            }
            Spacer()
            Button("立即打卡") { onOpenTask(alert.taskKey) }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color(hex: "F59E0B"))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(hex: "FFF7ED"))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "FED7AA"), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func groupCard(_ group: ReviewGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: group.color.replacingOccurrences(of: "#", with: ""))).frame(width: 8, height: 8)
                Text(group.subjectName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "1A1F26"))
            }
            VStack(spacing: 0) {
                ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Color(hex: "EEF1F4").frame(height: 1)
                    }
                    taskRow(task)
                }
            }
            .padding(.horizontal, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
    }

    private func taskRow(_ task: ReviewTask) -> some View {
        let label = task.done ? "已打卡" : (task.canCheckin ? "打卡" : "未打卡")
        let bg: Color = task.done ? Color(hex: "14C8B4").opacity(0.12) : (task.canCheckin ? Color(hex: "14C8B4") : Color(hex: "F3F4F6"))
        let fg: Color = task.done ? Color(hex: "00695A") : (task.canCheckin ? .white : Color(hex: "9CA3AF"))
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(Color(hex: "1A1F26"))
                    if !task.overdueLabel.isEmpty {
                        Text(task.overdueLabel)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .background(Color(hex: "DC2626"))
                            .clipShape(Capsule())
                    }
                }
                if !task.meta.isEmpty {
                    Text(task.meta)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "6B7280"))
                }
            }
            Spacer()
            Button(task.done ? "✓ \(label)" : label) { onOpenTask(task.taskKey) }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(fg)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(bg)
                .clipShape(Capsule())
                .disabled(!task.canCheckin && !task.done)
        }
        .padding(.vertical, 11)
    }

    private var emptyPlan: some View {
        VStack(spacing: 8) {
            Text("还没有复习计划")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "1A1F26"))
            Text("请联系教务老师为你生成复习计划后再来打卡")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "6B7280"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("学完倒计时")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundColor(Color(hex: "1A1F26"))
            ForEach(board.countdown) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.subjectName)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(item.statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "14C8B4"))
                    }
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "6B7280"))
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ReviewCheckinSheet: View {
    let task: ReviewTask
    let date: String
    let onClose: () -> Void
    let onDone: (String) -> Void

    @State private var doneAmount: String
    @State private var minutes: String
    @State private var note = ""
    @State private var makeup: Bool
    @State private var photos: [String] = []
    @State private var submitting = false
    @State private var uploading = false
    @State private var localError = ""
    @State private var keyboardInset: CGFloat = 0
    @State private var showImagePicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedImage: UIImage?

    init(task: ReviewTask, date: String, onClose: @escaping () -> Void, onDone: @escaping (String) -> Void) {
        self.task = task
        self.date = date
        self.onClose = onClose
        self.onDone = onDone
        _doneAmount = State(initialValue: task.doneAmount > 0 ? String(task.doneAmount) : (task.target > 0 ? String(task.target) : ""))
        _minutes = State(initialValue: task.minutes > 0 ? String(task.minutes) : "")
        _makeup = State(initialValue: task.overdue)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(task.title)
                                .font(.system(size: 15, weight: .bold))
                            if task.overdue {
                                Text("逾期 1 天")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: "EF4444"))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("今日应完成 \(task.target) \(task.unit)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "6B7280"))
                    }
                    Spacer()
                    Button("✕", action: onClose).foregroundColor(Color(hex: "6B7280"))
                }
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        if task.overdue {
                            Button { makeup.toggle() } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: makeup ? "checkmark.square.fill" : "square")
                                        .foregroundColor(Color(hex: "D97706"))
                                    Text("补卡标记 · 已逾期 1 天，24h 内补卡仍计入按时完成")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "7C2D12"))
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(Color(hex: "FFF7ED"))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(hex: "FED7AA"), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)
                        }
                        labeledField("已完成量", "默认 = 今日应完成量", $doneAmount, task.unit)
                        labeledField("实际用时", "手填 · 自报", $minutes, "分钟")
                        HStack {
                            Text("拍照凭证").font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text("选填，≤ 3 张").font(.system(size: 11)).foregroundColor(Color(hex: "9CA3AF"))
                        }
                        photoRow
                        if photos.count < 3 {
                            Button("从相册选") {
                                pickerSource = .photoLibrary
                                showImagePicker = true
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "0F766E"))
                            .disabled(uploading)
                        }
                        HStack {
                            Text("备注").font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text("选填，100 字内").font(.system(size: 11)).foregroundColor(Color(hex: "9CA3AF"))
                        }
                        TextField("例如：这一章的应用题比较吃力，明天再过一遍例题", text: $note)
                            .font(.system(size: 13))
                            .padding(10)
                            .frame(minHeight: 64, alignment: .top)
                            .background(Color(hex: "FAFBFC"))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "DDE0E4"), lineWidth: 1))
                            .onChange(of: note) { value in
                                if value.count > 100 { note = String(value.prefix(100)) }
                            }
                        if !localError.isEmpty {
                            Text(localError).font(.system(size: 12)).foregroundColor(Color(hex: "DC2626"))
                        }
                    }
                }

                Button(submitting ? "提交中" : "确认打卡") { submit() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: "14C8B4"))
                    .clipShape(Capsule())
                    .disabled(submitting || uploading)
                    .padding(.top, 12)
                Button("下次再说", action: onClose)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "6B7280"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(18)
            .padding(.bottom, keyboardInset)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .animation(.easeOut(duration: 0.22), value: keyboardInset)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $pickedImage, sourceType: pickerSource)
        }
        .onChange(of: pickedImage) { image in
            guard let image else { return }
            pickedImage = nil
            uploadPhoto(image)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboardInset = KeyboardOverlap.from(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardInset = 0
        }
    }

    private var photoRow: some View {
        HStack(spacing: 8) {
            ForEach(photos, id: \.self) { url in
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color(hex: "E5E7EB")
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    Button {
                        photos.removeAll { $0 == url }
                    } label: {
                        Text("×")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color(hex: "111827")))
                    }
                    .offset(x: 4, y: -4)
                }
            }
            if photos.count < 3 {
                Button {
                    pickerSource = .camera
                    showImagePicker = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "camera")
                        Text(uploading ? "…" : "拍照")
                            .font(.system(size: 10.5))
                    }
                    .foregroundColor(Color(hex: "6B7280"))
                    .frame(width: 60, height: 60)
                    .background(Color(hex: "FAFBFC"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(Color(hex: "D0D5DD"), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                }
                .buttonStyle(.plain)
                .disabled(uploading)
            }
            Spacer(minLength: 0)
        }
    }

    private func labeledField(_ title: String, _ hint: String, _ text: Binding<String>, _ suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .bold))
                Spacer()
                Text(hint).font(.system(size: 11)).foregroundColor(Color(hex: "9CA3AF"))
            }
            HStack {
                TextField("0", text: text).keyboardType(.numberPad)
                Text(suffix).font(.system(size: 12)).foregroundColor(Color(hex: "6B7280"))
            }
            .padding(12)
            .background(Color(hex: "FAFBFC"))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "DDE0E4"), lineWidth: 1.5))
        }
    }

    private func uploadPhoto(_ image: UIImage) {
        guard photos.count < 3 else {
            localError = "最多 3 张"
            return
        }
        uploading = true
        Task {
            let url = await AcademicApi.uploadImage(image)
            await MainActor.run {
                uploading = false
                if let url, !url.isEmpty {
                    photos.append(url)
                    localError = ""
                } else {
                    localError = "上传失败"
                }
            }
        }
    }

    private func submit() {
        submitting = true
        localError = ""
        let amount = Int(doneAmount) ?? task.target
        let used = Int(minutes) ?? 0
        let isMakeup = makeup && task.overdue
        Task {
            let result = await AcademicApi.submitReviewCheckin(
                date: date,
                task: task,
                doneAmount: amount,
                minutes: used,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                photos: photos,
                makeup: isMakeup
            )
            await MainActor.run {
                submitting = false
                switch result {
                case .success:
                    let extra = isMakeup ? "（补卡）" : ""
                    onDone("已打卡 · \(amount) / \(used)分钟\(extra) ✓")
                case .failure(let error):
                    localError = error.localizedDescription
                }
            }
        }
    }
}
