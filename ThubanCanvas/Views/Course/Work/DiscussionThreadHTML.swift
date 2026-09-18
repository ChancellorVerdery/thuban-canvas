import Foundation
import ThubanCanvasCore

/// Composes one HTML fragment for `CanvasHTMLView`: the topic message followed by the threaded replies, each with
/// a small header (name, date, unread dot) and indented by depth. Entry messages are Canvas HTML; the view sanitizes
/// the whole fragment before rendering, so only structure and inline layout styles are added here.
enum DiscussionThreadHTML {
    static let indentStep = 24
    static let maxIndentLevels = 5

    static func compose(topic: DiscussionTopic, thread: DiscussionView?, now: Date = Date()) -> String {
        var html = topic.message ?? ""
        guard let thread else { return html }
        let names = Dictionary((thread.participants ?? []).map { ($0.id, $0.displayName ?? "") }, uniquingKeysWith: { first, _ in first })
        let unread = Set(thread.unreadEntries ?? [])
        let entries = (thread.view ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        let total = count(entries)
        html += """
        <p style="margin: 32px 0 4px; padding-top: 14px; border-top: 1px solid var(--line-2);"><b>\(total == 0 ? "No replies yet" : WorkText.count(total, "reply", "replies"))</b>\(unread.isEmpty || total == 0 ? "" : " <small style=\"opacity:.65\">· \(unread.count) unread</small>")</p>
        """
        for entry in entries { html += render(entry, depth: 0, names: names, unread: unread, now: now) }
        return html
    }

    /// Entries including nested replies (deleted placeholders excluded).
    static func count(_ entries: [DiscussionEntry]) -> Int {
        entries.reduce(0) { $0 + ($1.deleted == true ? 0 : 1) + count($1.replies ?? []) }
    }

    private static func render(_ entry: DiscussionEntry, depth: Int, names: [CanvasID: String], unread: Set<CanvasID>, now: Date) -> String {
        let replies = (entry.replies ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if entry.deleted == true, replies.isEmpty { return "" }
        let indent = min(depth, maxIndentLevels) * indentStep
        let name = escape(names[entry.userId ?? -1].flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown")
        let date = entry.createdAt.map { WorkText.full($0, now: now) } ?? ""
        let dot = unread.contains(entry.id)
            ? "<span aria-label=\"unread\" style=\"display:inline-block;width:7px;height:7px;border-radius:4px;background:var(--accent);margin-right:7px;vertical-align:middle\"></span>"
            : ""
        var body: String
        if entry.deleted == true {
            body = "<p style=\"margin:0 0 4px\"><i><small style=\"opacity:.65\">This reply was deleted.</small></i></p>"
        } else {
            body = entry.message ?? ""
            if let attachments = entry.attachments, !attachments.isEmpty {
                let links = attachments.map { file -> String in
                    let href = escape(file.url ?? "")
                    return "<a href=\"\(href)\">\(escape(file.displayName))</a>"
                }.joined(separator: " · ")
                body += "<p style=\"margin:4px 0 0\"><small>Attachment: \(links)</small></p>"
            }
        }
        var html = """
        <div style="margin-left: \(indent)px; padding: 12px 0 6px; border-top: 1px solid var(--line);">
        <p style="margin: 0 0 6px;">\(dot)<b>\(name)</b> <small style="opacity:.65">· \(escape(date))</small></p>
        \(body)
        </div>
        """
        for reply in replies { html += render(reply, depth: depth + 1, names: names, unread: unread, now: now) }
        return html
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
