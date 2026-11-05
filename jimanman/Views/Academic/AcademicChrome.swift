import SwiftUI
import UIKit

enum AcademicPalette {
    static let ink = Color(hex: "1A1F26")
    static let dim = Color(hex: "9CA3AF")
    static let muted = Color(hex: "4B5563")
    static let teal = Color(hex: "4ECDC4")
    static let acc = Color(hex: "4ECDC4")
    static let brandInk = Color(hex: "00695A")
    static let ghostInk = Color(hex: "3FBFB5")
    static let page = Color(hex: "F5F7FA")
    static let hintBg = Color(hex: "EEFAFA")
    static let hero = Color(hex: "4DCDC4")
    static let heroWarn = Color(hex: "E5B44E")
    static let heroWarnInk = Color(hex: "3B2B0B")
    static let lemon = Color(hex: "FFD60A")
    static let hair = Color(hex: "EEF1F3")
    static let line = Color(hex: "0F172A").opacity(0.07)
}

struct JmmHeroDecor: View {
    var warn: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Circle()
                .stroke(Color.white.opacity(warn ? 0.18 : 0.38), lineWidth: 2)
                .frame(width: 280, height: 280)
                .position(x: w + 20, y: -90)
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.white.opacity(warn ? 0.34 : 0.90), lineWidth: 2.5)
                .frame(width: 17, height: 17)
                .rotationEffect(.degrees(45))
                .position(x: w - 28, y: 26)
            Circle()
                .fill(Color.white.opacity(warn ? 0.28 : 0.55))
                .frame(width: 6, height: 6)
                .position(x: w - 49, y: 52)
        }
        .allowsHitTesting(false)
    }
}

struct JmmHeroSurface<Content: View>: View {
    var warn: Bool = false
    var radius: CGFloat = 22
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    warn ? AcademicPalette.heroWarn : AcademicPalette.hero
                    JmmHeroDecor(warn: warn)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(
                color: (warn ? AcademicPalette.heroWarn : AcademicPalette.hero).opacity(0.42),
                radius: 18,
                x: 0,
                y: 10
            )
    }
}

struct AcademicSheet<Content: View>: View {
    let title: String
    var action: String = "取消"
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 12) {
                Capsule()
                    .fill(AcademicPalette.hair)
                    .frame(width: 38, height: 4)
                    .frame(maxWidth: .infinity)
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AcademicPalette.ink)
                    Spacer()
                    Button(action) { onDismiss() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AcademicPalette.ghostInk)
                }
                content()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .modifier(KeyboardBottomPadding())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

enum KeyboardOverlap {
    static func from(_ note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
        let screen = UIScreen.main.bounds
        return max(0, screen.maxY - frame.minY)
    }
}

struct KeyboardBottomPadding: ViewModifier {
    @State private var inset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, inset)
            .animation(.easeOut(duration: 0.22), value: inset)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                inset = KeyboardOverlap.from(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                inset = 0
            }
    }
}

struct AcademicPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AcademicPalette.hero)
                .clipShape(Capsule())
                .opacity(enabled ? 1 : 0.5)
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

struct AcademicSecondaryButton: View {
    let title: String
    var tint: Color = AcademicPalette.teal
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .overlay(Capsule().stroke(Color(hex: "DDE0E4"), lineWidth: 1))
                .clipShape(Capsule())
                .opacity(enabled ? 1 : 0.5)
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

struct AcademicSettingRow: View {
    let label: String
    let value: String
    var accent: Bool = false
    var chevron: String = ""
    var auto: String = ""
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(AcademicPalette.muted)
                Spacer()
                if !auto.isEmpty {
                    Text(auto)
                        .font(.system(size: 11))
                        .foregroundColor(AcademicPalette.teal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AcademicPalette.hintBg)
                        .clipShape(Capsule())
                }
                Text(value)
                    .font(.system(size: 14, weight: accent ? .semibold : .regular))
                    .foregroundColor(accent ? AcademicPalette.teal : AcademicPalette.ink)
                if !chevron.isEmpty {
                    Text(chevron).foregroundColor(AcademicPalette.dim)
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

struct AcademicSectionCard<Content: View>: View {
    let title: String
    var extra: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AcademicPalette.muted)
                Spacer()
                if !extra.isEmpty {
                    Text(extra)
                        .font(.system(size: 12))
                        .foregroundColor(AcademicPalette.dim)
                }
            }
            .padding(.bottom, 4)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "0F172A").opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct AcademicHeroCard: View {
    let title: String
    let gpaValue: String
    let unit: String
    let band: String
    let footLeft: String
    let footRight: String
    var warn: Bool = false

    var body: some View {
        JmmHeroSurface(warn: warn) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(warn ? AcademicPalette.brandInk : AcademicPalette.lemon)
                        .frame(width: 6, height: 6)
                        .shadow(color: AcademicPalette.lemon.opacity(warn ? 0 : 0.45), radius: 3)
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(warn ? AcademicPalette.heroWarnInk : .white)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(gpaValue)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(warn ? AcademicPalette.heroWarnInk : .white)
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(warn ? AcademicPalette.heroWarnInk.opacity(0.8) : .white.opacity(0.95))
                }
                Text(band)
                    .font(.system(size: 13.5))
                    .foregroundColor(warn ? AcademicPalette.heroWarnInk.opacity(0.88) : .white.opacity(0.92))
                HStack {
                    Text(footLeft)
                    Spacer()
                    Text(footRight)
                }
                .font(.system(size: 12.5))
                .foregroundColor(warn ? AcademicPalette.heroWarnInk.opacity(0.88) : .white.opacity(0.92))
                .padding(.top, 8)
                .overlay(alignment: .topLeading) {
                    Color.white.opacity(warn ? 0.16 : 0.22).frame(height: 1)
                }
            }
            .padding(18)
        }
    }
}

struct AcademicSegmentControl: View {
    let options: [String]
    let selectedIndex: Int
    var largeCorner: Bool = true
    var segmentHeight: CGFloat = 36
    let onSelect: (Int) -> Void

    private var trackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: largeCorner ? segmentHeight : 12, style: .continuous)
    }

    private var itemShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: largeCorner ? segmentHeight : 10, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Text(options[index])
                        .font(.system(size: 14, weight: index == selectedIndex ? .semibold : .regular))
                        .foregroundColor(index == selectedIndex ? AcademicPalette.brandInk : AcademicPalette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: segmentHeight)
                        .background(index == selectedIndex ? Color.white : Color.clear)
                        .clipShape(itemShape)
                        .shadow(
                            color: index == selectedIndex ? Color.black.opacity(0.06) : .clear,
                            radius: index == selectedIndex ? 6 : 0,
                            y: 1
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(hex: "EDEFF2"))
        .clipShape(trackShape)
    }
}

struct AcademicCompactToolbar: View {
    let semesterLabel: String
    let ruleLabel: String
    var semesterEnabled: Bool = true
    let onSemesterClick: () -> Void
    let onRuleClick: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            toolbarChip(semesterLabel, enabled: semesterEnabled, action: onSemesterClick)
            Spacer(minLength: 8)
            toolbarChip(ruleLabel.isEmpty ? "标准 4.0" : ruleLabel, enabled: true, action: onRuleClick)
        }
    }

    private func toolbarChip(_ text: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text + " ▾")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AcademicPalette.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AcademicPalette.hintBg)
                .overlay(Capsule().stroke(Color(hex: "CCFBF1"), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.7)
    }
}

struct AcademicLabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var enabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AcademicPalette.muted)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .disabled(!enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(hex: "F8FAFC"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(enabled ? 1 : 0.55)
        }
    }
}

struct AcademicOptionRow: View {
    let title: String
    var right: String = ""
    var selected: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundColor(disabled ? AcademicPalette.ink.opacity(0.5) : (selected ? AcademicPalette.teal : AcademicPalette.ink))
                Spacer()
                Text(right)
                    .font(.system(size: 11))
                    .foregroundColor(selected ? AcademicPalette.teal : AcademicPalette.dim)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(selected ? Color(hex: "E0FAF6") : Color(hex: "F9FAFB"))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(selected ? Color(hex: "00DCC8") : Color(hex: "0F172A").opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct GpaCalcHeroCard: View {
    let title: String
    let gpaValue: String
    var subtitle: String = ""
    var chip: String = ""

    var body: some View {
        JmmHeroSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(AcademicPalette.lemon)
                        .frame(width: 6, height: 6)
                        .shadow(color: AcademicPalette.lemon.opacity(0.45), radius: 3)
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                }
                Text(gpaValue.isEmpty ? "—" : gpaValue)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                if !chip.isEmpty {
                    Text(chip)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AcademicPalette.ghostInk)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 5)
                        .background(AcademicPalette.hintBg)
                        .overlay(Capsule().stroke(Color(hex: "06746C").opacity(0.40), lineWidth: 1))
                        .clipShape(Capsule())
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundColor(.white.opacity(0.92))
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 16)
        }
    }
}

struct GpaCourseListRow: View {
    let name: String
    let credits: String
    let score: String
    let pointText: String
    let pending: Bool
    let editable: Bool
    var excludedFromGpa: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name.isEmpty ? "未命名课程" : name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AcademicPalette.ink)
                        .lineLimit(1)
                    Text(pending
                         ? "\(credits.isEmpty ? "—" : credits) 学分 · 待录入分数" + (excludedFromGpa ? " · 不计入GPA" : "")
                         : "\(credits.isEmpty ? "—" : credits) 学分 · \(score) 分 · \(AcademicCalc.gradeNameOfScore(Double(score)))" + (excludedFromGpa ? " · 不计入GPA" : ""))
                        .font(.system(size: 12))
                        .foregroundColor(AcademicPalette.muted)
                }
                Spacer()
                Text(pending ? "—" : pointText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(pending ? AcademicPalette.dim : AcademicPalette.brandInk)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(pending ? Color(hex: "EEF2F6") : AcademicPalette.hintBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(pending ? Color(hex: "E2E8F0") : Color(hex: "00A691").opacity(0.35), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                if editable {
                    Text("编辑")
                        .font(.system(size: 12))
                        .foregroundColor(AcademicPalette.dim)
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: "0F172A").opacity(0.06), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(!editable)
    }
}

struct GpaYearSemesterRow: View {
    let label: String
    let right: String
    var pending: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(pending ? AcademicPalette.muted : AcademicPalette.ink)
            Spacer()
            Text(right)
                .font(.system(size: 13))
                .foregroundColor(pending ? AcademicPalette.dim : AcademicPalette.muted)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(pending ? Color.white.opacity(0.55) : Color.white)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "0F172A").opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct GpaTermSkeletonRow: View {
    let label: String
    let right: String
    var current: Bool = false
    var future: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: current ? .semibold : .medium))
                    .foregroundColor(future ? AcademicPalette.ink.opacity(0.45) : AcademicPalette.ink)
                Spacer()
                Text(right)
                    .font(.system(size: 12))
                    .foregroundColor(current ? AcademicPalette.teal : AcademicPalette.dim)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(future ? Color(hex: "F9FAFB").opacity(0.55) : Color(hex: "F9FAFB"))
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(future)
    }
}

struct AcademicHintBar<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack { content() }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AcademicPalette.hintBg)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "00A691").opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AcademicPlainStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundColor(AcademicPalette.muted)
            Text(value).font(.system(size: 28, weight: .bold)).foregroundColor(AcademicPalette.ink)
            Text(subtitle).font(.system(size: 13)).foregroundColor(AcademicPalette.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "0F172A").opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

func academicToast(_ message: String) {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = scene.windows.first else { return }
    let label = UILabel()
    label.text = message
    label.textColor = .white
    label.font = .systemFont(ofSize: 13)
    label.textAlignment = .center
    label.numberOfLines = 0
    label.backgroundColor = UIColor.black.withAlphaComponent(0.78)
    label.layer.cornerRadius = 10
    label.clipsToBounds = true
    let width = min(window.bounds.width - 80, 280)
    label.frame = CGRect(x: (window.bounds.width - width) / 2, y: window.bounds.height - 140, width: width, height: 40)
    window.addSubview(label)
    UIView.animate(withDuration: 0.25, delay: 1.6, options: .curveEaseOut) {
        label.alpha = 0
    } completion: { _ in
        label.removeFromSuperview()
    }
}
