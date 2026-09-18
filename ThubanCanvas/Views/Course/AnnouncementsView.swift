import SwiftUI
import ThubanCanvasCore

/// Course announcements, newest first: title, author, date, a three-line preview, unread dot, attachment count.
struct AnnouncementsView: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession

    var body: some View {
        ResourceStateView(resource: session.announcements, emptyTitle: "No announcements",
                          emptyMessage: "Nothing has been posted in the last six months.", isEmpty: { $0.isEmpty },
                          retry: { await session.loadAnnouncements(force: true) }) { announcements in
            let sorted = announcements.sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            let unread = sorted.filter { $0.readState == "unread" }.count
            SectionPage {
                SectionHeader("Announcements", count: sorted.count) {
                    if unread > 0 { Chip("\(unread) unread", kind: .accent) }
                }
                ForEach(sorted) { topic in
                    AnnouncementRow(topic: topic) { session.path.append(.discussion(topic.id)) }
                }
            }
        }
        .task(id: session.id) { await session.loadAnnouncements() }
    }
}

/// One announcement card.
private struct AnnouncementRow: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var topic: DiscussionTopic
    var action: () -> Void

    private var isUnread: Bool { topic.readState == "unread" }
    private var author: String { topic.author?.displayName ?? topic.userName ?? "Canvas" }
    private var preview: String { CanvasHTML.plainText(topic.message, limit: 320) }

    var body: some View {
        ListRowCard(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isUnread ? theme.accentColor : .clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(topic.title)
                            .font(ThubanFont.scaled(15, scale: textScale, weight: .semibold))
                            .foregroundStyle(theme.inkColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if let posted = topic.postedAt {
                            Text(WorkText.day(posted))
                                .font(ThubanFont.scaled(12.5, scale: textScale))
                                .foregroundStyle(theme.inkDimColor)
                                .monospacedDigit()
                                .help(WorkText.full(posted))
                        }
                    }
                    HStack(spacing: 6) {
                        Text(author).font(ThubanFont.scaled(12.5, scale: textScale)).foregroundStyle(theme.inkDimColor)
                        if let posted = topic.postedAt {
                            Text("·").foregroundStyle(theme.inkFaintColor)
                            Text(posted.formatted(date: .omitted, time: .shortened)).font(ThubanFont.scaled(12.5, scale: textScale)).foregroundStyle(theme.inkFaintColor)
                        }
                        if let attachments = topic.attachments, !attachments.isEmpty {
                            Text("·").foregroundStyle(theme.inkFaintColor)
                            HStack(spacing: 3) {
                                Image(systemName: "paperclip").font(.system(size: 11, weight: .semibold))
                                Text(WorkText.count(attachments.count, "attachment"))
                            }
                            .font(ThubanFont.scaled(12.5, scale: textScale))
                            .foregroundStyle(theme.inkDimColor)
                        }
                    }
                    if !preview.isEmpty {
                        Text(preview)
                            .font(ThubanFont.scaled(13.5, scale: textScale))
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Glyph(.chevronRight, size: 12).foregroundStyle(theme.inkFaintColor).padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [isUnread ? "Unread announcement" : "Announcement", topic.title, "from \(author)"]
        if let posted = topic.postedAt { parts.append(WorkText.full(posted)) }
        if let attachments = topic.attachments, !attachments.isEmpty { parts.append(WorkText.count(attachments.count, "attachment")) }
        return parts.joined(separator: ", ")
    }
}
