import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    @ViewBuilder
    func hideScrollContentBackgroundIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func dismissKeyboardOnScrollIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}

// MARK: - Toast 提示（对齐 Android Toast）

struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
    }
}

extension View {
    func toastOverlay(message: String, isShowing: Bool) -> some View {
        overlay(alignment: .bottom) {
            if isShowing {
                ToastBanner(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowing)
    }
}

enum ToastPresenter {
    static func scheduleAutoHide(
        task: inout Task<Void, Never>?,
        isShowing: Binding<Bool>,
        delaySeconds: Double = 2.0
    ) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            await MainActor.run { isShowing.wrappedValue = false }
        }
    }
}

enum AppSettingsOpener {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
