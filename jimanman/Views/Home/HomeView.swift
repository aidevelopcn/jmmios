import SwiftUI

// MARK: - 首页（对齐 Android HomeScreen）
struct HomeView: View {
    let onOpenSubjectRegister: () -> Void
    let onOpenGpa: () -> Void
    let onOpenGradeTarget: () -> Void
    let onOpenAssessment: () -> Void
    let onOpenAiChat: () -> Void
    let onOpenCourse: () -> Void
    let onOpenPoliticsQuiz: () -> Void
    let onOpenReviewPlan: () -> Void

    @State private var bannerURLs: [String] = []
    @State private var currentBannerIndex = 0
    @State private var gradeGoals: [HomeGradeGoalItem] = []
    private let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    private var featureItems: [(title: String, icon: String)] {
        let core: [(String, String)] = [
            ("科目登记", "icon_01"),
            ("GPA计算", "icon_06"),
            ("成绩倒推", "icon_02"),
            ("快速答疑", "icon_05"),
            ("能力测试", "icon_08"),
        ]
        let courses: [(String, String)] = AppFeatures.showExternalCourses
            ? [("我的课程", "icon_07")]
            : []
        let extra: [(String, String)] = [
            ("思政刷题", "icon_04"),
            ("复习计划", "icon_03"),
        ]
        return core + courses + extra
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("绩满满")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "111111"))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

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
        .onAppear { reloadHome() }
        .onReceive(timer) { _ in
            guard bannerURLs.count > 1 else { return }
            currentBannerIndex = (currentBannerIndex + 1) % bannerURLs.count
        }
    }

    private var bannerSection: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentBannerIndex) {
                ForEach(bannerURLs.indices, id: \.self) { index in
                    AsyncImage(url: URL(string: bannerURLs[index])) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color(hex: "E0E0E0")
                        }
                    }
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
        .frame(height: 152)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
            Color(hex: "00E5D4").frame(height: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color(hex: "00E5D4"), lineWidth: 2)
                            .frame(width: 18, height: 18)
                        Circle()
                            .fill(Color(hex: "00E5D4"))
                            .frame(width: 7, height: 7)
                    }
                    Text("各科成绩目标")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "00E5D4"))
                    Spacer()
                    Button(action: onOpenGradeTarget) {
                        HStack(spacing: 3) {
                            Text("成绩倒推")
                                .font(.system(size: 11, weight: .medium))
                            Text("›")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(Color(hex: "00E5D4"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "00E5D4").opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "00E5D4"), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                if gradeGoals.isEmpty {
                    Button(action: onOpenGradeTarget) {
                        VStack(spacing: 6) {
                            Text("暂无科目")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(hex: "1A1A1A"))
                            Text("完成科目登记或在成绩倒推中添加科目后，这里会显示各科目标")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "9AA3AF"))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(Array(gradeGoals.enumerated()), id: \.element.id) { index, goal in
                        HStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Text(goal.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color(hex: "1A1A1A"))
                                    .lineLimit(1)
                                if !goal.credit.isEmpty {
                                    Text(goal.credit)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "9AA3AF"))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            Text(goal.scored ? "出分 \(goal.goal)" : "目标 \(goal.goal)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color(hex: "00E5D4"))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 12)
                        if index != gradeGoals.count - 1 {
                            Color(hex: "F0F2F5").frame(height: 0.5)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(hex: "1DB8B5").opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private func openFeature(_ title: String) {
        switch title {
        case "科目登记": onOpenSubjectRegister()
        case "GPA计算": onOpenGpa()
        case "成绩倒推": onOpenGradeTarget()
        case "能力测试": onOpenAssessment()
        case "快速答疑": onOpenAiChat()
        case "我的课程": onOpenCourse()
        case "思政刷题": onOpenPoliticsQuiz()
        case "复习计划": onOpenReviewPlan()
        default: break
        }
    }

    private func reloadHome() {
        Task {
            async let banners = ApiService.shared.fetchBannerUrls()
            async let goals = AcademicHomeService.loadGradeGoals()
            let (urls, items) = await (banners, goals)
            await MainActor.run {
                bannerURLs = urls
                if currentBannerIndex >= urls.count { currentBannerIndex = 0 }
                gradeGoals = items
            }
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
