import SwiftUI
import ThubanCanvasCore

/// The Inbox panel: scope picker + search over the conversation list on the left, the selected thread on the right.
/// Click selects one conversation, ⌘-click toggles, ⇧-click extends the range, ⌘A selects all; several selected rows
/// get a bulk bar (read / unread / star / archive / delete). Opening a conversation marks it read, like the web
/// inbox. Reversible actions run at once; archive and delete are confirmed. Everything is gated on
/// `settings.writesEnabled`.
struct InboxView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var model = InboxModel()
    @State private var scope: InboxScope = .all
    @State private var search = ""
    @State private var selection = InboxSelection()
    @State private var composing = false
    @State private var pendingAction: InboxAction?
    @State private var isWorking = false
    @State private var writeError: String?

    var body: some View {
        VStack(spacing: 0) {
            bar
            HStack(spacing: 0) {
                ConversationList(model: model, scope: scope, search: search, selection: $selection, perform: request)
                    .frame(width: 380)
                    .thubanHairline(.trailing, color: theme.lineColor)
                detail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: scope) {
            await model.load(scope: scope, app: app)
            if selection.isEmpty, let first = model.resource(for: scope).value?.first?.id { selection.select(first) }
        }
        .onChange(of: scope) { _, _ in selection.clear() }
        .sheet(isPresented: $composing) { ComposeMessageSheet(model: model) }
        .sheet(item: $pendingAction) { action in
            ConfirmWriteSheet(
                title: action.title,
                message: action.message,
                actionLabel: action.buttonLabel,
                isWorking: isWorking,
                error: writeError,
                confirm: { perform(action) },
                cancel: { pendingAction = nil; writeError = nil }
            )
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
        if selection.ids.count > 1 {
            BulkActionsView(count: selection.ids.count, rows: selectedRows, scope: scope, isWorking: isWorking, error: writeError,
                            perform: { request($0, ids: selection.ids) }, clear: { selection.clear() })
        } else if let selected = selection.ids.first {
            ConversationDetailView(model: model, conversationId: selected, summary: row(for: selected))
                .id(selected)
        } else {
            EmptyState(title: "No conversation selected", message: "Choose a message on the left to read it here.")
        }
    }

    private func row(for id: CanvasID) -> Conversation? {
        model.resource(for: scope).value?.first { $0.id == id }
    }

    private var selectedRows: [Conversation] {
        (model.resource(for: scope).value ?? []).filter { selection.ids.contains($0.id) }
    }

    // MARK: Writes

    /// Entry point for row menus and the bulk bar: reversible events run immediately; archive / delete confirm.
    private func request(_ event: ConversationBatchEvent, ids: Set<CanvasID>) {
        guard app.settings.writesEnabled, !ids.isEmpty else { return }
        let action = InboxAction(event: event, ids: ids)
        if action.needsConfirmation { pendingAction = action } else { perform(action) }
    }

    private func perform(_ action: InboxAction) {
        guard app.settings.writesEnabled, let client = app.client, !isWorking else { return }
        isWorking = true
        writeError = nil
        let ids = Array(action.ids)
        Task {
            defer { isWorking = false }
            do {
                try await client.batchUpdateConversations(ids, event: action.event)
                switch action.event {
                case .markAsRead:
                    for id in ids { model.update(id, app: app) { $0.workflowState = "read" } }
                case .markAsUnread:
                    for id in ids { model.update(id, app: app) { $0.workflowState = "unread" } }
                case .star:
                    for id in ids { model.update(id, app: app) { $0.starred = true } }
                case .unstar:
                    for id in ids { model.update(id, app: app) { $0.starred = false } }
                case .archive, .destroy:
                    model.remove(Set(ids), app: app)
                    selection.clear()
                }
                await app.refreshUnreadCount()
                pendingAction = nil
                if action.event == .archive || action.event == .destroy {
                    await model.load(scope: scope, app: app, force: true)
                }
            } catch {
                writeError = error.localizedDescription
                if !action.needsConfirmation { pendingAction = action } // surface the failure in the sheet
            }
        }
    }
}

/// Which rows are selected: the set plus the anchor a ⇧-click extends from.
struct InboxSelection: Equatable {
    private(set) var ids: Set<CanvasID> = []
    private(set) var anchor: CanvasID?

    var isEmpty: Bool { ids.isEmpty }

    mutating func clear() { ids = []; anchor = nil }

    /// Plain click: just this row.
    mutating func select(_ id: CanvasID) { ids = [id]; anchor = id }

    /// ⌘-click: toggle membership; the toggled row becomes the anchor.
    mutating func toggle(_ id: CanvasID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        anchor = ids.contains(id) ? id : ids.first
    }

    /// ⇧-click: every row between the anchor and this one (inclusive), in the list's current order.
    mutating func extend(to id: CanvasID, in order: [CanvasID]) {
        guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else { select(id); return }
        ids.formUnion(order[min(from, to)...max(from, to)])
    }

    mutating func selectAll(_ order: [CanvasID]) {
        ids = Set(order)
        if anchor == nil { anchor = order.first }
    }
}

/// A write to one or more conversations. Read/star changes are reversible and run without a sheet; archive and
/// delete are confirmed first.
struct InboxAction: Hashable, Identifiable {
    var event: ConversationBatchEvent
    var ids: Set<CanvasID>

    var id: String { event.rawValue + "/" + ids.sorted().map(String.init).joined(separator: ",") }
    var needsConfirmation: Bool { event == .archive || event == .destroy }
    private var noun: String { ids.count == 1 ? "this conversation" : "\(ids.count) conversations" }

    var title: String {
        switch event {
        case .archive: return "Archive \(noun)?"
        case .destroy: return "Delete \(noun)?"
        case .markAsRead: return "Mark \(noun) as read?"
        case .markAsUnread: return "Mark \(noun) as unread?"
        case .star: return "Star \(noun)?"
        case .unstar: return "Unstar \(noun)?"
        }
    }

    var buttonLabel: String {
        switch event {
        case .archive: return "Archive"
        case .destroy: return "Delete"
        case .markAsRead: return "Mark as read"
        case .markAsUnread: return "Mark as unread"
        case .star: return "Star"
        case .unstar: return "Unstar"
        }
    }

    var message: String {
        switch event {
        case .archive: return "Archived conversations leave your inbox in Canvas; find them under Archived."
        case .destroy: return "This removes the conversation from your Canvas inbox for you. It cannot be undone here."
        default: return "This changes the conversation in your Canvas inbox."
        }
    }
}

/// Shown in place of the thread while several rows are selected.
private struct BulkActionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var count: Int
    var rows: [Conversation]
    var scope: InboxScope
    var isWorking: Bool
    var error: String?
    var perform: (ConversationBatchEvent) -> Void
    var clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) conversations selected")
                    .font(ThubanFont.display(22))
                    .foregroundStyle(theme.inkColor)
                Text(summary)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
            }
            if app.settings.writesEnabled {
                HStack(spacing: 8) {
                    if rows.contains(where: \.isUnread) { action("Mark as read", "envelope.open", .markAsRead) }
                    if rows.contains(where: { !$0.isUnread }) { action("Mark as unread", "envelope.badge", .markAsUnread) }
                    if rows.contains(where: { $0.starred != true }) { action("Star", "star", .star) }
                    if rows.contains(where: { $0.starred == true }) { action("Unstar", "star.slash", .unstar) }
                    if scope != .archived { action("Archive…", "archivebox", .archive) }
                    action("Delete…", "trash", .destroy)
                }
                if isWorking { ProgressView().controlSize(.small) }
                if let error { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor) }
            } else {
                SettingsNote(text: "Sending to Canvas is turned off in Settings › Connection, so the selection is read-only.")
            }
            Button("Clear selection", action: clear)
                .buttonStyle(GhostButtonStyle(height: 28, tinted: true, horizontalPadding: 8))
                .keyboardShortcut(.cancelAction)
            Text("Tip: ⌘-click toggles a row, ⇧-click selects a range, ⌘A selects everything listed.")
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summary: String {
        let unread = rows.filter(\.isUnread).count
        let starred = rows.filter { $0.starred == true }.count
        var parts: [String] = []
        if unread > 0 { parts.append("\(unread) unread") }
        if starred > 0 { parts.append("\(starred) starred") }
        return parts.isEmpty ? "All read, none starred." : parts.joined(separator: " · ")
    }

    private func action(_ label: String, _ symbol: String, _ event: ConversationBatchEvent) -> some View {
        Button {
            perform(event)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(label)
            }
        }
        .buttonStyle(SecondaryButtonStyle(height: 30))
        .disabled(isWorking)
        .accessibilityLabel("\(label.replacingOccurrences(of: "…", with: "")) \(count) conversations")
    }
}

// MARK: - List

/// The conversation rows for one scope, filtered by the search text. Click / ⌘-click / ⇧-click select; ↑ ↓ move
/// (⇧ extends); ⌘A selects all listed rows.
private struct ConversationList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var model: InboxModel
    var scope: InboxScope
    var search: String
    @Binding var selection: InboxSelection
    var perform: (ConversationBatchEvent, Set<CanvasID>) -> Void
    @FocusState private var listFocused: Bool

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
                                ConversationRow(conversation: conversation, isSelected: selection.ids.contains(conversation.id),
                                                hasAttachments: conversation.hasAttachments || (model.details[conversation.id]?.hasCachedAttachments ?? false)) {
                                    click(conversation.id, in: rows)
                                }
                                .id(conversation.id)
                                .contextMenu { contextMenu(for: conversation) }
                            }
                        }
                    }
                    .focusable()
                    .focused($listFocused)
                    .focusEffectDisabled()
                    .overlay(alignment: .leading) {
                        Rectangle().fill(theme.accentColor).frame(width: 2).opacity(listFocused ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .onAppear { listFocused = true }
                    .onKeyPress(.downArrow, phases: .down) { press in move(1, in: rows, proxy: proxy, extend: press.modifiers.contains(.shift)) }
                    .onKeyPress(.upArrow, phases: .down) { press in move(-1, in: rows, proxy: proxy, extend: press.modifiers.contains(.shift)) }
                    .onKeyPress(characters: CharacterSet(charactersIn: "aA"), phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        selection.selectAll(rows.map(\.id))
                        return .handled
                    }
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

    /// Reads the modifier keys of the click that fired the row's action.
    private func click(_ id: CanvasID, in rows: [Conversation]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) {
            selection.extend(to: id, in: rows.map(\.id))
        } else if flags.contains(.command) {
            selection.toggle(id)
        } else {
            selection.select(id)
        }
    }

    /// The row the keyboard moves from: the anchor (last clicked) when it is listed, else the first selected row.
    private func move(_ delta: Int, in rows: [Conversation], proxy: ScrollViewProxy, extend: Bool) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let reference = selection.anchor.flatMap { id in rows.firstIndex { $0.id == id } }
            ?? rows.firstIndex { selection.ids.contains($0.id) }
        let current = reference ?? (delta > 0 ? -1 : rows.count)
        let next = min(max(current + delta, 0), rows.count - 1)
        let id = rows[next].id
        if extend {
            selection.extend(to: id, in: rows.map(\.id))
        } else {
            selection.select(id)
        }
        proxy.scrollTo(id, anchor: nil)
        return .handled
    }

    /// Acts on the whole selection when the row is part of it, else on the row alone.
    private func targets(_ conversation: Conversation) -> Set<CanvasID> {
        selection.ids.contains(conversation.id) ? selection.ids : [conversation.id]
    }

    @ViewBuilder
    private func contextMenu(for conversation: Conversation) -> some View {
        let ids = targets(conversation)
        let many = ids.count > 1
        if app.settings.writesEnabled {
            if many {
                Text("\(ids.count) selected")
                Button("Mark as read") { perform(.markAsRead, ids) }
                Button("Mark as unread") { perform(.markAsUnread, ids) }
                Button("Star") { perform(.star, ids) }
                Button("Unstar") { perform(.unstar, ids) }
            } else {
                Button(conversation.isUnread ? "Mark as read" : "Mark as unread") { perform(conversation.isUnread ? .markAsRead : .markAsUnread, ids) }
                Button(conversation.starred == true ? "Remove star" : "Star") { perform(conversation.starred == true ? .unstar : .star, ids) }
            }
            Divider()
            if scope != .archived { Button("Archive…") { perform(.archive, ids) } }
            Button("Delete…", role: .destructive) { perform(.destroy, ids) }
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
                            .foregroundStyle(conversation.isUnread ? theme.brassInkColor : theme.inkDimColor)
                            .monospacedDigit()
                    }
                    Text(conversation.participantSummary(excluding: app.user?.id))
                        .font(.system(size: 13 * textScale, weight: conversation.isUnread ? .semibold : .regular))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                    if let course = conversationCourseName(conversation, app: app) {
                        Text(course)
                            .font(.system(size: 12 * textScale))
                            .foregroundStyle(theme.inkDimColor)
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
