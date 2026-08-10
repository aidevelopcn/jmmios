import SwiftUI
import WebKit

// MARK: - HTML 构建（对齐 Android buildMathHtml）
enum MathHTMLBuilder {
    static var baseURL: URL {
        if let url = Bundle.main.url(forResource: "katex.min", withExtension: "css", subdirectory: "math")?
            .deletingLastPathComponent() {
            return url
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("math", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return Bundle.main.bundleURL
    }

    static func needsRichRendering(_ markdown: String) -> Bool {
        let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text.contains("$$") || text.contains("\\(") || text.contains("\\[") || text.contains("\\)") { return true }
        if text.contains("```") || text.contains("**") || text.contains("__") || text.contains("##") { return true }
        if text.contains("![") || text.contains("<table") { return true }
        if text.range(of: #"\$[^\$\n]+\$"#, options: .regularExpression) != nil { return true }
        if text.contains("\n- ") || text.contains("\n* ") || text.contains("\n1. ") { return true }
        return false
    }

    static func buildHTML(markdown: String, streaming: Bool) -> String {
        let safeMd = jsonQuotedString(markdown)
        let cursor = streaming ? "<span class='cursor'>◊</span>" : ""
        // 原始字符串：JS 正则里的 \ $ 不会被 Swift 当作转义（对齐 Android Kotlin """）
        return #"""
        <!doctype html>
        <html>
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <link rel="stylesheet" href="katex.min.css">
          <style>
            body { margin:0; padding:0; background:transparent; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; }
            #content { color:#2d3748; font-size:14px; line-height:1.75; word-break:break-word; }
            p { margin: 0.5em 0; }
            pre { background:#1e1e1e; color:#d4d4d4; padding:10px; border-radius:8px; overflow-x:auto; }
            code { background:#f0f0f0; padding:2px 6px; border-radius:4px; }
            .katex-display { overflow-x:auto; overflow-y:hidden; margin:0.6em 0; }
            .cursor { color:#4ecdc4; animation:blink .9s infinite; }
            @keyframes blink { 0%,100%{opacity:1;} 50%{opacity:0;} }
          </style>
        </head>
        <body>
          <div id="content"></div>
          <script src="marked.min.js"></script>
          <script src="katex.min.js"></script>
          <script>
            const raw = \#(safeMd);
            function renderMath(md) {
              let idx = 0;
              const blocks = [];
              function protect(latex, display) {
                const key = "\\u0000MATH" + (idx++) + "\\u0000";
                let html = "";
                try {
                  html = katex.renderToString(latex.trim(), {displayMode:display, throwOnError:false, strict:"ignore"});
                } catch (e) {
                  html = latex;
                }
                blocks.push({key, html: display ? "<div class='katex-display'>" + html + "</div>" : html});
                return key;
              }
              md = md.replace(/\\\[([\\s\\S]*?)\\\]/g, (_, p1) => protect(p1, true));
              md = md.replace(/\$\$([\s\S]*?)\$\$/g, (_, p1) => protect(p1, true));
              md = md.replace(/\\\(([\s\S]*?)\\\)/g, (_, p1) => protect(p1, false));
              md = md.replace(/\$([^\$\n]+?)\$/g, (_, p1) => protect(p1, false));
              let html = marked.parse(md);
              blocks.forEach(b => { html = html.split(b.key).join(b.html); });
              return html;
            }
            document.getElementById('content').innerHTML = renderMath(raw) + "\#(cursor)";
            function reportHeight() {
              return Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight, document.documentElement.offsetHeight);
            }
            reportHeight();
          </script>
        </body>
        </html>
        """#
    }

    /// 将字符串转义为 JS 可用的 JSON 字面量（对齐 Android JSONObject.quote）
    private static func jsonQuotedString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let quoted = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return quoted
    }
}

// MARK: - UIKit 容器（对齐 Android MarkdownMathBubble：缓存 WebView + tag 比较 HTML）
final class MarkdownBubbleContainer: UIView, WKNavigationDelegate {
    let messageId: String
    private var webView: WKWebView
    private var lastHTML: String?
    private var throttleWorkItem: DispatchWorkItem?
    var onHeightChanged: ((CGFloat) -> Void)?

    init(messageId: String) {
        self.messageId = messageId
        self.webView = MarkdownWebViewPool.shared.acquire(messageId: messageId)
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: String, streaming: Bool) {
        let html = MathHTMLBuilder.buildHTML(markdown: content, streaming: streaming)
        guard lastHTML != html else { return }

        throttleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.loadHTML(html)
        }
        throttleWorkItem = work
        let delay = streaming ? 0.18 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func loadHTML(_ html: String) {
        lastHTML = html
        webView.tag = html.hashValue
        webView.loadHTMLString(html, baseURL: MathHTMLBuilder.baseURL)
    }

    func prepareForReuse() {
        throttleWorkItem?.cancel()
        throttleWorkItem = nil
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        MarkdownWebViewPool.shared.release(messageId: messageId, webView: webView)
    }

    private func measureHeight() {
        webView.evaluateJavaScript(
            "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight, document.documentElement.offsetHeight)"
        ) { [weak self] result, _ in
            guard let self else { return }
            let parsed: CGFloat? = {
                if let h = result as? Double { return CGFloat(h) }
                if let h = result as? Int { return CGFloat(h) }
                return nil
            }()
            guard let h = parsed, h > 0 else { return }
            let next = max(h + 4, 44)
            MarkdownWebViewPool.shared.setHeight(next, for: self.messageId)
            DispatchQueue.main.async {
                self.onHeightChanged?(next)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        measureHeight()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.measureHeight()
        }
    }
}

// MARK: - SwiftUI 包装
struct MarkdownMathBubbleView: UIViewRepresentable {
    let messageId: String
    let content: String
    let isStreaming: Bool
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> MarkdownBubbleContainer {
        let view = MarkdownBubbleContainer(messageId: messageId)
        view.onHeightChanged = { h in
            if abs(height - h) > 1 { height = h }
        }
        height = MarkdownWebViewPool.shared.cachedHeight(for: messageId)
        view.update(content: content, streaming: isStreaming)
        return view
    }

    func updateUIView(_ uiView: MarkdownBubbleContainer, context: Context) {
        uiView.onHeightChanged = { h in
            if abs(height - h) > 1 { height = h }
        }
        uiView.update(content: content, streaming: isStreaming)
    }

    static func dismantleUIView(_ uiView: MarkdownBubbleContainer, coordinator: ()) {
        uiView.prepareForReuse()
    }
}
