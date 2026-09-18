import SwiftUI
import ThubanCanvasCore
import WebKit

/// Renders a Canvas HTML fragment (page body, assignment description, syllabus, announcement) in the app's theme,
/// with a ⌘F find bar. Same-host images load through `CanvasSchemeHandler`; link clicks go to `AppModel.openLink`
/// (in-app when the link is a Canvas assignment/page/file, else the browser). Scrolls internally; give it a
/// flexible frame.
struct CanvasHTMLView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var html: String
    /// Optional heading rendered above the body inside the web view (keeps one scroll surface).
    var title: String? = nil
    @State private var find = WebFindState()

    var body: some View {
        VStack(spacing: 0) {
            if find.isVisible {
                WebFindBar(find: find)
            }
            CanvasWebView(html: html, title: title, find: find)
        }
        .onAppear { app.visibleWebViews += 1 }
        .onDisappear { app.visibleWebViews -= 1 }
        .onChange(of: app.findRequest) { _, _ in find.show() }
    }
}

/// Find-in-page state shared between the bar and the web view.
@MainActor
@Observable
final class WebFindState {
    var isVisible = false
    var query = ""
    var matchCount: Int?
    var matchIndex = 0
    var noMatch = false
    /// Bumped to move keyboard focus into the field.
    var focusRequest = 0
    weak var webView: WKWebView?

    func show() {
        isVisible = true
        focusRequest += 1
    }

    func hide() {
        isVisible = false
        query = ""
        matchCount = nil
        matchIndex = 0
        noMatch = false
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }

    /// New query: count matches, then select the first from the top of the document.
    func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard let webView, !text.isEmpty else { matchCount = nil; matchIndex = 0; noMatch = false; return }
        let escaped = text.lowercased().replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.getSelection().removeAllRanges(); (document.body.innerText || '').toLowerCase().split('\(escaped)').length - 1") { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                self.matchCount = (result as? Int) ?? (result as? Double).map(Int.init)
                self.matchIndex = 0
                self.step(forward: true)
            }
        }
    }

    /// Selects and scrolls to the next / previous match (wrapping).
    func step(forward: Bool) {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard let webView, !text.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = false
        configuration.wraps = true
        configuration.backwards = !forward
        webView.find(text, configuration: configuration) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.noMatch = !result.matchFound
                guard result.matchFound, let count = self.matchCount, count > 0 else { return }
                self.matchIndex = forward ? (self.matchIndex % count) + 1 : ((self.matchIndex + count - 2) % count) + 1
            }
        }
    }
}

/// The thin find bar above the page: field, "2 of 7", previous / next, close. Return = next, ⇧Return = previous,
/// Escape closes.
private struct WebFindBar: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var find: WebFindState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Glyph(.search, size: 13).foregroundStyle(theme.inkFaintColor)
                TextField("Find in page", text: $find.query)
                    .textFieldStyle(.plain)
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkColor)
                    .focused($focused)
                    .onSubmit { find.step(forward: NSApp.currentEvent?.modifierFlags.contains(.shift) != true) }
                    .onChange(of: find.query) { _, _ in find.search() }
                    .accessibilityLabel("Find in page")
            }
            .padding(.horizontal, 10)
            .frame(width: 260, height: 28)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(find.noMatch && !find.query.isEmpty ? theme.negColor : theme.line2Color, lineWidth: ThubanMetrics.hairline))
            Text(countText)
                .font(ThubanFont.small)
                .foregroundStyle(find.noMatch && !find.query.isEmpty ? theme.negTextColor : theme.inkDimColor)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .leading)
            IconButton(glyph: .chevronLeft, label: "Previous match", size: 26, iconSize: 13) { find.step(forward: false) }
                .disabled((find.matchCount ?? 0) == 0)
            IconButton(glyph: .chevronRight, label: "Next match", size: 26, iconSize: 13) { find.step(forward: true) }
                .disabled((find.matchCount ?? 0) == 0)
            Spacer(minLength: 0)
            Button("Done") { find.hide() }
                .buttonStyle(GhostButtonStyle(height: 26, horizontalPadding: 8))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close find bar")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(theme.panel2Color)
        .thubanHairline(.bottom, color: theme.lineColor)
        .onAppear { focused = true }
        .onChange(of: find.focusRequest) { _, _ in focused = true }
    }

    private var countText: String {
        guard !find.query.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        guard let count = find.matchCount else { return "" }
        if count == 0 { return "No matches" }
        return "\(find.matchIndex) of \(count)"
    }
}

/// The WKWebView itself.
private struct CanvasWebView: NSViewRepresentable {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var html: String
    var title: String?
    var find: WebFindState

    func makeCoordinator() -> Coordinator { Coordinator(app: app) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let client = app.client {
            configuration.setURLSchemeHandler(CanvasSchemeHandler(client: client), forURLScheme: CanvasHTML.scheme)
        }
        configuration.preferences.isElementFullscreenEnabled = true
        // `sanitize` already strips scripts from the document; make sure nothing proxied in can run either.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        context.coordinator.webView = webView
        find.webView = webView
        load(into: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        load(into: webView, context: context)
    }

    /// Compares a cheap key first so unrelated `app.settings` writes do not re-sanitize the fragment on every update.
    private func load(into webView: WKWebView, context: Context) {
        let key = Coordinator.Key(html: html, title: title, css: theme.cssVariables, textScale: textScale, host: app.host,
                                  dyslexia: app.settings.dyslexiaFont, reduceMotion: app.settings.reduceMotion)
        guard key != context.coordinator.lastKey else { return }
        context.coordinator.lastKey = key
        let document = Self.document(html: html, title: title, theme: theme, textScale: textScale, host: app.host,
                                     dyslexia: key.dyslexia, reduceMotion: key.reduceMotion)
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
        var lastKey: Key?

        /// Everything the rendered document depends on.
        struct Key: Equatable {
            var html: String
            var title: String?
            var css: String
            var textScale: Double
            var host: String
            var dyslexia: Bool
            var reduceMotion: Bool
        }

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
