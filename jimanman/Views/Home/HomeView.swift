import SwiftUI

// MARK: - 首页
struct HomeView: View {
    let onOpenGpa: () -> Void
    let onOpenAssessment: () -> Void
    let onOpenAiChat: () -> Void
    let onOpenCourse: () -> Void
    
    @State private var bannerURLs: [String] = []
    @State private var currentBannerIndex = 0
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // 标题栏
                pageTitleBar(title: "绩满满")
                
                // 轮播图
                tabViewSection
                
                Spacer().frame(height: 2)
                
                // 功能菜单入口
                menuGridSection
                
                // 海报区域
                posterCard
            }
        }
        .background(AppColors.background)
        .onAppear { loadBanners() }
    }
    
    // MARK: - 标题栏
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
    
    // MARK: - 轮播图
    private var tabViewSection: some View {
        TabView(selection: $currentBannerIndex) {
            ForEach(bannerURLs.indices, id: \.self) { index in
                AsyncImage(url: URL(string: bannerURLs[index])) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Rectangle().fill(Color(hex: "E0E0E0")).overlay(
                            Text("加载中...").foregroundColor(.gray).font(.system(size: 14))
                        )
                    }
                }
                .tag(index)
            }
        }
        .frame(height: UIScreen.main.bounds.width * 300 / 750)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .onReceive(timer) { _ in
            if !bannerURLs.isEmpty {
                currentBannerIndex = (currentBannerIndex + 1) % bannerURLs.count
            }
        }
    }
    
    // MARK: - 功能菜单
    private var menuGridSection: some View {
        HStack(alignment: .top, spacing: 2) {
            HomeMenuItem(iconName: "ic_nav_ai", title: "快速答疑", action: onOpenAiChat)
            HomeMenuItem(iconName: "ic_nav_gpa", title: "GPA计算", action: onOpenGpa)
            HomeMenuItem(iconName: "ic_nav_assessment", title: "学习能力测试", action: onOpenAssessment)
            HomeMenuItem(iconName: "ic_nav_course", title: "我的课程", action: onOpenCourse)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
        .background(Color.white)
    }
    
    // MARK: - 海报卡片（对齐 Android：白底圆角卡片 + 满宽 FillWidth）
    private var posterCard: some View {
        VStack(spacing: 0) {
            Image("poster_home")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Spacer().frame(height: 12)
        }
    }
    
    // MARK: - 加载轮播图
    private func loadBanners() {
        Task {
            let urls = await ApiService.shared.fetchBannerUrls()
            await MainActor.run { self.bannerURLs = urls }
        }
    }
}

// MARK: - 首页菜单项
private struct HomeMenuItem: View {
    let iconName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
