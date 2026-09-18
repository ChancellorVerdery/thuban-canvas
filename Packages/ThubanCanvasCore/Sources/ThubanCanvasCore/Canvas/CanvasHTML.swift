import Foundation
import SwiftSoup

/// Cleans Canvas-authored HTML for in-app display and produces plain-text previews.
public enum CanvasHTML {
    /// Custom scheme the app's WKWebView handler serves authenticated Canvas resources through.
    public static let scheme = "thubancanvas"

    /// Plain text for list previews: tags stripped, whitespace collapsed, at most `limit` characters.
    public static func plainText(_ html: String?, limit: Int = 200) -> String {
        guard let html, !html.isEmpty else { return "" }
        let text: String
        if let document = try? SwiftSoup.parse(html), let body = try? document.text() {
            text = body
        } else {
            text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Rewrites a Canvas HTML fragment for the viewer:
    /// - drops `<script>`, `<style>`, `<link>` and inline event handlers,
    /// - routes same-host images / iframes / media through `thubancanvas://` so the scheme handler can attach the token,
    /// - turns `data-api-endpoint` links into plain hrefs.
    public static func sanitize(_ html: String, host: String) -> String {
        guard let document = try? SwiftSoup.parseBodyFragment(html) else { return html }
        do {
            try document.select("script, style, link, iframe[src*=youtube] ~ noscript, noscript").remove()
            for element in try document.getAllElements() {
                for attribute in element.getAttributes()?.asList() ?? [] where attribute.getKey().lowercased().hasPrefix("on") {
                    try element.removeAttr(attribute.getKey())
                }
            }
            for image in try document.select("img[src], source[src], video[src], audio[src], embed[src]") {
                let src = try image.attr("src")
                if let rewritten = proxied(src, host: host) { try image.attr("src", rewritten) }
            }
            for frame in try document.select("iframe[src]") {
                let src = try frame.attr("src")
                if let rewritten = proxied(src, host: host) { try frame.attr("src", rewritten) }
            }
            for anchor in try document.select("a[href]") {
                let href = try anchor.attr("href")
                if href.hasPrefix("/") { try anchor.attr("href", host + href) }
            }
            return try document.body()?.html() ?? html
        } catch {
            return html
        }
    }

    /// `https://host/...` or `/...` on the Canvas host → `thubancanvas://host/...`; other hosts unchanged.
    public static func proxied(_ src: String, host: String) -> String? {
        guard let hostURL = URL(string: host), let hostName = hostURL.host else { return nil }
        if src.hasPrefix("/") { return "\(scheme)://\(hostName)\(src)" }
        guard let url = URL(string: src), url.host == hostName, url.scheme == "https" else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components?.string
    }

    /// The reverse mapping for the scheme handler.
    public static func original(_ proxied: URL) -> URL? {
        var components = URLComponents(url: proxied, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }

    /// Finds `/courses/:c/assignments/:a`, `/courses/:c/pages/:slug`, `/courses/:c/files/:f`, `/courses/:c/modules/items/:i`
    /// and `/courses/:c/discussion_topics/:d` links so the app can open them in place instead of a browser.
    public enum Link: Equatable, Sendable {
        case assignment(course: CanvasID, id: CanvasID)
        case page(course: CanvasID, slug: String)
        case file(course: CanvasID?, id: CanvasID)
        case moduleItem(course: CanvasID, id: CanvasID)
        case discussion(course: CanvasID, id: CanvasID)
        case quiz(course: CanvasID, id: CanvasID)
        case course(CanvasID)
    }

    public static func classify(_ url: URL, host: String) -> Link? {
        guard let hostName = URL(string: host)?.host, url.host == hostName else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count >= 2, parts[0] == "files", let id = CanvasID(parts[1]) { return .file(course: nil, id: id) }
        guard parts.count >= 2, parts[0] == "courses", let course = CanvasID(parts[1]) else { return nil }
        guard parts.count >= 4 else { return parts.count == 2 ? .course(course) : nil }
        switch parts[2] {
        case "assignments": return CanvasID(parts[3]).map { .assignment(course: course, id: $0) }
        case "pages": return .page(course: course, slug: parts[3])
        case "files": return CanvasID(parts[3]).map { .file(course: course, id: $0) }
        case "discussion_topics": return CanvasID(parts[3]).map { .discussion(course: course, id: $0) }
        case "quizzes": return CanvasID(parts[3]).map { .quiz(course: course, id: $0) }
        case "modules": return parts.count >= 5 && parts[3] == "items" ? CanvasID(parts[4]).map { .moduleItem(course: course, id: $0) } : nil
        default: return nil
        }
    }
}
