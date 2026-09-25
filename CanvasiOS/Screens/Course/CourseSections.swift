import SwiftUI
import ThubanCanvasCore

// The remaining course sections: Assignments, Announcements, Discussions (+ thread), Syllabus, People, Files,
// Pages (+ page). All read-only.

// MARK: - Assignments

struct AssignmentsScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("Assignments", back: back) {
                AssignmentsContent(session: session).padding(.top, 8)
            }
            .refreshable { await session.loadGroups(force: true) }
        }
    }
}

/// This week / upcoming / undated / past & graded. On iPad `selection` drives the detail pane instead of pushing.
struct AssignmentsContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    var selection: Binding<CanvasID?>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.groups.hasValue {
                let items = session.workItems.filter { $0.kind != .event }
                let week = WorkItemBuilder.upcoming(items, within: 7)
                let later = WorkItemBuilder.upcoming(items).filter { item in !week.contains(item) }
                let overdue = WorkItemBuilder.overdue(items, dismissed: [])
                let undated = items.filter { $0.dueAt == nil && !$0.isDone && $0.status != .overdue }
                let past = items.filter { $0.isDone || ($0.dueAt.map { $0 < Date() } ?? false && $0.status != .overdue && $0.status != .upcoming) }
                    .sorted { ($0.gradedAt ?? $0.dueAt ?? .distantPast) > ($1.gradedAt ?? $1.dueAt ?? .distantPast) }
                if !overdue.isEmpty { group("Overdue", overdue, highlight: false) }
                if week.isEmpty && overdue.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeading("This week")
                        Card { EmptyNote(systemName: "checkmark", text: "Nothing due this week.", tint: theme.posTextColor) }
                    }
                } else if !week.isEmpty {
                    group("This week", week, highlight: true)
                }
                if !later.isEmpty { group("Upcoming", later, highlight: false) }
                if !undated.isEmpty { group("No due date", undated, highlight: false) }
                if !past.isEmpty { group("Past & graded", past, highlight: false) }
            } else if session.groups.isLoading || !session.groups.hasAttempted {
                LoadingCard(text: "Loading assignments…")
            } else if let error = session.groups.error {
                Card { EmptyNote(systemName: "wifi.exclamationmark", text: error.localizedDescription, tint: theme.negTextColor) }
            }
        }
        .gutter()
        .task(id: session.id) { await session.loadGroups() }
    }

    private func group(_ title: String, _ items: [WorkItem], highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title)
            Card(border: highlight && selection == nil ? nil : nil) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(theme.lineColor).frame(height: 1) }
                    Button {
                        guard let id = item.assignmentId else { return }
                        if let selection { selection.wrappedValue = id } else { app.push(.assignment(course: session.id, id: id)) }
                    } label: {
                        row(item, first: highlight && index == 0)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
    }

    private func row(_ item: WorkItem, first: Bool) -> some View {
        let selected = selection?.wrappedValue == item.assignmentId && selection != nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).tFont(.text(16, .semibold)).foregroundStyle(theme.inkColor).multilineTextAlignment(.leading)
                subtitle(item, emphasize: first)
            }
            Spacer(minLength: 8)
            trailing(item)
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 8)
        .frame(minHeight: 60)
        .background(selected || (first && selection == nil) ? theme.accentTintColor : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func subtitle(_ item: WorkItem, emphasize: Bool) -> some View {
        switch item.status {
        case .graded:
            Text(item.gradedAt.map { "Graded \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Graded").tFont(.footnote).foregroundStyle(theme.inkDimColor)
        case .submitted:
            Text("Submitted" + (item.dueAt.map { " · due \(DueFormatter.compact($0))" } ?? "")).tFont(.footnote).foregroundStyle(theme.inkDimColor)
        case .overdue:
            Text(item.dueAt.map { DueFormatter.lateness($0) } ?? "Missing").tFont(.text(13, .semibold)).foregroundStyle(theme.negTextColor)
        case .excused:
            Text("Excused").tFont(.footnote).foregroundStyle(theme.inkDimColor)
        case .upcoming:
            if let due = item.dueAt {
                let soon = due.timeIntervalSinceNow < 48 * 3_600
                Text(item.lockedForUser ? "Locked · due \(DueFormatter.compact(due))" : DueFormatter.compact(due))
                    .tFont(.text(13, soon || emphasize ? .semibold : .regular))
                    .foregroundStyle(soon || emphasize ? theme.brassInkColor : theme.inkDimColor)
            }
        case .noDate:
            Text(item.dueAt.map { DueFormatter.compact($0) } ?? "No due date").tFont(.footnote).foregroundStyle(theme.inkDimColor)
        }
    }

    @ViewBuilder
    private func trailing(_ item: WorkItem) -> some View {
        if item.status == .graded {
            ScoreLabel(score: item.score, possible: item.pointsPossible, size: 14)
        } else if item.kind == .quiz {
            ChipView("Quiz", kind: .signal)
        } else if let points = item.pointsPossible {
            Text("\(PointsText.short(points)) pts").tFont(.mono(13)).foregroundStyle(theme.inkDimColor)
        }
    }
}

// MARK: - Announcements & discussions

struct AnnouncementsScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("Announcements", back: back) {
                TopicListContent(session: session, announcements: true).padding(.top, 8)
            }
            .refreshable { await session.loadAnnouncements(force: true) }
        }
    }
}

struct DiscussionsScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("Discussions", back: back) {
                TopicListContent(session: session, announcements: false).padding(.top, 8)
            }
            .refreshable { await session.loadDiscussions(force: true) }
        }
    }
}

struct TopicListContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    var announcements: Bool

    var body: some View {
        let resource = announcements ? session.announcements : session.discussions
        VStack(alignment: .leading, spacing: 0) {
            if let topics = resource.value {
                let sorted = topics.sorted { ($0.lastReplyAt ?? $0.postedAt ?? .distantPast) > ($1.lastReplyAt ?? $1.postedAt ?? .distantPast) }
                if sorted.isEmpty {
                    Card { EmptyNote(systemName: announcements ? "megaphone" : "bubble.left.and.bubble.right", text: announcements ? "No announcements yet." : "No discussions yet.") }
                } else {
                    Card {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, topic in
                            if index > 0 { RowDivider() }
                            Button {
                                app.push(announcements ? .announcement(course: session.id, id: topic.id) : .discussion(course: session.id, id: topic.id))
                            } label: { row(topic) }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                }
            } else if resource.isLoading || !resource.hasAttempted {
                LoadingCard()
            } else if resource.unavailable {
                Card { EmptyNote(systemName: "lock", text: "Turned off in this course.") }
            } else if let error = resource.error {
                Card { EmptyNote(systemName: "wifi.exclamationmark", text: error.localizedDescription, tint: theme.negTextColor) }
            }
        }
        .gutter()
        .task(id: session.id) {
            if announcements { await session.loadAnnouncements() } else { await session.loadDiscussions() }
        }
    }

    private func row(_ topic: DiscussionTopic) -> some View {
        let unread = topic.readState == "unread" || (topic.unreadCount ?? 0) > 0
        return HStack(alignment: .top, spacing: 12) {
            Circle().fill(unread ? theme.accentColor : .clear).frame(width: 8, height: 8).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title).tFont(.text(16, unread ? .bold : .semibold)).foregroundStyle(theme.inkColor).multilineTextAlignment(.leading)
                Text(meta(topic)).tFont(.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
                let preview = CanvasHTML.plainText(topic.message, limit: 140)
                if !preview.isEmpty { Text(preview).tFont(.text(14)).foregroundStyle(theme.inkDimColor).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? "Unread" : "")
    }

    private func meta(_ topic: DiscussionTopic) -> String {
        var parts: [String] = []
        if let author = topic.author?.displayName ?? topic.userName { parts.append(author) }
        if let date = topic.postedAt { parts.append(DueFormatter.compact(date)) }
        if !announcements, let replies = topic.discussionSubentryCount {
            parts.append("\(replies) repl\(replies == 1 ? "y" : "ies")" + ((topic.unreadCount ?? 0) > 0 ? " · \(topic.unreadCount ?? 0) new" : ""))
        }
        return parts.joined(separator: " · ")
    }
}

/// An announcement or discussion topic, with the thread for discussions. Viewing uses plain GETs.
struct TopicScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var courseId: CanvasID
    var topicId: CanvasID
    var isAnnouncement: Bool
    var back: String
    @State private var fetched: DiscussionTopic?
    @State private var thread: DiscussionView?
    @State private var error: String?

    var body: some View {
        PushedScreen(isAnnouncement ? "Announcement" : "Discussion", back: back) {
            if let url = topic?.htmlUrl.flatMap(URL.init(string:)) {
                IconButton(systemName: "safari", label: "Open in Canvas") { app.openInSafari(url) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let topic {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow([app.shortName(for: courseId), topic.author?.displayName ?? topic.userName, topic.postedAt.map { DueFormatter.compact($0) }].compactMap { $0 }.joined(separator: " · "))
                        Text(topic.title).tFont(.display(24)).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
                    }
                    if let message = topic.message, !message.isEmpty { Card { HTMLContentView(html: message) } }
                    if !isAnnouncement { replies }
                } else if let error {
                    Card { EmptyNote(systemName: "wifi.exclamationmark", text: error, tint: theme.negTextColor) }
                } else {
                    LoadingCard()
                }
                if !isAnnouncement {
                    Text("Replying happens in Canvas. Thuban Canvas only reads.").tFont(.footnote).foregroundStyle(theme.inkDimColor)
                }
            }
            .padding(.top, 8)
            .gutter()
        }
        .task { await load() }
    }

    private var topic: DiscussionTopic? {
        if let fetched { return fetched }
        let session = app.sessions[courseId]
        let list = (isAnnouncement ? session?.announcements.value : session?.discussions.value) ?? []
        return list.first { $0.id == topicId }
    }

    @ViewBuilder
    private var replies: some View {
        if let entries = thread?.view, !entries.isEmpty {
            let names = Dictionary(uniqueKeysWithValues: (thread?.participants ?? []).map { ($0.id, $0.displayName ?? "Someone") })
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Replies")
                Card {
                    ForEach(Array(flatten(entries).enumerated()), id: \.element.entry.id) { index, pair in
                        if index > 0 { RowDivider() }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pair.entry.userId.flatMap { names[$0] } ?? "Someone").tFont(.text(15, .semibold)).foregroundStyle(theme.inkColor)
                                Spacer()
                                if let date = pair.entry.createdAt { Text(DueFormatter.compact(date)).tFont(.footnote).foregroundStyle(theme.inkFaintColor) }
                            }
                            Text(CanvasHTML.plainText(pair.entry.message, limit: 2_000)).tFont(.secondary).foregroundStyle(theme.inkColor)
                        }
                        .padding(.leading, 16 + CGFloat(min(pair.depth, 3)) * 14).padding(.trailing, 16).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func flatten(_ entries: [DiscussionEntry], depth: Int = 0) -> [(entry: DiscussionEntry, depth: Int)] {
        entries.filter { $0.deleted != true }.flatMap { [($0, depth)] + flatten($0.replies ?? [], depth: depth + 1) }
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            if topic == nil || topic?.message == nil { fetched = try await client.discussion(course: courseId, id: topicId) }
            if !isAnnouncement { thread = try await client.discussionView(course: courseId, topic: topicId) }
        } catch {
            if topic == nil { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Syllabus

struct SyllabusScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var courseId: CanvasID
    var back: String

    var body: some View {
        PushedScreen("Syllabus", back: back) {
            SyllabusContent(courseId: courseId).padding(.top, 8)
        }
    }
}

struct SyllabusContent: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let html = app.sessions[courseId]?.course.syllabusBody, !html.isEmpty {
                Card { HTMLContentView(html: html) }
            } else {
                Card { EmptyNote(systemName: "book.closed", text: "The instructor hasn’t posted a syllabus in Canvas.") }
            }
        }
        .gutter()
    }
}

// MARK: - People

struct PeopleScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("People", back: back) { PeopleContent(session: session).padding(.top, 6) }
                .refreshable { await session.loadPeople(force: true) }
        }
    }
}

struct PeopleContent: View {
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchBar(text: $query, placeholder: "Search people")
            if let people = session.people.value {
                let filtered = query.isEmpty ? people : people.filter { $0.name.localizedCaseInsensitiveContains(query) }
                let staff = filtered.filter { $0.roleLabel != "Student" }
                let students = filtered.filter { $0.roleLabel == "Student" }
                if !staff.isEmpty { list("Instructors", staff) }
                if !students.isEmpty { list("Students · \(students.count)", students) }
                if filtered.isEmpty { Card { EmptyNote(systemName: "magnifyingglass", text: "No one matches “\(query)”.") } }
            } else if session.people.isLoading || !session.people.hasAttempted {
                LoadingCard()
            } else {
                Card { EmptyNote(systemName: "person.2", text: session.people.error?.localizedDescription ?? "The roster is not available.") }
            }
        }
        .gutter()
        .task(id: session.id) { await session.loadPeople() }
    }

    private func list(_ title: String, _ people: [CourseUser]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title)
            Card {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { RowDivider(inset: 68) }
                    HStack(spacing: 12) {
                        InitialsAvatar(name: person.name, index: person.id, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name).tFont(.body).foregroundStyle(theme.inkColor)
                            if let pronouns = person.pronouns { Text(pronouns).tFont(.footnote).foregroundStyle(theme.inkDimColor) }
                        }
                        Spacer()
                        if person.roleLabel != "Student" { ChipView(person.roleLabel, kind: .warn) }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Files

struct FilesScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("Files", back: back) { FilesContent(session: session).padding(.top, 6) }
                .refreshable { await session.loadFiles(force: true) }
        }
    }
}

struct FilesContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchBar(text: $query, placeholder: "Search files")
            if let files = session.files.value {
                let filtered = (query.isEmpty ? files : files.filter { $0.displayName.localizedCaseInsensitiveContains(query) }).filter { $0.hidden != true }
                if filtered.isEmpty {
                    Card { EmptyNote(systemName: "folder", text: query.isEmpty ? "No files in this course." : "No file matches “\(query)”.") }
                } else {
                    Card {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, file in
                            if index > 0 { RowDivider(inset: 60) }
                            Button { Task { await app.openFile(course: session.id, id: file.id) } } label: {
                                HStack(spacing: 12) {
                                    FileBadge(name: file.displayName)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(file.displayName).tFont(.text(16, .semibold)).foregroundStyle(theme.inkColor).lineLimit(2).multilineTextAlignment(.leading)
                                        Text([DueFormatter.bytes(file.size), (file.updatedAt ?? file.createdAt).map { $0.formatted(.dateTime.month(.abbreviated).day()) },
                                              AppModel.isSavedOffline(fileId: file.id) ? "saved offline" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .tFont(.footnote).foregroundStyle(theme.inkDimColor)
                                    }
                                    Spacer(minLength: 8)
                                    if app.downloadingFile == file.id { ProgressView().tint(theme.brassInkColor) } else { RowChevron() }
                                }
                                .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 8)
                                .frame(minHeight: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                            .disabled(file.lockedForUser == true)
                            .accessibilityHint("Opens in Quick Look")
                        }
                    }
                }
            } else if session.files.isLoading || !session.files.hasAttempted {
                LoadingCard()
            } else {
                Card { EmptyNote(systemName: "folder", text: session.files.error?.localizedDescription ?? "Files are turned off in this course.") }
            }
        }
        .gutter()
        .task(id: session.id) { await session.loadFiles() }
    }
}

// MARK: - Pages

struct PagesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("Pages", back: back) {
                VStack(alignment: .leading, spacing: 0) {
                    if let pages = session.pages.value {
                        if pages.isEmpty {
                            Card { EmptyNote(systemName: "doc.text", text: "No pages yet.") }
                        } else {
                            Card {
                                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                    if index > 0 { RowDivider() }
                                    Button { app.push(.page(course: courseId, slug: page.url)) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(page.title).tFont(.text(16, .semibold)).foregroundStyle(theme.inkColor).multilineTextAlignment(.leading)
                                                if let updated = page.updatedAt { Text("Updated \(DueFormatter.compact(updated))").tFont(.footnote).foregroundStyle(theme.inkDimColor) }
                                            }
                                            Spacer()
                                            RowChevron()
                                        }
                                        .padding(.leading, 16).padding(.trailing, 12)
                                        .frame(minHeight: 56)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(RowPressStyle())
                                }
                            }
                        }
                    } else {
                        LoadingCard()
                    }
                }
                .padding(.top, 8)
                .gutter()
                .task { await session.loadPages() }
            }
        }
    }
}

struct PageScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var courseId: CanvasID
    var slug: String
    var back: String
    @State private var page: Page?
    @State private var error: String?

    var body: some View {
        PushedScreen("Page", back: back) {
            if let raw = page?.htmlUrl, let url = URL(string: raw) {
                IconButton(systemName: "safari", label: "Open in Canvas") { app.openInSafari(url) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let page {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow([app.shortName(for: courseId), page.updatedAt.map { "Updated \(DueFormatter.compact($0))" }].compactMap { $0 }.joined(separator: " · "))
                        Text(page.title).tFont(.display(26)).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
                    }
                    Card { HTMLContentView(html: page.body ?? "") }
                } else if let error {
                    Card { EmptyNote(systemName: "wifi.exclamationmark", text: error, tint: theme.negTextColor) }
                } else {
                    LoadingCard()
                }
            }
            .padding(.top, 8)
            .gutter()
        }
        .task {
            guard page == nil, let client = app.client else { return }
            do { page = try await client.page(course: courseId, url: slug) } catch { self.error = error.localizedDescription }
        }
    }
}
