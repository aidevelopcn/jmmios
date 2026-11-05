import WebKit

final class MarkdownWebViewPool {
    static let shared = MarkdownWebViewPool()
    private var heightCache: [String: CGFloat] = [:]
    private init() {}

    func cachedHeight(for messageId: String) -> CGFloat {
        heightCache[messageId] ?? 0
    }

    func setHeight(_ height: CGFloat, for messageId: String) {
        heightCache[messageId] = max(height, 44)
    }

    func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            _ = QaShellStore.fileURL
        }
    }
}
