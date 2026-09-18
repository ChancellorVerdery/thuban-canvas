import SwiftUI
import ThubanCanvasCore

/// The Inbox panel: scope picker + search over the conversation list on the left, the selected thread on the right.
/// Every write (reply, compose, mark read, star) is confirmed first and gated on `settings.writesEnabled`.
struct InboxView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var model = InboxModel()
    @State private var scope: InboxScope = .all
    @State private var search = ""
    @State private var selected: CanvasID?
    @State private var composing = false
    @State private var pendingAction: InboxAction?
    @State private var writeError: String?

    var body: some View {
        VStack(spacing: 0) {
            bar
            HStack(spacing: 0) {
                ConversationList(model: model, scope: scope, search: search, selected: $selected, pendingAction: $pendingAction)
                    .frame(width: 380)
                    .thubanHairline(.trailing, color: theme.lineColor)
                detail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: scope) {
            await model.load(scope: scope, app: app)
            if selected == nil { selected = model.resource(for: scope).value?.first?.id }
        }
        .sheet(isPresented: $composing) { ComposeMessageSheet(model: model) }
        .confirmationDialog(pendingAction?.title ?? "", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
                            titleVisibility: .visible, presenting: pendingAction) { action in
            Button(action.buttonLabel) { perform(action) }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { action in
            Text(action.message)
        }
        .alert("Couldn’t update the conversation", isPresented: Binding(get: { writeError != nil }, set: { if !$0 { writeError = nil } })) {
            Button("OK") { writeError = nil }
        } message: {
            Text(writeError ?? "")
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 10) {
            Text("Inbox")
                .font(ThubanFont.display(18))
                .foregroundStyle(theme.inkColor)
                .accessibilityAddTraits(.isHeader)
            if app.unreadInbox > 0 {
                Chip(app.unreadInbox == 1 ? "1 unread" : "\(app.unreadInbox) unread", kind: .accent)
                    .accessibilityLabel("\(app.unreadInbox) unread messages")
            }
            SegmentedPicker(selection: $scope, options: InboxScope.allCases.map { SegmentOption($0, $0.label) }, segmentHeight: SegmentedPickerHeight.toolbar)
                .padding(.leading, 6)
                .accessibilityLabel("Mailbox")
            SearchField(text: $search, placeholder: "Search messages")
                .frame(width: 220)
                .accessibilityLabel("Search messages")
            if model.resource(for: scope).isLoading {
                ProgressView().controlSize(.small).accessibilityLabel("Loading messages")
            }
            Spacer(minLength: 12)
            if app.settings.writesEnabled {
                Button {
                    composing = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .semibold))
                        Text("Compose")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(height: 30))
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("Compose a new message")
            }
            Button("Close") { app.panel = nil }
                .buttonStyle(GhostButtonStyle(height: 30))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close inbox")
        }
        .padding(.horizontal, 16)
        .frame(height: ThubanMetrics.sectionBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            ConversationDetailView(model: model, conversationId: selected, summary: row(for: selected))
                .id(selected)
        } else {
            EmptyState(title: "No conversation selected", message: "Choose a message on the left to read it here.")
        }
    }

    private func row(for id: CanvasID) -> Conversation? {
        model.resource(for: scope).value?.first { $0.id == id }
    }

    // MARK: Writes (read state, star) — confirmed by the dialog above

    private func perform(_ action: InboxAction) {
        pendingAction = nil
        guard app.settings.writesEnabled, let client = app.client else { return }
        Task {
            do {
                switch action {
                case .markRead(let id, let read):
                    try await client.markConversation(id, read: read)
                    model.update(id, app: app) { $0.workflowState = read ? "read" : "unread" }
                case .star(let id, let starred):
                    try await client.starConversation(id, starred: starred)
                    model.update(id, app: app) { $0.starred = starred }
                }
                await app.refreshUnreadCount()
            } catch {
                writeError = error.localizedDescription
            }
        }
    }
}

/// A context-menu write awaiting confirmation.
enum InboxAction: Hashable {
    case markRead(CanvasID, read: Bool)
    case star(CanvasID, starred: Bool)

    var title: String {
        switch self {
        case .markRead(_, let read): return read ? "Mark as read?" : "Mark as unread?"
        case .star(_, let starred): return starred ? "Star this conversation?" : "Remove the star?"
        }
    }

    var buttonLabel: String {
        switch self {
        case .markRead(_, let read): return read ? "Mark as read" : "Mark as unread"
        case .star(_, let starred): return starred ? "Star" : "Unstar"
        }
    }

    var message: String {
        switch self {
        case .markRead: return "This changes the conversation in your Canvas inbox."
        case .star: return "Stars are saved to your Canvas inbox."
        }
    }
}

// MARK: - List

/// The conversation rows for one scope, filtered by the search text; ↑ / ↓ move the selection.
private struct ConversationList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: InboxModel
    var scope: InboxScope
    var search: String
    @Binding var selected: CanvasID?
    @Binding var pendingAction: InboxAction?

    var body: some View {
        let resource = model.resource(for: scope)
        ResourceStateView(resource: resource, emptyTitle: emptyTitle, emptyMessage: nil, isEmpty: { $0.isEmpty },
                          retry: { await model.load(scope: scope, app: app, force: true) }) { conversations in
            let rows = filtered(conversations)
            if rows.isEmpty {
                EmptyState(title: "No matches", message: "Nothing in \(scope.label) matches “\(search)”.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { conversation in
                                ConversationRow(conversation: conversation, isSelected: conversation.id == selected,
                                                hasAttachments: conversation.hasAttachments || (model.details[conversation.id]?.hasAttachments ?? false)) {
                                    selected = conversation.id
                                }
                                .id(conversation.id)
                                .contextMenu { contextMenu(for: conversation) }
                            }
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(.downArrow) { move(1, in: rows, proxy: proxy) }
                    .onKeyPress(.upArrow) { move(-1, in: rows, proxy: proxy) }
                }
            }
        }
        .background(theme.bgColor)
        .accessibilityLabel("Conversations")
    }

    private var emptyTitle: String {
        switch scope {
        case .all: return "No messages"
        case .unread: return "Nothing unread"
        case .starred: return "No starred messages"
        case .sent: return "Nothing sent yet"
        case .archived: return "Nothing archived"
        }
    }

    private func filtered(_ conversations: [Conversation]) -> [Conversation] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return conversations }
        let me = app.user?.id
        return conversations.filter { conversation in
            let haystack: [String?] = [conversation.subject, conversation.lastMessage, conversation.contextName,
                                       conversation.others(excluding: me).map(\.name).joined(separator: " ")]
            return haystack.contains { $0?.localizedCaseInsensitiveContains(query) == true }
        }
    }

    private func move(_ delta: Int, in rows: [Conversation], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == selected } ?? (delta > 0 ? -1 : rows.count)
        let next = min(max(current + delta, 0), rows.count - 1)
        selected = rows[next].id
        proxy.scrollTo(rows[next].id, anchor: nil)
        return .handled
    }

    @ViewBuilder
    private func contextMenu(for conversation: Conversation) -> some View {
        if app.settings.writesEnabled {
            Button(conversation.isUnread ? "Mark as read…" : "Mark as unread…") {
                pendingAction = .markRead(conversation.id, read: conversation.isUnread)
            }
            Button(conversation.starred == true ? "Remove star…" : "Star…") {
                pendingAction = .star(conversation.id, starred: conversation.starred != true)
            }
            Divider()
        }
        Button("Open in Canvas") {
            if let url = URL(string: "\(app.host)/conversations#filter=type=inbox&id=\(conversation.id)") { NSWorkspace.shared.open(url) }
        }
    }
}

/// Subject (bold + accent dot when unread), the other participants, the course, a one-line preview, the date,
/// star and attachment marks.
private struct ConversationRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var conversation: Conversation
    var isSelected: Bool
    var hasAttachments: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(conversation.isUnread ? theme.accentColor : .clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(subject)
                            .font(.system(size: 14 * textScale, weight: conversation.isUnread ? .bold : .semibold))
                            .foregroundStyle(theme.inkColor)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if hasAttachments {
                            Image(systemName: "paperclip").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
                                .accessibilityLabel("Has attachments")
                        }
                        if conversation.starred == true {
                            Image(systemName: "star.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                                .accessibilityLabel("Starred")
                        }
                        Text(inboxDate(conversation.lastMessageAt))
                            .font(.system(size: 12 * textScale))
                            .foregroundStyle(conversation.isUnread ? theme.brassInkColor : theme.inkFaintColor)
                            .monospacedDigit()
                    }
                    Text(conversation.participantSummary(excluding: app.user?.id))
                        .font(.system(size: 13 * textScale, weight: conversation.isUnread ? .semibold : .regular))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                    if let course = conversationCourseName(conversation, app: app) {
                        Text(course)
                            .font(.system(size: 12 * textScale))
                            .foregroundStyle(theme.inkFaintColor)
                            .lineLimit(1)
                    }
                    if let preview = conversation.lastMessage, !preview.isEmpty {
                        Text(preview.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression))
                            .font(.system(size: 12 * textScale))
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .thubanHairline(.bottom, color: theme.lineColor)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var subject: String { conversation.displaySubject }

    private var accessibilityText: String {
        var parts = [conversation.isUnread ? "Unread" : "", subject, conversation.participantSummary(excluding: app.user?.id)]
        if let course = conversationCourseName(conversation, app: app) { parts.append(course) }
        parts.append(inboxDate(conversation.lastMessageAt))
        if conversation.starred == true { parts.append("starred") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
