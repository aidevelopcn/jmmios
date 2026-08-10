import WebKit

/// WebView 复用池 + 高度缓存（对齐 Android webViewCache / answerHeightCache）
final class MarkdownWebViewPool {
    static let shared = MarkdownWebViewPool()

    private var storage: [String: WKWebView] = [:]
    private var heightCache: [String: CGFloat] = [:]
    private let maxCached = 16

    private init() {}

    func cachedHeight(for messageId: String) -> CGFloat {
        heightCache[messageId] ?? 56
    }

    func setHeight(_ height: CGFloat, for messageId: String) {
        heightCache[messageId] = max(height, 44)
    }

    func acquire(messageId: String) -> WKWebView {
        if let existing = storage.removeValue(forKey: messageId) {
            existing.scrollView.isScrollEnabled = false
            existing.scrollView.bounces = false
            return existing
        }
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func release(messageId: String, webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        if storage.count >= maxCached, let key = storage.keys.first {
            storage.removeValue(forKey: key)
        }
        storage[messageId] = webView
    }
}
