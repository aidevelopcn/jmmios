import SwiftUI
import UIKit

private let AdvisorWechat = "JDMM015"
private let StarGold = Color(hex: "F0B400")
private let Amber = Color(hex: "F59E0B")
private let AmberInk = Color(hex: "B45309")
private let AmberTint = Color(hex: "FFF7E6")
private let CardLine = Color(hex: "E4E9EB")
private let CoursePageBg = Color(hex: "F5F7F8")

struct MyCourseView: View {
    let onBack: () -> Void

    @State private var loading = MyCoursesCache.snapshot() == nil
    @State private var loadError: String?
    @State private var enrolled = MyCoursesCache.snapshot()?.enrolled ?? false
    @State private var loadReason = MyCoursesCache.snapshot()?.reason ?? ""
    @State private var courses = MyCoursesCache.snapshot()?.courses ?? []
    @State private var expanded: Set<String> = []
    @State private var busyRecordId: Int?
    @State private var reviewCourse: MyCourseItem?
    @State private var ratingTeach = 0.0
    @State private var ratingAdvisor = 0.0
    @State private var commentTeach = ""
    @State private var commentAdvisor = ""
    @State private var submittingReview = false
    @State private var showConsult = false
    @State private var toast = ""
    @State private var showToast = false
    @State private var reloadKey = 0
    @State private var openSeries: Set<String> = []

    var body: some View {
        ProfileScreenScaffold(background: CoursePageBg) {
            VStack(spacing: 0) {
                ProfileSimpleTopBar(title: "我的课程", onBack: onBack)
                content
            }
        }
        .task(id: reloadKey) { await reload() }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toast)
        }
        .alert("请咨询顾问，微信号 \(AdvisorWechat)", isPresented: $showConsult) {
            Button("复制微信号") {
                UIPasteboard.general.string = AdvisorWechat
                toast = "已复制顾问微信：\(AdvisorWechat)"
                showToast = true
            }
            Button("取消", role: .cancel) {}
        }
        .overlay {
            if let course = reviewCourse {
                reviewSheet(course)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            Spacer()
            ProgressView().tint(AcademicPalette.hero)
            Spacer()
        } else if let loadError {
            Spacer()
            Text(loadError)
                .font(.system(size: 14))
                .foregroundColor(AcademicPalette.muted)
            Button("重试") { reloadKey += 1 }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(AcademicPalette.hero)
                .clipShape(Capsule())
                .padding(.top, 16)
            Spacer()
        } else if enrolled {
            enrolledBody
        } else {
            catalogBody
        }
    }

    private var enrolledBody: some View {
        let total = courses.reduce(0) { $0 + $1.totalHours }
        let used = courses.reduce(0) { $0 + $1.usedHours }
        let left = courses.reduce(0) { $0 + (($1.finished || $1.refunded) ? 0 : $1.leftHours) }
        let pct = total > 0 ? min(100, max(0, Int((used / total) * 100))) : 0
        let studying = courses.contains { !$0.finished && !$0.refunded && $0.leftHours > 0 }
        let pending: [(MyCourseItem, MyCourseRecord)] = courses.flatMap { course in
            course.records.filter(\.confirmable).map { (course, $0) }
        }
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hoursHero(count: courses.count, left: left, total: total, used: used, percent: pct, studying: studying)
                ForEach(Array(pending.enumerated()), id: \.offset) { _, pair in
                    pendingCard(course: pair.0, record: pair.1)
                }
                HStack(spacing: 8) {
                    Text("已报课程")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AcademicPalette.ink)
                    Text("\(courses.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(AcademicPalette.hero)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 10)
                if courses.isEmpty {
                    Text("还没有课程。班主任在后台建课后，会显示在这里。")
                        .font(.system(size: 13))
                        .foregroundColor(AcademicPalette.muted)
                        .padding(.horizontal, 18)
                }
                ForEach(courses) { course in
                    courseCard(course)
                }
                Spacer().frame(height: 24)
            }
        }
    }

    private func heroStatus(studying: Bool, courses: [MyCourseItem]) -> String {
        if studying { return "在学中" }
        if courses.contains(where: { $0.finished }) { return "已结课" }
        if !courses.isEmpty && courses.allSatisfy({ $0.refunded }) { return "已退费" }
        if courses.contains(where: { $0.refunded }) && !courses.contains(where: { !$0.refunded && $0.leftHours > 0 }) {
            return "已退费"
        }
        return "已结课"
    }

    private func hoursHero(count: Int, left: Double, total: Double, used: Double, percent: Int, studying: Bool) -> some View {
        JmmHeroSurface(radius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Spacer()
                    Text("本学期").font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white)
                    Circle().fill(AcademicPalette.lemon).frame(width: 6, height: 6)
                        .shadow(color: AcademicPalette.lemon.opacity(0.45), radius: 3)
                    Text("在读").font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white)
                    Text("\(count)")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(Color(hex: "0A3D33"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.42))
                        .clipShape(Capsule())
                    Text("门").font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    Text(formatHours(left))
                        .font(.system(size: 56, weight: .black))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("剩余课时")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 10)
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: "0A3D33")).frame(width: 6, height: 6)
                        Text(heroStatus(studying: studying, courses: courses))
                            .font(.system(size: 11.5, weight: .heavy))
                            .foregroundColor(Color(hex: "0A3D33"))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.40))
                    .clipShape(Capsule())
                    .padding(.bottom, 10)
                }
                .padding(.top, 10)
                Color.white.opacity(0.22).frame(height: 1).padding(.vertical, 12)
                HStack {
                    heroStat(formatHours(total), "总课时")
                    Color.white.opacity(0.28).frame(width: 1, height: 26)
                    heroStat(formatHours(used), "已用 · \(percent)%")
                    Color.white.opacity(0.28).frame(width: 1, height: 26)
                    heroStat(formatHours(left), "剩余")
                }
            }
            .padding(18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .heavy)).foregroundColor(.white)
            Text(label).font(.system(size: 11)).foregroundColor(.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity)
    }

    private func pendingCard(course: MyCourseItem, record: MyCourseRecord) -> some View {
        HStack(spacing: 0) {
            Color(hex: "4DCDC4")
                .frame(width: 4, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.vertical, 12)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(hex: "D97706"))
                Text("!")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white)
            }
            .frame(width: 42, height: 42)
            .padding(.leading, 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(course.teacherName.isEmpty ? "授课老师" : course.teacherName)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(AcademicPalette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("待你确认")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(AcademicPalette.brandInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AcademicPalette.hintBg)
                        .overlay(Capsule().stroke(AcademicPalette.hero.opacity(0.55), lineWidth: 1))
                        .clipShape(Capsule())
                }
                Text("已登记 \(record.date.isEmpty ? "最近" : record.date) 的 \(formatHours(record.hours)) 课时，请核对后确认")
                    .font(.system(size: 12))
                    .foregroundColor(AcademicPalette.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            Button {
                confirm(record)
            } label: {
                Text(busyRecordId == record.id ? "确认中" : "确认课时")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AcademicPalette.hero)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busyRecordId != nil)
            .padding(.trailing, 12)
        }
        .background(AmberTint)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func courseCard(_ course: MyCourseItem) -> some View {
        let remaining = (course.finished || course.refunded) ? 0 : course.leftHours
        let percent = course.finished
            ? 100
            : (course.totalHours > 0 ? min(100, max(0, Int((course.usedHours / course.totalHours) * 100))) : 0)
        let rawTeacher = course.teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacherPending = rawTeacher.isEmpty || rawTeacher.hasPrefix("待")
        let teacher = rawTeacher.isEmpty ? "待排课" : rawTeacher
        let opened = expanded.contains(course.courseNo)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Capsule().fill(Color(hex: "35BDB4")).frame(width: 4, height: 17)
                Text(course.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AcademicPalette.ink)
            }
            HStack(spacing: 6) {
                Text(String(teacher.prefix(1)))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(teacherPending ? Color(hex: "0A3D33") : .white)
                    .frame(width: 20, height: 20)
                    .background(teacherPending ? Amber : avatarColor(teacher))
                    .clipShape(Circle())
                Text(teacher).font(.system(size: 12)).foregroundColor(AcademicPalette.muted)
                if course.records.contains(where: { $0.confirmable }) {
                    Text("待确认")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AcademicPalette.brandInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AcademicPalette.hintBg)
                        .overlay(Capsule().stroke(AcademicPalette.hero.opacity(0.55), lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 6)
            HStack {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "EDF0F2"))
                        Capsule().fill(AcademicPalette.hero).frame(width: geo.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 10)
                Text("\(percent)%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AcademicPalette.brandInk)
                    .padding(.leading, 12)
            }
            .padding(.top, 12)
            HStack {
                hourCell("总课时", course.totalHours, false)
                hourCell("已上", course.usedHours, false)
                hourCell("剩余", remaining, true)
            }
            .padding(.top, 10)
            if !course.courseNo.hasPrefix("enroll-subject:") {
                rateRow(course)
            }
            Button {
                if opened { expanded.remove(course.courseNo) } else { expanded.insert(course.courseNo) }
            } label: {
                HStack {
                    Spacer()
                    Text(opened ? "收起记录" : "上课记录")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(AcademicPalette.brandInk)
                    Text(opened ? "▾" : "›")
                        .foregroundColor(AcademicPalette.brandInk)
                }
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
            if opened {
                if course.records.isEmpty {
                    Text("还没有上课记录")
                        .font(.system(size: 12))
                        .foregroundColor(AcademicPalette.muted)
                        .padding(.top, 6)
                }
                ForEach(course.records) { record in
                    let confirmed = record.status == "已确认"
                    let statusColor = confirmed ? Color(hex: "15803D") : AmberInk
                    HStack {
                        Text(record.date.isEmpty ? "—" : record.date)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(AcademicPalette.ink)
                        Text("\(formatHours(record.hours)) 课时")
                            .font(.system(size: 12.5))
                            .foregroundColor(AcademicPalette.muted)
                        Spacer()
                        Text(record.status)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.14))
                            .overlay(Capsule().stroke(statusColor.opacity(0.38), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(hex: "F4F7F8"))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(CardLine, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CardLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func hourCell(_ label: String, _ value: Double, _ accent: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundColor(Color(hex: "9AA3A8"))
            Text(formatHours(value))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(accent ? AcademicPalette.brandInk : AcademicPalette.ink)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func rateRow(_ course: MyCourseItem) -> some View {
        HStack {
            if let evaluation = course.evaluation {
                Text("已完成 · 已评价")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "9AA3A8"))
                Spacer()
                HStack(spacing: 4) {
                    miniStars(evaluation.rating1)
                    Text(" \(formatHours(evaluation.rating1)) · 教务 \(formatHours(evaluation.rating2))")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(AcademicPalette.brandInk)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AcademicPalette.hintBg)
                .overlay(Capsule().stroke(AcademicPalette.hero.opacity(0.55), lineWidth: 1))
                .clipShape(Capsule())
            } else if course.refunded {
                Text("学员已退费")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "9AA3A8"))
            } else if course.canRate || course.finished {
                Text("课程已结课，分享你的体验")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "9AA3A8"))
                Spacer()
                Button("去评价") {
                    reviewCourse = course
                    ratingTeach = 0
                    ratingAdvisor = 0
                    commentTeach = ""
                    commentAdvisor = ""
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "0A3D33"))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Amber)
                .clipShape(Capsule())
            } else if course.leftHours > 0 {
                Text("完成全部课时后可评价（还剩 \(formatHours(course.leftHours)) 课时）")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "9AA3A8"))
            } else {
                Text("暂时还不能评价")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "9AA3A8"))
            }
        }
        .padding(.top, 12)
    }

    private func miniStars(_ rating: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Text("★")
                    .font(.system(size: 11))
                    .foregroundColor(rating + 0.01 >= Double(star) ? StarGold : Color(hex: "E5E7EB"))
            }
        }
    }

    private var catalogBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let reasonText = catalogReason {
                    Text(reasonText)
                        .font(.system(size: 12))
                        .foregroundColor(AmberInk)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Amber.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Amber.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
                JmmHeroSurface {
                    VStack(spacing: 6) {
                        Text("解锁你的绩点")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text("三大系列对应三种目标\n从「稳过及格」到「冲刺满绩」都有对应打法")
                            .font(.system(size: 12.5))
                            .foregroundColor(.white.opacity(0.90))
                            .multilineTextAlignment(.center)
                        Button {
                            copyWechat()
                        } label: {
                            Text("咨询顾问 · 微信 \(AdvisorWechat)")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(AcademicPalette.brandInk)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                ForEach(CourseCatalog.series, id: \.name) { series in
                    let opened = openSeries.contains(series.name)
                    Button {
                        if opened { openSeries.remove(series.name) } else { openSeries.insert(series.name) }
                    } label: {
                        HStack {
                            Text(series.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(series.iconColor)
                                .frame(width: 32, height: 32)
                                .background(series.tone)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(series.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AcademicPalette.brandInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.white)
                                .overlay(Capsule().stroke(AcademicPalette.hero.opacity(0.55), lineWidth: 1))
                                .clipShape(Capsule())
                            Text(series.price)
                                .font(.system(size: 11.5))
                                .foregroundColor(AcademicPalette.muted)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(opened ? "▴" : "▾")
                                .foregroundColor(AcademicPalette.brandInk)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 10)
                    }
                    .buttonStyle(.plain)
                    if opened {
                        ForEach(series.items, id: \.name) { product in
                            HStack(spacing: 12) {
                                Text(product.icon)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(series.iconColor)
                                    .frame(width: 40, height: 40)
                                    .background(series.tone)
                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(AcademicPalette.ink)
                                    Text(product.desc)
                                        .font(.system(size: 12))
                                        .foregroundColor(AcademicPalette.muted)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button("立即咨询") { showConsult = true }
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(AcademicPalette.hero)
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(CardLine, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }
                }
                Spacer().frame(height: 28)
            }
        }
    }

    private var catalogReason: String? {
        switch loadReason {
        case "no_courses":
            return "课程已建好但还没下发到账号，请联系班主任确认课程是否建在当前学号下。"
        case "no_enrollment":
            return "当前账号还没关联学籍，关联后班主任建的课程会显示在这里。"
        default:
            return nil
        }
    }

    private func reviewSheet(_ course: MyCourseItem) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture {
                if !submittingReview { reviewCourse = nil }
            }
            VStack(spacing: 0) {
                Capsule().fill(Color(hex: "E5E7EB")).frame(width: 36, height: 4).padding(.top, 8)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("课程评价").font(.system(size: 16, weight: .bold)).foregroundColor(AcademicPalette.ink)
                        Text(course.name).font(.system(size: 12)).foregroundColor(AcademicPalette.muted)
                    }
                    Spacer()
                    Button {
                        if !submittingReview { reviewCourse = nil }
                    } label: {
                        Text("×")
                            .font(.system(size: 18))
                            .foregroundColor(AcademicPalette.muted)
                            .frame(width: 32, height: 32)
                            .background(Color(hex: "F4F7F8"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                ScrollView {
                    rateBlock(role: "授课老师", name: course.teacherName, rating: $ratingTeach, comment: $commentTeach)
                    rateBlock(role: "教务老师", name: course.advisorName, rating: $ratingAdvisor, comment: $commentAdvisor)
                }
                .padding(.horizontal, 18)
                let ready = ratingTeach > 0 && ratingAdvisor > 0 && !submittingReview
                Button {
                    submitReview(course)
                } label: {
                    Text(submittingReview ? "提交中" : "提交评价")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(ready ? .white : Color(hex: "9AA3A8"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(ready ? AcademicPalette.hero : Color(hex: "E5E7EB"))
                        .clipShape(Capsule())
                }
                .disabled(!ready)
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                Button("下次再说") {
                    if !submittingReview { reviewCourse = nil }
                }
                .font(.system(size: 12.5))
                .foregroundColor(AcademicPalette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .padding(.bottom, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .modifier(KeyboardBottomPadding())
        }
    }

    private func rateBlock(role: String, name: String, rating: Binding<Double>, comment: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(role).font(.system(size: 13, weight: .bold)).foregroundColor(AcademicPalette.ink)
                Text(name.isEmpty ? role : name)
                    .font(.system(size: 12))
                    .foregroundColor(AcademicPalette.muted)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating.wrappedValue = Double(star)
                    } label: {
                        Text("★")
                            .font(.system(size: 26))
                            .foregroundColor(rating.wrappedValue + 0.01 >= Double(star) ? StarGold : Color(hex: "E5E7EB"))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("选填，最多 200 字", text: comment)
                .font(.system(size: 13))
                .padding(10)
                .background(Color(hex: "F8FAFC"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: comment.wrappedValue) { value in
                    if value.count > 200 { comment.wrappedValue = String(value.prefix(200)) }
                }
        }
        .padding(.vertical, 12)
    }

    private func reload() async {
        let result = await AcademicApi.fetchMyCourses()
        await MainActor.run {
            switch result {
            case .success(let payload):
                enrolled = payload.enrolled
                loadReason = payload.reason
                courses = payload.courses
                loadError = nil
            case .failure(let error):
                let message = error.localizedDescription
                if message.contains("登录") {
                    MyCoursesCache.clear()
                    enrolled = false
                    courses = []
                    loadReason = ""
                    loadError = nil
                } else if courses.isEmpty && !enrolled {
                    loadError = message.isEmpty ? "加载失败" : message
                } else {
                    toast = message.isEmpty ? "加载失败" : message
                    showToast = true
                }
            }
            loading = false
        }
    }

    private func confirm(_ record: MyCourseRecord) {
        guard busyRecordId == nil else { return }
        busyRecordId = record.id
        Task {
            let result = await AcademicApi.confirmMyCourseHours(recordId: record.id)
            await MainActor.run {
                busyRecordId = nil
                switch result {
                case .success(let message):
                    toast = message
                    showToast = true
                    reloadKey += 1
                case .failure(let error):
                    toast = error.localizedDescription.isEmpty ? "确认失败" : error.localizedDescription
                    showToast = true
                }
            }
        }
    }

    private func submitReview(_ course: MyCourseItem) {
        guard !submittingReview else { return }
        if ratingTeach <= 0 || ratingAdvisor <= 0 {
            toast = "请给授课老师和教务老师都打分"
            showToast = true
            return
        }
        submittingReview = true
        Task {
            let result = await AcademicApi.submitMyCourseRating(
                courseNo: course.courseNo,
                rating1: ratingTeach,
                rating2: ratingAdvisor,
                comment1: commentTeach.trimmingCharacters(in: .whitespacesAndNewlines),
                comment2: commentAdvisor.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await MainActor.run {
                submittingReview = false
                switch result {
                case .success(let message):
                    reviewCourse = nil
                    toast = message
                    showToast = true
                    reloadKey += 1
                case .failure(let error):
                    toast = error.localizedDescription.isEmpty ? "评价提交失败" : error.localizedDescription
                    showToast = true
                }
            }
        }
    }

    private func copyWechat() {
        UIPasteboard.general.string = AdvisorWechat
        toast = "已复制顾问微信：\(AdvisorWechat)"
        showToast = true
    }

    private func formatHours(_ value: Double) -> String {
        if value.isNaN { return "0" }
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 { return String(Int(rounded.rounded())) }
        return String(format: "%.1f", rounded)
    }

    private func avatarColor(_ name: String) -> Color {
        let colors = ["0F766E", "0369A1", "7C3AED", "C2410C", "BE185D", "15803D"]
        let idx = abs(name.hashValue) % colors.count
        return Color(hex: colors[idx])
    }
}

private enum CourseCatalog {
    struct Product { let name: String; let desc: String; let icon: String }
    struct Series {
        let name: String
        let price: String
        let tone: Color
        let iconColor: Color
        let icon: String
        let items: [Product]
    }

    static let series: [Series] = [
        Series(
            name: "领跑系列",
            price: "学期版 ¥36350 起 · 50/80 课时",
            tone: Color(hex: "EEFAFA"),
            iconColor: Color(hex: "00695A"),
            icon: "领",
            items: [
                Product(name: "早鸟领跑营", desc: "开学就上车，整学期四大阶段系统规划", icon: "早"),
                Product(name: "大二领跑营(逆袭版)", desc: "从大二补缺口，多科统筹把排名拉回来", icon: "二"),
                Product(name: "大三领跑营(逆袭版)", desc: "关键学年定向冲刺，守住保研留学线", icon: "三"),
                Product(name: "转专业领跑营", desc: "把转专业准入线倒推到各科分数", icon: "转"),
                Product(name: "大类分流领跑营", desc: "拆分流规则与名额，冲进目标专业", icon: "流"),
                Product(name: "保研领跑营", desc: "标准版 50 / 进阶版 100 / 旗舰版 180 课时", icon: "保"),
                Product(name: "留学领跑营", desc: "对标留学申请的绩点门槛规划", icon: "留")
            ]
        ),
        Series(
            name: "满血系列",
            price: "¥400 / 课时 · 6 课时起报",
            tone: Color(hex: "FFF7E6"),
            iconColor: Color(hex: "B45309"),
            icon: "满",
            items: [
                Product(name: "满血复活班", desc: "挂科补考急救，一对一兜底重修线", icon: "复"),
                Product(name: "满血速通班", desc: "期末窗口压缩复习范围，先稳住及格线", icon: "速")
            ]
        ),
        Series(
            name: "单科高分系列",
            price: "期末版 ¥8470 起",
            tone: Color(hex: "EEF2FF"),
            iconColor: Color(hex: "1D4ED8"),
            icon: "科",
            items: [
                Product(name: "高数上高分班", desc: "一门课一个阵地，按本校考情冲高分", icon: "数"),
                Product(name: "高数下高分班", desc: "下学期续阵地，考情无缝衔接", icon: "下"),
                Product(name: "线性代数高分班", desc: "线代专项，概念+题型双线突破", icon: "线"),
                Product(name: "概率统计高分班", desc: "概率统计专项，公式与套路全梳理", icon: "概"),
                Product(name: "大学物理高分班", desc: "大物专项，标准版含全学期知识精讲", icon: "物"),
                Product(name: "其他科目高分班", desc: "大学有的科目都能辅导，按需开班", icon: "其")
            ]
        )
    ]
}
