import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showLogin = false
    @State private var showGpaCalculator = false
    @State private var gpaOpenHistory = false
    @State private var gpaFromGradeTarget = false
    @State private var showAssessment = false
    @State private var assessmentInProgressId: Int?
    @State private var assessmentReport: (id: Int, score: Int)?
    @State private var showAssessmentSummary = false
    @State private var profileRoute: ProfileRoute?
    @State private var hideTabBarForCamera = false
    @State private var chatHistoryVisible = false
    @State private var qaRefreshTrigger = 0
    @State private var homeRoute: HomeRoute?
    @State private var homeReloadTrigger = 0
    @StateObject private var academicSession = AcademicSession()
    
    // 协议弹窗
    @AppStorage("agreementAccepted") private var agreementAccepted = false
    
    var body: some View {
        ZStack {
            mainContent
        }
        .environmentObject(academicSession)
        .onAppear {
            AcademicApi.prefetchSubjectRegister()
            AcademicApi.prefetchMyCourses()
            HomeSnapshotStore.prefetchBanners()
        }
        .overlay {
            if !agreementAccepted {
                AgreementGateView {
                    agreementAccepted = true
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if showLogin {
                LoginScreen(onBack: { showLogin = false }, onLoginSuccess: {
                    showLogin = false
                    selectedTab = 2
                    homeReloadTrigger += 1
                })
            } else if showGpaCalculator {
                GpaAcademicView(openHistory: gpaOpenHistory, onBack: {
                    showGpaCalculator = false
                    let reopenTarget = gpaFromGradeTarget
                    gpaOpenHistory = false
                    gpaFromGradeTarget = false
                    if reopenTarget {
                        homeRoute = .gradeTarget
                    }
                })
            } else if let route = homeRoute {
                homeDestination(route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let route = profileRoute {
                profileDestination(route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = assessmentReport {
                AssessmentReportView(
                    assessmentId: report.id,
                    score: report.score,
                    onBackHome: {
                        assessmentReport = nil
                        showAssessment = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let aid = assessmentInProgressId {
                AssessmentQuestionView(
                    assessmentId: aid,
                    onQuit: {
                        assessmentInProgressId = nil
                        showAssessment = true
                    },
                    onFinish: { finishedId, score in
                        AssessmentStore.saveScore(assessmentId: finishedId, score: score)
                        assessmentInProgressId = nil
                        assessmentReport = (finishedId, score)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showAssessmentSummary {
                AssessmentSummaryView(onBackHome: {
                    showAssessmentSummary = false
                    showAssessment = true
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showAssessment {
                AssessmentHomeView(
                    onBack: { showAssessment = false },
                    onStartAssessment: { aid in
                        if AssessmentStore.isLocked { return }
                        showAssessment = false
                        assessmentInProgressId = aid
                    },
                    onOpenSummary: {
                        showAssessment = false
                        showAssessmentSummary = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    Group {
                        switch selectedTab {
                        case 0:
                            HomeView(
                                onOpenSubjectRegister: { openHomeFeature { homeRoute = .subjectRegister } },
                                onOpenGpa: {
                                    openHomeFeature {
                                        gpaOpenHistory = false
                                        gpaFromGradeTarget = false
                                        showGpaCalculator = true
                                    }
                                },
                                onOpenGradeTarget: { openHomeFeature { homeRoute = .gradeTarget } },
                                onOpenAssessment: { openHomeFeature { showAssessment = true } },
                                onOpenAiChat: { selectedTab = 1 },
                                onOpenMyAsk: { openHomeFeature { profileRoute = .myAsk } },
                                onOpenCourse: {
                                    openHomeFeature { homeRoute = .myCourse }
                                },
                                onOpenPoliticsQuiz: { selectedTab = 1 },
                                onOpenReviewPlan: { openHomeFeature { homeRoute = .reviewPlan } },
                                reloadTrigger: homeReloadTrigger
                            )
                        case 1:
                            AiChatView(
                                onNeedLogin: { showLogin = true },
                                onOpenTimetable: { homeRoute = .subjectRegister },
                                onOpenHome: { selectedTab = 0 },
                                onOpenMine: { selectedTab = 2 },
                                qaRefreshTrigger: qaRefreshTrigger,
                                onCameraOverlayVisibleChanged: { hideTabBarForCamera = $0 },
                                onHistoryVisibleChanged: { chatHistoryVisible = $0 }
                            )
                        default:
                            MyView(
                                onNeedLogin: { showLogin = true },
                                onOpenMyAsk: { profileRoute = .myAsk },
                                onOpenAssessment: { showAssessment = true },
                                onOpenVip: { profileRoute = .vipCenter },
                                onOpenAccount: { profileRoute = .account },
                                onOpenStudentInfo: { profileRoute = .studentInfo },
                                onOpenFeedback: { profileRoute = .feedback }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !(hideTabBarForCamera || selectedTab == 1) {
                        MainTabBar(selectedTab: $selectedTab)
                            .background(Color.white.ignoresSafeArea(edges: .bottom))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func homeDestination(_ route: HomeRoute) -> some View {
        switch route {
        case .subjectRegister:
            SubjectRegisterView(onBack: {
                homeRoute = nil
                qaRefreshTrigger += 1
                homeReloadTrigger += 1
            }, onOpenGpa: {
                homeRoute = nil
                gpaOpenHistory = false
                gpaFromGradeTarget = false
                showGpaCalculator = true
            })
        case .gradeTarget:
            GradeBacktrackView(onBack: {
                homeRoute = nil
                homeReloadTrigger += 1
            }, onOpenHistory: {
                homeRoute = nil
                gpaOpenHistory = true
                gpaFromGradeTarget = true
                showGpaCalculator = true
            })
        case .politicsQuiz:
            HomeFeaturePlaceholderView(title: "思政刷题", onBack: { homeRoute = nil })
        case .reviewPlan:
            ReviewCheckinView(onBack: {
                homeRoute = nil
                homeReloadTrigger += 1
            })
        case .myCourse:
            MyCourseView(onBack: { homeRoute = nil })
        }
    }

    @ViewBuilder
    private func profileDestination(_ route: ProfileRoute) -> some View {
        switch route {
        case .myAsk:
            MyAskListView(
                onBack: { profileRoute = nil },
                onNeedLogin: { showLogin = true },
                onOpenTimetable: {
                    profileRoute = nil
                    homeRoute = .subjectRegister
                }
            )
        case .vipCenter:
            if AppFeatures.showMembership {
                VipCenterView(onBack: { profileRoute = nil }, onOpenRecharge: {
                    if AppFeatures.showRecharge {
                        profileRoute = .recharge
                    }
                }, onOpenOrders: { profileRoute = .myOrders })
            } else {
                Color.clear.onAppear { profileRoute = nil }
            }
        case .recharge:
            if AppFeatures.showRecharge {
                RechargeView(onBack: { profileRoute = .vipCenter })
            } else {
                Color.clear.onAppear { profileRoute = nil }
            }
        case .myOrders:
            if AppFeatures.showMembership {
                MyOrderView(onBack: { profileRoute = .vipCenter })
            } else {
                Color.clear.onAppear { profileRoute = nil }
            }
        case .account:
            AccountManageView(onBack: { profileRoute = nil }) {
                ApiService.shared.token = nil
                profileRoute = nil
            } onOpenApplyClose: { profileRoute = .applyCloseAccount }
        case .applyCloseAccount:
            ApplyCloseAccountView(onBack: { profileRoute = .account }) { profileRoute = .confirmCloseAccount }
        case .confirmCloseAccount:
            ConfirmCloseAccountView(onBack: { profileRoute = .applyCloseAccount }) {
                ApiService.shared.token = nil
                profileRoute = nil
                selectedTab = 0
            }
        case .studentInfo:
            StudentInfoView(onBack: { profileRoute = nil }) { profileRoute = .studentCertification }
        case .studentCertification:
            StudentCertificationView(onBack: { profileRoute = .studentInfo })
        case .feedback:
            FeedbackView(onBack: { profileRoute = nil })
        }
    }

    private func openHomeFeature(_ action: () -> Void) {
        if (ApiService.shared.token ?? "").isEmpty {
            showLogin = true
            return
        }
        action()
    }
}

// MARK: - 首次启动协议（iPad 上 alert + Link 会导致卡启动页，改用全屏弹层）
private struct AgreementGateView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("服务协议和隐私政策")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)

                Text("欢迎使用绩满满。请先阅读并同意《用户协议》和《隐私协议》后继续使用。")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("用户协议") {
                        SafariOpen.page(AgreementURL.userAgreement)
                    }
                    .font(.system(size: 14))
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.primary)
                    Text("|")
                        .foregroundColor(AppColors.textMuted)
                    Button("隐私协议") {
                        SafariOpen.page(AgreementURL.privacyPolicy)
                    }
                    .font(.system(size: 14))
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.primary)
                }

                Button(action: onAccept) {
                    Text("同意并继续")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - 路由枚举
enum HomeRoute {
    case subjectRegister, gradeTarget, politicsQuiz, reviewPlan, myCourse
}

enum ProfileRoute {
    case myAsk, vipCenter, recharge, myOrders
    case account, applyCloseAccount, confirmCloseAccount
    case studentInfo, studentCertification, feedback
}

// MARK: - 底部 Tab 栏（对齐 Android BottomTabBar：图标 24pt、文字 11pt）
private struct MainTabBar: View {
    @Binding var selectedTab: Int

    private struct TabItem {
        let title: String
        let icon: String
        let selectedIcon: String
    }

    private let tabs: [TabItem] = [
        TabItem(title: "首页", icon: "tabbar_home", selectedIcon: "tabbar_home_on"),
        TabItem(title: "答疑", icon: "tabbar_dayi_un", selectedIcon: "tabbar_dy"),
        TabItem(title: "我的", icon: "tabbar_me", selectedIcon: "tabbar_me_on")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(hex: "E5E5E5"))

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let selected = selectedTab == index
                    Button {
                        selectedTab = index
                    } label: {
                        VStack(spacing: 4) {
                            Image(selected ? tab.selectedIcon : tab.icon)
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 24, height: 24)

                            Text(tab.title)
                                .font(.system(size: 11))
                                .foregroundColor(selected ? Color(hex: "00B4BE") : Color(hex: "999999"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white)
        }
        .background(Color.white)
    }
}
