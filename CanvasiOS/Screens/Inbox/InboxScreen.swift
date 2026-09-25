import SwiftUI
import ThubanCanvasCore

/// Read-only inbox: mailbox chips, pull to refresh, search. No compose, reply, star or archive — those happen in
/// Canvas. Opening a thread does not mark it read in Canvas.
struct InboxScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var scope: MailScope = .inbox
    @State private var searching = false
    @State private var query = ""

    var body: some View {
        RootScreen("Inbox", eyebrow: eyebrow) {
            EmptyView()
        } trailing: {
            IconButton(systemName: "magnifyingglass", label: searching ? "Hide search" : "Search messages") {
                searching.toggle()
                if !searching { query = "" }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if searching { SearchBar(text: $query, placeholder: "Search messages").gutter() }
                FilterChips(options: MailScope.allCases.map { ($0, $0.label) }, selection: $scope, accessibilityLabel: "Mailbox")
                list.gutter()
            }
            .padding(.top, 12)
        }
        .refreshable { await app.inbox.load(scope, app: app, force: true) }
        .task(id: scope) { await app.inbox.load(scope, app: app) }
    }

    private var eyebrow: String {
        app.unreadInbox > 0 ? "\(app.unreadInbox) unread · Canvas conversations" : "Canvas conversations"
    }

    @ViewBuilder
    private var list: some View {
        let resource = app.inbox.resource(scope)
        if let conversations = resource.value {
            let text = query.trimmingCharacters(in: .whitespaces)
            let filtered = text.isEmpty ? conversations : conversations.filter { conversation in
                (conversation.subject ?? "").localizedCaseInsensitiveContains(text)
                    || (conversation.lastMessage ?? "").localizedCaseInsensitiveContains(text)
                    || (conversation.participants ?? []).contains { $0.name.localizedCaseInsensitiveContains(text) }
            }
            if filtered.isEmpty {
                Card {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(theme.brassInkColor)
                        Text(text.isEmpty ? (scope == .archived ? "Nothing archived" : "No messages") : "No message matches “\(text)”.")
                            .tFont(.secondary).foregroundStyle(theme.inkDimColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Card {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, conversation in
                        if index > 0 { Rectangle().fill(theme.lineColor).frame(height: 1) }
                        Button { app.push(.conversation(conversation.id)) } label: {
                            ConversationRow(conversation: conversation, index: index, sent: scope == .sent)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
            }
        } else if resource.isLoading || !resource.hasAttempted {
            LoadingCard(text: "Checking for messages…")
        } else if let error = resource.error {
            Card { EmptyNote(systemName: "wifi.exclamationmark", text: error.localizedDescription, tint: theme.negTextColor) }
        }
    }
}

struct ConversationRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var conversation: Conversation
    var index: Int
    var sent: Bool

    var body: some View {
        let unread = conversation.isUnread
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(unread ? theme.accentColor : .clear).frame(width: 8, height: 8).padding(.top, 16)
            InitialsAvatar(name: sent ? (app.user?.name ?? "Me") : sender, index: index)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sent ? "To: \(sender)" : sender).tFont(.text(16, unread ? .bold : .medium)).foregroundStyle(theme.inkColor).lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = conversation.lastMessageAt ?? conversation.lastAuthoredMessageAt {
                        Text(Self.stamp(date)).tFont(.footnote).foregroundStyle(theme.inkFaintColor)
                    }
                }
                HStack(spacing: 6) {
                    let course = courseCode
                    if !course.isEmpty { ChipView(course, kind: .neutral, mono: true) }
                    Text(conversation.subject ?? "(no subject)").tFont(.text(15, unread ? .bold : .medium)).foregroundStyle(theme.inkColor).lineLimit(1)
                    if conversation.starred == true {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(theme.brassInkColor).accessibilityLabel("Starred")
                    }
                }
                Text(conversation.lastMessage ?? "").tFont(.text(14)).foregroundStyle(theme.inkDimColor).lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? "Unread" : "")
    }

    private var sender: String {
        let me = app.user?.id
        let others = (conversation.participants ?? []).filter { $0.id != me }
        return others.isEmpty ? "Me" : others.map(\.name).joined(separator: ", ")
    }

    private var courseCode: String {
        guard let code = conversation.contextCode, code.hasPrefix("course_"), let id = CanvasID(code.dropFirst(7)) else { return "" }
        return app.shortName(for: id, fallback: conversation.contextName)
    }

    static func stamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if abs(date.timeIntervalSinceNow) < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A conversation thread, oldest first. Replying happens in Canvas.
struct ConversationScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var conversationId: CanvasID
    var back: String

    var body: some View {
        let thread = app.inbox.threads[conversationId]
        let summary = thread ?? app.inbox.summary(conversationId)
        PushedScreen("Message", back: back) {
            if let url = URL(string: "\(app.host)/conversations#filter=type=inbox") {
                IconButton(systemName: "safari", label: "Open inbox in Canvas") { app.openInSafari(url) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let summary {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow([courseName(summary), "\(summary.messageCount ?? thread?.messages?.count ?? 0) messages"].compactMap { $0 }.joined(separator: " · "))
                        Text(summary.subject ?? "(no subject)").tFont(.display(24)).foregroundStyle(theme.inkColor)
                        Text(participants(summary)).tFont(.secondary).foregroundStyle(theme.inkDimColor)
                    }
                }
                if let messages = thread?.messages {
                    let names = Dictionary(uniqueKeysWithValues: (thread?.participants ?? []).map { ($0.id, $0.name) })
                    ForEach(messages.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }) { message in
                        let mine = message.authorId == app.user?.id
                        Card(fill: mine ? theme.accentTintColor : nil) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(mine ? "You" : (message.authorId.flatMap { names[$0] } ?? "Someone")).tFont(.text(15, .semibold)).foregroundStyle(theme.inkColor)
                                    Spacer()
                                    if let date = message.createdAt { Text(DueFormatter.compact(date)).tFont(.footnote).foregroundStyle(theme.inkFaintColor) }
                                }
                                Text(message.body ?? "").tFont(.body).foregroundStyle(theme.inkColor).textSelection(.enabled)
                                ForEach(message.attachments ?? []) { file in
                                    Button { Task { await app.openFile(course: nil, id: file.id) } } label: {
                                        HStack(spacing: 10) {
                                            FileBadge(name: file.displayName)
                                            Text(file.displayName).tFont(.text(15, .semibold)).foregroundStyle(theme.inkColor)
                                            Spacer()
                                        }
                                        .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else if let error = app.inbox.threadErrors[conversationId] {
                    Card { EmptyNote(systemName: "wifi.exclamationmark", text: error, tint: theme.negTextColor) }
                } else {
                    LoadingCard()
                }
                Text("Replies are sent from Canvas. Thuban Canvas only reads, and opening a message here leaves it unread in Canvas.")
                    .tFont(.footnote).foregroundStyle(theme.inkDimColor)
            }
            .padding(.top, 8)
            .gutter()
        }
        .refreshable { await app.inbox.loadThread(conversationId, app: app, force: true) }
        .task { await app.inbox.loadThread(conversationId, app: app) }
    }

    private func courseName(_ conversation: Conversation) -> String? {
        guard let code = conversation.contextCode, code.hasPrefix("course_"), let id = CanvasID(code.dropFirst(7)) else { return conversation.contextName }
        return app.shortName(for: id, fallback: conversation.contextName)
    }

    private func participants(_ conversation: Conversation) -> String {
        let names = (conversation.participants ?? []).map { $0.id == app.user?.id ? "You" : $0.name }
        return names.joined(separator: ", ")
    }
}
