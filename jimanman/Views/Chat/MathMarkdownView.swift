import SwiftUI
import WebKit
import QuartzCore

enum MathHTMLBuilder {
    static func bundledFile(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "math") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.main.url(forResource: "\(name).\(ext)", withExtension: nil)
    }

    static func needsRichRendering(_ markdown: String) -> Bool {
        let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text.contains("$$") || text.contains("\\(") || text.contains("\\[") || text.contains("\\)") { return true }
        if text.contains("\\") { return true }
        if text.contains("```") || text.contains("**") || text.contains("__") || text.contains("##") { return true }
        if text.contains("![") || text.contains("<table") { return true }
        if text.range(of: #"\$[^\$\n]+\$"#, options: .regularExpression) != nil { return true }
        if text.contains("\n- ") || text.contains("\n* ") || text.contains("\n1. ") { return true }
        return false
    }

    static func jsonQuotedString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let quoted = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return quoted
    }

    static func readBundled(_ name: String, _ ext: String) -> String {
        guard let url = bundledFile(name, ext) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func scriptTag(_ source: String) -> String {
        let safe = source.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive)
        return "<script>\n\(safe)\n</script>"
    }

    static func buildInlinedShellHTML() -> String {
        let css = readBundled("katex.min", "css")
        let marked = readBundled("marked.min", "js")
        let katex = readBundled("katex.min", "js")
        let render = readBundled("qa-render", "js")
        let pageCSS = """
        html, body { margin:0; padding:0; width:100%; max-width:100%; height:auto !important; min-height:0 !important; overflow:hidden !important; background:transparent; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; -webkit-tap-highlight-color:transparent; outline:none; }
        * { -webkit-tap-highlight-color:transparent; outline:none; box-sizing:border-box; }
        #content { color:#1f2937; font-size:15px; line-height:1.85; word-break:break-word; overflow-wrap:anywhere; overflow:visible !important; max-width:100%; height:auto !important; padding:4px 0 6px; }
        p { margin: 0.55em 0; padding: 0.15em 0; }
        strong { font-weight: 700; }
        hr { border: none; border-top: 1px solid #E5E7EB; margin: 1em 0; }
        h1,h2,h3,h4 { font-size:16px; font-weight:700; margin:0.85em 0 0.4em; }
        ul,ol { margin: 0.4em 0 0.4em 1.2em; padding: 0; }
        li { margin: 0.7em 0; }
        blockquote { margin: 0.7em 0; padding: 0.15em 0 0.15em 0.75em; border-left: 3px solid #22C7BE; color: #374151; }
        pre { background:#1e1e1e; color:#d4d4d4; padding:10px; border-radius:8px; overflow-x:auto; max-width:100%; }
        code { background:#f0f0f0; padding:2px 6px; border-radius:4px; }
        img { max-width:100%; height:auto; border-radius:12px; display:block; }
        .katex-html, .katex .vlist-t, .katex .vlist-r { overflow: visible !important; }
        .katex-mathml { position:absolute !important; clip:rect(1px, 1px, 1px, 1px) !important; width:1px !important; height:1px !important; overflow:hidden !important; }
        .katex, .katex * { overflow-wrap:normal !important; word-break:normal !important; }
        .katex { font-size: 1.1em; }
        .katex-display { display:block; margin:0.35em 0; padding:0.35em 0 0.2em; text-align:left; overflow:visible !important; max-width:none; }
        .katex-display > .katex { max-width:none; display:inline-block; overflow:visible !important; }
        .math-scroll { width:100%; max-width:100%; overflow-x:auto; overflow-y:hidden; -webkit-overflow-scrolling:touch; touch-action:pan-x; margin:0.35em 0; padding:0 2px 8px; }
        .math-plain, .katex-error { color:#1f2937 !important; background:transparent !important; font-size:15px; }
        .cursor { color:#4ecdc4; animation:blink .9s infinite; }
        @keyframes blink { 0%,100%{opacity:1;} 50%{opacity:0;} }
        """
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
          <style>
          \(css)
          \(pageCSS)
          </style>
        </head>
        <body>
          <div id="content"></div>
          \(scriptTag(marked))
          \(scriptTag(katex))
          \(scriptTag(render))
        </body>
        </html>
        """
    }
}

enum QaShellStore {
    static let fileURL: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jmm-qa-shell-42", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("index.html")
        let html = MathHTMLBuilder.buildInlinedShellHTML()
        try? html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }()
}

final class MarkdownBubbleContainer: UIView, WKNavigationDelegate {
    let messageId: String
    private let webView: WKWebView
    private var pageReady = false
    private var shellLoading = false
    private var lastKey = ""
    private var pending: (String, Bool)?
    private var lastPushAt: TimeInterval = 0
    private var flushWork: DispatchWorkItem?
    var onHeightChanged: ((CGFloat) -> Void)?

    init(messageId: String) {
        self.messageId = messageId
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let atPolyfill = """
        if (!Array.prototype.at) {
          Array.prototype.at = function(n) {
            n = Math.trunc(Number(n)) || 0;
            if (n < 0) n += this.length;
            if (n < 0 || n >= this.length) return undefined;
            return this[n];
          };
        }
        """
        config.userContentController.addUserScript(
            WKUserScript(source: atPolyfill, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 24, height: 120), configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        self.webView = view
        super.init(frame: .zero)
        backgroundColor = .clear
        webView.navigationDelegate = self
        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        loadShellIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: String, streaming: Bool) {
        pending = (content, streaming)
        let key = "\(streaming)\n\(content)"
        if key == lastKey && pageReady { return }
        lastKey = key
        flushWork?.cancel()
        if streaming && pageReady && lastPushAt > 0 {
            let wait = 0.25 - (CACurrentMediaTime() - lastPushAt)
            if wait > 0 {
                let work = DispatchWorkItem { [weak self] in
                    self?.apply(content: content, streaming: true)
                }
                flushWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
                return
            }
        }
        apply(content: content, streaming: streaming)
    }

    private func apply(content: String, streaming: Bool) {
        pending = (content, streaming)
        if !pageReady {
            loadShellIfNeeded()
            return
        }
        lastPushAt = CACurrentMediaTime()
        pushContent(content, streaming: streaming, attempt: 0)
    }

    private func loadShellIfNeeded() {
        guard !pageReady, !shellLoading else { return }
        shellLoading = true
        let htmlURL = QaShellStore.fileURL
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    private func pushContent(_ content: String, streaming: Bool, attempt: Int) {
        let js = "window.setQaContent(\(MathHTMLBuilder.jsonQuotedString(content)), \(streaming ? "true" : "false"), false)"
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self else { return }
            if error != nil || result == nil, attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.pushContent(content, streaming: streaming, attempt: attempt + 1)
                }
                return
            }
            self.publishHeight(result)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.measureHeight()
            }
        }
    }

    private func measureHeight() {
        webView.evaluateJavaScript(
            "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, (document.getElementById('content')||{}).scrollHeight||0)"
        ) { [weak self] result, _ in
            self?.publishHeight(result)
        }
    }

    private func publishHeight(_ result: Any?) {
        let parsed: CGFloat? = {
            if let n = result as? NSNumber { return CGFloat(truncating: n) }
            if let h = result as? Double { return CGFloat(h) }
            if let h = result as? Int { return CGFloat(h) }
            if let s = result as? String, let h = Double(s) { return CGFloat(h) }
            return nil
        }()
        guard let h = parsed, h > 8 else { return }
        let next = max(h + 8, 48)
        MarkdownWebViewPool.shared.setHeight(next, for: messageId)
        DispatchQueue.main.async {
            self.onHeightChanged?(next)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        shellLoading = false
        if let pending {
            apply(content: pending.0, streaming: pending.1)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        shellLoading = false
        pageReady = true
        if let pending {
            apply(content: pending.0, streaming: pending.1)
        }
    }
}

struct MarkdownMathBubbleView: UIViewRepresentable {
    let messageId: String
    let content: String
    let isStreaming: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> MarkdownBubbleContainer {
        let view = MarkdownBubbleContainer(messageId: messageId)
        view.onHeightChanged = { h in
            context.coordinator.setHeight(h)
        }
        let cached = MarkdownWebViewPool.shared.cachedHeight(for: messageId)
        if cached > 48 { context.coordinator.setHeight(cached) }
        view.update(content: content, streaming: isStreaming)
        return view
    }

    func updateUIView(_ uiView: MarkdownBubbleContainer, context: Context) {
        context.coordinator.height = $height
        uiView.onHeightChanged = { h in
            context.coordinator.setHeight(h)
        }
        uiView.update(content: content, streaming: isStreaming)
    }

    final class Coordinator {
        var height: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.height = height }
        func setHeight(_ h: CGFloat) {
            if abs(height.wrappedValue - h) > 1 {
                height.wrappedValue = h
            }
        }
    }
}
