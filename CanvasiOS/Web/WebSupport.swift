import SafariServices
import SwiftUI
import ThubanCanvasCore
import WebKit

/// Canvas HTML (descriptions, pages, syllabus, announcements) in the app theme, sized to its content so it sits in
/// the surrounding scroll view. Same-host images load through the shared `CanvasSchemeHandler`; links go to
/// `AppModel.openLink` (in-app for Canvas assignments/pages/files, Safari otherwise). Page scripts never run.
struct HTMLContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanFontScale) private var scale
    var html: String
    var padding = "14px 16px 16px"
    @State private var height: CGFloat = 40

    var body: some View {
        HTMLWebView(html: html, document: document, client: app.client, host: app.host, height: $height) { url in app.openLink(url) }
            .frame(height: max(height, 24))
    }

    private var document: String {
        CanvasHTMLDocument.build(html: html, title: nil, theme: theme, textScale: Double(scale), host: app.host,
                                 dyslexia: app.settings.dyslexiaFont, reduceMotion: app.settings.reduceMotion,
                                 bodyPadding: padding, baseSize: 16, maxWidth: "none")
    }
}

private struct HTMLWebView: UIViewRepresentable {
    var html: String
    var document: String
    var client: CanvasClient?
    var host: String
    @Binding var height: CGFloat
    var open: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, open: open) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let client {
            configuration.setURLSchemeHandler(CanvasSchemeHandler(client: client), forURLScheme: CanvasHTML.scheme)
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = [.link]
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 40), configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.observe(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        webView.loadHTMLString(document, baseURL: URL(string: host.isEmpty ? "about:blank" : host))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var open: (URL) -> Void
        var lastDocument: String?
        private var observation: NSKeyValueObservation?

        init(height: Binding<CGFloat>, open: @escaping (URL) -> Void) {
            self.height = height
            self.open = open
        }

        func observe(_ webView: WKWebView) {
            observation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
                let value = scrollView.contentSize.height
                Task { @MainActor in self?.update(value) }
            }
        }

        private func update(_ value: CGFloat) {
            guard value > 0, abs(value - height.wrappedValue) > 1 else { return }
            height.wrappedValue = value
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] result, _ in
                let value = (result as? Double).map { CGFloat($0) } ?? (result as? Int).map { CGFloat($0) }
                Task { @MainActor in if let value { self?.update(value) } }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            open(url.scheme == CanvasHTML.scheme ? (CanvasHTML.original(url) ?? url) : url)
        }
    }
}

/// Safari inside the app (Submit in Canvas, external links). Canvas itself handles every write there.
struct SafariView: UIViewControllerRepresentable {
    var url: URL
    var tint: Color

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(tint)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
