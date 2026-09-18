import SwiftUI
import ThubanCanvasCore

/// Course discussions: pinned topics first, then by most recent reply. Rows show reply count, last activity,
/// unread count and whether the discussion is graded.
struct DiscussionsView: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession

    var body: some View {
        ResourceStateView(resource: session.discussions, emptyTitle: "No discussions",
                          emptyMessage: "This course has no discussion topics yet.", isEmpty: { $0.isEmpty },
                          retry: { await session.loadDiscussions(force: true) }) { discussions in
            let sorted = discussions.filter { $0.isAnnouncement != true }.sorted(by: order)
            let pinned = sorted.filter { $0.pinned == true }
            let rest = sorted.filter { $0.pinned != true }
            SectionPage {
                if !pinned.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Pinned", count: pinned.count)
                        ForEach(pinned) { topic in DiscussionRow(topic: topic) { session.path.append(.discussion(topic.id)) } }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(pinned.isEmpty ? "Discussions" : "All discussions", count: rest.count)
                    ForEach(rest) { topic in DiscussionRow(topic: topic) { session.path.append(.discussion(topic.id)) } }
                }
            }
        }
        .task(id: session.id) { await session.loadDiscussions() }
    }

    private func order(_ a: DiscussionTopic, _ b: DiscussionTopic) -> Bool {
        if (a.pinned == true) != (b.pinned == true) { return a.pinned == true }
        let da = a.lastReplyAt ?? a.postedAt ?? .distantPast
        let db = b.lastReplyAt ?? b.postedAt ?? .distantPast
        if da != db { return da > db }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}

/// One discussion topic row.
private struct DiscussionRow: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var topic: DiscussionTopic
    var action: () -> Void

    /// Canvas sends `read_state: "unread"` with `unread_count: 0` for a never-opened topic without replies.
    private var unreadReplies: Int { topic.unreadCount ?? 0 }
    private var isUnread: Bool { unreadReplies > 0 || topic.readState == "unread" }
    private var isLocked: Bool { topic.locked == true || topic.lockedForUser == true }

    var body: some View {
        ListRowCard(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: topic.pinned == true ? "pin" : "bubble.left.and.bubble.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isUnread ? theme.brassInkColor : theme.inkFaintColor)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(ThubanFont.scaled(14, scale: textScale, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(activityText)
                            .font(ThubanFont.scaled(12.5, scale: textScale))
                            .foregroundStyle(theme.inkDimColor)
                            .monospacedDigit()
                        if let author = topic.author?.displayName ?? topic.userName {
                            Text("·").foregroundStyle(theme.inkFaintColor)
                            Text(author).font(ThubanFont.scaled(12.5, scale: textScale)).foregroundStyle(theme.inkFaintColor).lineLimit(1)
                        }
                        if isLocked { Glyph(.lock, size: 12).foregroundStyle(theme.inkFaintColor) }
                    }
                }
                Spacer(minLength: 12)
                if unreadReplies > 0 { Chip("\(unreadReplies) unread", kind: .accent) }
                else if isUnread { Chip("Unread", kind: .accent) }
                if topic.assignmentId != nil { Chip("Graded", kind: .signal) }
                if let count = topic.discussionSubentryCount {
                    Text(WorkText.count(count, "reply", "replies"))
                        .font(ThubanFont.scaled(12.5, scale: textScale))
                        .foregroundStyle(theme.inkDimColor)
                        .monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                }
                Glyph(.chevronRight, size: 12).foregroundStyle(theme.inkFaintColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var activityText: String {
        if let last = topic.lastReplyAt { return "Last reply " + WorkText.day(last) }
        if let posted = topic.postedAt { return "Posted " + WorkText.day(posted) }
        if let delayed = topic.delayedPostUntil, delayed > Date() { return "Opens " + WorkText.day(delayed) }
        return "No replies yet"
    }

    private var accessibilityText: String {
        var parts = [topic.pinned == true ? "Pinned discussion" : "Discussion", topic.title, activityText]
        if let count = topic.discussionSubentryCount { parts.append(WorkText.count(count, "reply", "replies")) }
        if unreadReplies > 0 { parts.append("\(unreadReplies) unread") } else if isUnread { parts.append("unread") }
        if topic.assignmentId != nil { parts.append("graded") }
        if isLocked { parts.append("locked") }
        return parts.joined(separator: ", ")
    }
}
