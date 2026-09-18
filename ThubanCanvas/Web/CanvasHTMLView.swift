import SwiftUI
import ThubanCanvasCore
import WebKit

/// Renders a Canvas HTML fragment (page body, assignment description, syllabus, announcement) in the app's theme.
/// Same-host images load through `CanvasSchemeHandler`; link clicks go to `AppModel.openLink` (in-app when the
/// link is a Canvas assignment/page/file, else the browser). Scrolls internally; give it a flexible frame.
struct CanvasHTMLView: NSViewRepresentable {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var html: String
    /// Optional heading rendered above the body inside the web view (keeps one scroll surface).
    var title: String?

    func makeCoordinator() -> Coordinator { Coordinator(app: app) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let client = app.client {
            configuration.setURLSchemeHandler(CanvasSchemeHandler(client: client), forURLScheme: CanvasHTML.scheme)
        }
        configuration.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        context.coordinator.webView = webView
        load(into: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        load(into: webView, context: context)
    }

    private func load(into webView: WKWebView, context: Context) {
        let document = Self.document(html: html, title: title, theme: theme, textScale: textScale, host: app.host,
                                     dyslexia: app.settings.dyslexiaFont, reduceMotion: app.settings.reduceMotion)
        guard document != context.coordinator.lastDocument else { return }
        context.coordinator.lastDocument = document
        webView.loadHTMLString(document, baseURL: URL(string: app.host))
    }

    /// Full HTML document: theme variables, typography, and the sanitized fragment.
    static func document(html: String, title: String?, theme: ResolvedTheme, textScale: Double, host: String, dyslexia: Bool, reduceMotion: Bool) -> String {
        let body = CanvasHTML.sanitize(html, host: host)
        let heading = title.map { "<h1 class=\"thuban-title\">\(escape($0))</h1>" } ?? ""
        let fontStack = dyslexia
            ? "\"OpenDyslexic\", \"Comic Sans MS\", \"Atkinson Hyperlegible\", -apple-system, sans-serif"
            : "-apple-system, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(theme.cssVariables)
        html { background: transparent; }
        body { margin: 0; padding: 20px 28px 40px; color: var(--ink); font: \(15 * textScale)px/1.55 \(fontStack);
               -webkit-font-smoothing: antialiased; max-width: 860px; word-wrap: break-word; }
        .thuban-title { font-family: "New York", "Iowan Old Style", Georgia, serif; font-weight: 600; font-size: \(26 * textScale)px; line-height: 1.2; margin: 0 0 16px; }
        h1, h2, h3, h4 { font-family: "New York", "Iowan Old Style", Georgia, serif; font-weight: 600; line-height: 1.25; color: var(--ink); margin: 1.4em 0 .5em; }
        h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.15em; } h4 { font-size: 1em; }
        p { margin: 0 0 .9em; }
        a { color: var(--accent-text); text-decoration: none; border-bottom: 1px solid var(--accent-tint); }
        a:hover { border-bottom-color: var(--accent-text); }
        img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
        iframe { min-height: 320px; width: 100%; border: 1px solid var(--line); }
        table { border-collapse: collapse; margin: 1em 0; max-width: 100%; }
        th, td { border: 1px solid var(--line-2); padding: 6px 10px; text-align: left; vertical-align: top; }
        th { background: var(--panel-2); font-weight: 600; }
        pre, code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .92em; }
        pre { background: var(--panel-2); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px; overflow: auto; }
        blockquote { margin: 1em 0; padding: 4px 0 4px 16px; border-left: 2px solid var(--line-2); color: var(--ink-dim); }
        hr { border: 0; border-top: 1px solid var(--line); margin: 1.5em 0; }
        ul, ol { padding-left: 1.4em; }
        li { margin: .25em 0; }
        [style*="background"] { background-image: none !important; }
        [style*="color"] { color: inherit !important; }
        [style*="font-family"] { font-family: inherit !important; }
        [style*="font-size"] { font-size: inherit !important; }
        [style*="width"] { max-width: 100% !important; }
        .dp-wrapper, [class^="dp-"] { background: transparent !important; box-shadow: none !important; }
        \(reduceMotion ? "*, *::before, *::after { animation: none !important; transition: none !important; }" : "")
        ::selection { background: var(--accent-tint); }
        </style></head><body>\(heading)\(body)</body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let app: AppModel
        weak var webView: WKWebView?
        var lastDocument: String?

        init(app: AppModel) { self.app = app }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            let target = url.scheme == CanvasHTML.scheme ? (CanvasHTML.original(url) ?? url) : url
            app.openLink(target)
        }
    }
}
