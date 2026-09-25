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
        CanvasHTMLDocument.build(html: html, title: title, theme: theme, textScale: textScale, host: host, dyslexia: dyslexia, reduceMotion: reduceMotion)
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
