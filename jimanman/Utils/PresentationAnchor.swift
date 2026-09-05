import UIKit

enum PresentationAnchor {
    /// iPad 上 keyWindow 可能为空，需从 foreground scene 取 window
    static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        for scene in scenes {
            if let window = scene.windows.first(where: \.isKeyWindow) {
                return window
            }
        }
        for scene in scenes {
            if let window = scene.windows.first {
                return window
            }
        }
        return nil
    }
}
