import SwiftUI
import ThubanCanvasCore

/// The newest announcements across the starred courses, with a two-line plain-text preview.
struct HomeAnnouncementsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var limit: Int = 6

    var body: some View {
        HomeCard("Announcements") {
            ResourceStateView(resource: app.announcements, retry: reload) { topics in
                let recent = self.recent(topics)
                if recent.isEmpty {
                    HomeEmptyRow(symbol: "megaphone", text: "No announcements in the last six months.")
                } else {
                    HomeRowList(data: recent) { topic in
                        HomeRow(label: rowLabel(topic), action: { open(topic) }) {
                            row(topic)
                        }
                    }
                }
            }
        }
    }

    private func row(_ topic: DiscussionTopic) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CourseDot(tint: topic.courseId.flatMap { app.sessions[$0]?.preferences.tint })
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(topic.title)
                        .font(ThubanFont.scaled(14, scale: textScale, weight: .medium))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if topic.readState == "unread" {
                        Circle().fill(theme.accentColor).frame(width: 6, height: 6).padding(.top, 4)
                            .accessibilityLabel("Unread")
                    }
                }
                Text(meta(topic))
                    .font(ThubanFont.scaled(12.5, scale: textScale))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
                let preview = CanvasHTML.plainText(topic.message, limit: 240)
                if !preview.isEmpty {
                    Text(preview)
                        .font(ThubanFont.scaled(13, scale: textScale))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
                if let attachments = topic.attachments, !attachments.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "paperclip").font(.system(size: 11, weight: .semibold))
                        Text(attachments.count == 1 ? attachments[0].displayName : "\(attachments.count) attachments").lineLimit(1)
                    }
                    .font(ThubanFont.scaled(12, scale: textScale))
                    .foregroundStyle(theme.inkFaintColor)
                    .padding(.top, 1)
                }
            }
        }
    }

    /// Newest first, only from starred courses, at most `limit`.
    private func recent(_ topics: [DiscussionTopic]) -> [DiscussionTopic] {
        Array(topics
            .filter { $0.courseId.map { app.sessions[$0] != nil } ?? false }
            .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            .prefix(limit))
    }

    /// The short tab title (nickname, short name or code) so the line fits beside the date and author.
    private func courseName(_ topic: DiscussionTopic) -> String {
        topic.courseId.flatMap { app.sessions[$0]?.tabTitle } ?? "Course"
    }

    private func meta(_ topic: DiscussionTopic) -> String {
        var parts = [courseName(topic)]
        if let posted = topic.postedAt { parts.append(DueFormatter.relative(posted)) }
        if let author = topic.author?.displayName ?? topic.userName, !author.isEmpty { parts.append(author) }
        return parts.joined(separator: " · ")
    }

    private func rowLabel(_ topic: DiscussionTopic) -> String {
        var text = "\(topic.title), \(topic.courseId.flatMap { app.sessions[$0]?.displayName } ?? "")"
        if let posted = topic.postedAt { text += ", \(DueFormatter.relative(posted))" }
        if topic.readState == "unread" { text += ", unread" }
        return text
    }

    private func open(_ topic: DiscussionTopic) {
        guard let course = topic.courseId else { return }
        app.open(course: course, section: .announcements, route: .discussion(topic.id))
    }

    private func reload() async {
        let ids = app.courses.map(\.id)
        await app.announcements.load(app: app, force: true) { try await $0.announcements(courses: ids) }
    }
}
