import SwiftUI
import UIKit

// MARK: - 首页（对齐 Android HomeScreen）
struct HomeView: View {
    let onOpenSubjectRegister: () -> Void
    let onOpenGpa: () -> Void
    let onOpenGradeTarget: () -> Void
    let onOpenAssessment: () -> Void
    let onOpenAiChat: () -> Void
    let onOpenMyAsk: () -> Void
    let onOpenCourse: () -> Void
    let onOpenPoliticsQuiz: () -> Void
    let onOpenReviewPlan: () -> Void
    var reloadTrigger: Int = 0

    @EnvironmentObject private var session: AcademicSession
    @State private var bannerURLs: [String] = HomeSnapshotStore.banners
    @State private var bannerAspects: [CGFloat] = HomeSnapshotStore.bannerAspects
    @State private var currentBannerIndex = 0
    @State private var gradeGoals: [HomeGradeGoalItem] = HomeSnapshotStore.gradeGoals
    @State private var showAllGoals = false
    @State private var reviewBoard: ReviewBoard? = HomeSnapshotStore.reviewBoard
    private let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    private var featureItems: [(title: String, icon: String)] {
        [
            ("科目登记", "icon_01"),
            ("GPA计算", "icon_06"),
            ("成绩目标", "icon_02"),
            ("拾错藏珍", "icon_05"),
            ("能力测试", "icon_08"),
            ("我的课程", "icon_07"),
            ("快速答疑", "icon_04"),
            ("复习打卡", "icon_03"),
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("绩满满")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "111111"))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if let board = reviewBoard {
                    ReviewBoardBody(board: board, onOpenTask: { _ in onOpenReviewPlan() })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if !bannerURLs.isEmpty {
                    bannerSection
                    Spacer().frame(height: 20)
                }

                menuGridSection
                Spacer().frame(height: 20)
                gradeGoalsCard
                Spacer().frame(height: 24)
            }
        }
        .background(Color(hex: "F5F7FA"))
        .onAppear {
            applyBannerSnapshot()
            reloadHome()
        }
        .onChange(of: reloadTrigger) { _ in reloadHome() }
        .onReceive(timer) { _ in
            guard bannerURLs.count > 1 else { return }
            currentBannerIndex = (currentBannerIndex + 1) % bannerURLs.count
        }
    }

    private var currentBannerAspect: CGFloat {
        if bannerAspects.indices.contains(currentBannerIndex), bannerAspects[currentBannerIndex] > 0 {
            return bannerAspects[currentBannerIndex]
        }
        return bannerURLs.isEmpty ? 0 : 2.34375
    }

    private var bannerSection: some View {
        Color.clear
            .aspectRatio(currentBannerAspect, contentMode: .fit)
            .overlay(
                ZStack(alignment: .bottom) {
                    TabView(selection: $currentBannerIndex) {
                        ForEach(bannerURLs.indices, id: \.self) { index in
                            HomeBannerImage(urlString: bannerURLs[index])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                    HStack(spacing: 5) {
                        ForEach(bannerURLs.indices, id: \.self) { index in
                            Capsule()
                                .fill(Color.white.opacity(index == currentBannerIndex ? 1 : 0.45))
                                .frame(width: index == currentBannerIndex ? 16 : 5, height: 5)
                        }
                    }
                    .padding(.bottom, 10)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color(hex: "1DB8B5").opacity(0.16), radius: 14, x: 0, y: 6)
            .padding(.horizontal, 16)
    }

    private var menuGridSection: some View {
        VStack(spacing: 16) {
            ForEach(0..<((featureItems.count + 3) / 4), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        featureCell(at: row * 4 + col)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func featureCell(at index: Int) -> some View {
        if index < featureItems.count {
            Button(action: { openFeature(featureItems[index].title) }) {
                VStack(spacing: 6) {
                    Image(featureItems[index].icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    Text(featureItems[index].title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "2D3748"))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    private var gradeGoalsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color(hex: "35BDB4"))
                    .frame(width: 4, height: 17)
                    .shadow(color: Color(hex: "4ECDC4").opacity(0.45), radius: 2, y: 1)
                Text("各科成绩目标")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "1A1F26"))
                Spacer()
                Button(action: onOpenGradeTarget) {
                    HStack(spacing: 3) {
                        Text("设置目标")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(hex: "4B5563"))
                        Text("›")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "9CA3AF"))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "0F172A").opacity(0.07), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 13)

            if gradeGoals.isEmpty {
                Button(action: onOpenGradeTarget) {
                    VStack(spacing: 6) {
                        Text("暂无科目")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "1A1F26"))
                        Text("完成科目登记或在成绩目标中添加科目后，这里会显示各科目标")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "9AA3AF"))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array((showAllGoals ? gradeGoals : Array(gradeGoals.prefix(6))).enumerated()), id: \.element.id) { index, goal in
                        HStack(spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(goal.name)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundColor(Color(hex: "1A1F26"))
                                    .lineLimit(1)
                                if !goal.credit.isEmpty {
                                    Text(goal.credit)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "8A94A0"))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            Text(goal.scored ? "出分 \(goal.goal)" : "目标 \(goal.goal)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color(hex: "3FBFB5"))
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(Color(hex: "EEFAFA"))
                                .overlay(Capsule().stroke(Color(hex: "4ECDC4").opacity(0.4), lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .frame(minHeight: 52)
                        .padding(.horizontal, 16)
                        if index != (showAllGoals ? gradeGoals.count : min(6, gradeGoals.count)) - 1 {
                            Color(hex: "0F172A").opacity(0.05).frame(height: 1).padding(.horizontal, 16)
                        }
                    }
                    if !showAllGoals && gradeGoals.count > 6 {
                        Button("查看更多") { showAllGoals = true }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "4ECDC4"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 5)
            }
        }
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "0F172A").opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(hex: "0F172A").opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private func openFeature(_ title: String) {
        switch title {
        case "科目登记": onOpenSubjectRegister()
        case "GPA计算": onOpenGpa()
        case "成绩目标": onOpenGradeTarget()
        case "能力测试": onOpenAssessment()
        case "拾错藏珍": onOpenMyAsk()
        case "快速答疑": onOpenAiChat()
        case "我的课程": onOpenCourse()
        case "复习打卡": onOpenReviewPlan()
        default: break
        }
    }

    private func reloadHome() {
        applyBannerSnapshot()
        let hint = AcademicCalc.inferGpaSemesterCode(session.schoolyear)
        let semesterHint = hint.isEmpty ? session.semester : hint
        let loggedIn = !(ApiService.shared.token ?? "").isEmpty
        Task {
            async let bannersTask = HomeSnapshotStore.refreshBanners()
            async let goals = AcademicHomeService.loadGradeGoals(semesterHint: semesterHint)
            let urls = await bannersTask
            await MainActor.run {
                if let urls {
                    bannerURLs = urls
                    bannerAspects = HomeSnapshotStore.bannerAspects
                    if currentBannerIndex >= max(urls.count, 1) { currentBannerIndex = 0 }
                }
            }
            let items = await goals
            var review: ReviewBoard?
            if loggedIn, case .success(let value) = await AcademicApi.fetchReviewBoard() {
                review = value.hasPlan ? value : nil
            }
            await MainActor.run {
                gradeGoals = items
                showAllGoals = false
                reviewBoard = review
                HomeSnapshotStore.gradeGoals = items
                HomeSnapshotStore.reviewBoard = review
            }
        }
    }

    private func applyBannerSnapshot() {
        if !HomeSnapshotStore.banners.isEmpty {
            bannerURLs = HomeSnapshotStore.banners
            bannerAspects = HomeSnapshotStore.bannerAspects
        }
    }
}

struct HomeFeaturePlaceholderView: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProfileSimpleTopBar(title: title, onBack: onBack)
            Spacer()
            VStack(spacing: 8) {
                Text("\(title)即将同步")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "1A1A1A"))
                Text("该功能正在按 Android 端对齐开发")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "9AA3AF"))
            }
            Spacer()
        }
        .background(Color(hex: "F5F7FA").ignoresSafeArea())
    }
}

enum HomeSnapshotStore {
    private static let urlsKey = "home_banner_urls"
    private static let aspectsKey = "home_banner_aspects"

    static var banners: [String] = UserDefaults.standard.stringArray(forKey: urlsKey) ?? []
    static var bannerAspects: [CGFloat] = (UserDefaults.standard.array(forKey: aspectsKey) as? [Double])?.map { CGFloat($0) } ?? []
    static var gradeGoals: [HomeGradeGoalItem] = []
    static var reviewBoard: ReviewBoard?
    static var bannersLoaded = false

    static func prefetchBanners() {
        Task { _ = await refreshBanners() }
    }

    @discardableResult
    static func refreshBanners() async -> [String]? {
        let urls = await ApiService.shared.fetchBannerUrls()
        guard let urls else { return banners.isEmpty ? nil : banners }
        bannersLoaded = true
        persist(urls: urls, aspects: bannerAspects.count == urls.count ? bannerAspects : Array(repeating: 2.34375, count: urls.count))
        HomeBannerImageCache.prefetch(urls)
        Task {
            let aspects = await HomeBannerMetrics.aspects(for: urls)
            persist(urls: urls, aspects: aspects)
        }
        return urls
    }

    private static func persist(urls: [String], aspects: [CGFloat]) {
        banners = urls
        bannerAspects = aspects
        UserDefaults.standard.set(urls, forKey: urlsKey)
        UserDefaults.standard.set(aspects.map { Double($0) }, forKey: aspectsKey)
    }
}

private enum HomeBannerMetrics {
    static func aspects(for urls: [String]) async -> [CGFloat] {
        await withTaskGroup(of: (Int, CGFloat).self) { group in
            for (index, urlString) in urls.enumerated() {
                group.addTask { (index, await aspect(for: urlString)) }
            }
            var result = Array(repeating: CGFloat(2.34375), count: urls.count)
            for await item in group {
                if item.1 > 0 { result[item.0] = item.1 }
            }
            return result
        }
    }

    private static func aspect(for urlString: String) async -> CGFloat {
        if let cached = HomeBannerImageCache.image(for: urlString) {
            let width = cached.size.width * cached.scale
            let height = cached.size.height * cached.scale
            return (width > 0 && height > 0) ? width / height : 0
        }
        guard let image = await HomeBannerImageCache.download(urlString) else { return 0 }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width > 0, height > 0 else { return 0 }
        return width / height
    }
}

private enum HomeBannerImageCache {
    private static let memory = NSCache<NSString, UIImage>()

    static func image(for urlString: String) -> UIImage? {
        memory.object(forKey: urlString as NSString)
    }

    static func prefetch(_ urls: [String]) {
        urls.forEach { url in
            Task { _ = await download(url) }
        }
    }

    static func download(_ urlString: String) async -> UIImage? {
        if let cached = image(for: urlString) { return cached }
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            memory.setObject(image, forKey: urlString as NSString)
            return image
        } catch {
            return nil
        }
    }
}

private struct HomeBannerImage: View {
    let urlString: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(hex: "E0E0E0")
            }
        }
        .onAppear {
            image = HomeBannerImageCache.image(for: urlString)
            if image == nil {
                Task {
                    let downloaded = await HomeBannerImageCache.download(urlString)
                    await MainActor.run { image = downloaded }
                }
            }
        }
    }
}
