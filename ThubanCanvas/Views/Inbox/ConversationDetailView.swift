import SwiftUI
import ThubanCanvasCore

/// One thread: header, messages newest first (plain-text bodies, attachments open in the browser) and a reply
/// composer that confirms before `replyToConversation`.
struct ConversationDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var model: InboxModel
    var conversationId: CanvasID
    /// The list row (available before the full thread loads).
    var summary: Conversation?
    @State private var reply = ""
    @State private var confirmingReply = false
    @State private var isSending = false
    @State private var sendError: String?

    private var conversation: Conversation? { model.details[conversationId] ?? summary }

    var body: some View {
        VStack(spacing: 0) {
            if let conversation {
                header(conversation)
                messages(conversation)
                composer
            } else if let error = model.detailErrors[conversationId] {
                EmptyState(title: "Couldn’t load", message: error) {
                    Button("Try again") { Task { await model.loadDetail(conversationId, app: app, force: true) } }.buttonStyle(.thubanSecondary)
                }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: conversationId) { await model.loadDetail(conversationId, app: app) }
        .sheet(isPresented: $confirmingReply) {
            ConfirmWriteSheet(
                title: "Send this reply?",
                message: "Your reply goes to everyone in “\(subjectText)” through Canvas.",
                actionLabel: "Send reply",
                isWorking: isSending,
                error: sendError,
                confirm: sendReply,
                cancel: { confirmingReply = false }
            )
        }
    }

    private var subjectText: String { conversation?.displaySubject ?? "(No subject)" }

    // MARK: Header

    private func header(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(subjectText)
                    .font(ThubanFont.display(22))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if conversation.starred == true {
                    Image(systemName: "star.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                        .accessibilityLabel("Starred")
                }
                if conversation.isUnread { Chip("Unread", kind: .accent) }
            }
            HStack(spacing: 8) {
                if let course = conversationCourseName(conversation, app: app) {
                    Text(course).font(ThubanFont.small).foregroundStyle(theme.brassInkColor)
                    Text("·").font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                }
                Text(participantsLine(conversation))
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
                    .help(conversation.others(excluding: app.user?.id).map(\.name).joined(separator: ", "))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    private func participantsLine(_ conversation: Conversation) -> String {
        let others = conversation.others(excluding: app.user?.id)
        if others.isEmpty { return "Just you" }
        if others.count <= 4 { return others.map(\.name).joined(separator: ", ") }
        return others.prefix(3).map(\.name).joined(separator: ", ") + " and \(others.count - 3) others"
    }

    // MARK: Messages

    @ViewBuilder
    private func messages(_ conversation: Conversation) -> some View {
        let list = conversation.messagesNewestFirst
        if list.isEmpty {
            if model.loadingDetails.contains(conversationId) {
                LoadingView(text: "Loading messages…")
            } else if let error = model.detailErrors[conversationId] {
                EmptyState(title: "Couldn’t load the messages", message: error) {
                    Button("Try again") { Task { await model.loadDetail(conversationId, app: app, force: true) } }.buttonStyle(.thubanSecondary)
                }
            } else {
                EmptyState(title: "No messages", message: "This conversation has no messages you can see.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(list) { message in
                        MessageCard(message: message, conversation: conversation)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Reply

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if reply.isEmpty {
                    Text("Reply to everyone in this conversation…")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkFaintColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $reply)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkColor)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(height: 84)
                    .accessibilityLabel("Reply")
            }
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
            HStack(spacing: 10) {
                if !app.settings.writesEnabled {
                    Text("Sending to Canvas is turned off in Settings › Connection.").font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                } else if let error = sendError, !confirmingReply {
                    Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor).lineLimit(1)
                }
                Spacer()
                Button("Reply") { sendError = nil; confirmingReply = true }
                    .buttonStyle(PrimaryButtonStyle(height: 30))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canReply)
                    .accessibilityLabel("Reply to the conversation")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(theme.bgColor)
        .thubanHairline(.top, color: theme.lineColor)
    }

    private var canReply: Bool {
        app.settings.writesEnabled && app.client != nil && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// Runs only from the confirm sheet.
    private func sendReply() {
        guard canReply, let client = app.client else { return }
        let body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        sendError = nil
        Task {
            defer { isSending = false }
            do {
                let updated = try await client.replyToConversation(conversationId, body: body)
                model.apply(updated, app: app)
                await model.loadDetail(conversationId, app: app, force: true)
                reply = ""
                confirmingReply = false
                await app.refreshUnreadCount()
            } catch {
                sendError = error.localizedDescription
            }
        }
    }
}

/// Author avatar + name, date, the body as selectable text, and attachment rows.
private struct MessageCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var message: ConversationMessage
    var conversation: Conversation

    private var author: ConversationParticipant? { conversation.participant(message.authorId) }
    private var isMine: Bool { message.authorId != nil && message.authorId == app.user?.id }
    private var authorName: String {
        if isMine { return "You" }
        return author?.name ?? "Unknown sender"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(name: isMine ? (app.user?.name ?? "You") : (author?.name ?? "?"), url: author?.avatarUrl ?? (isMine ? app.user?.avatarUrl : nil), size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(authorName)
                        .font(.system(size: 14 * textScale, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                    if let date = message.createdAt {
                        Text(DueFormatter.relative(date))
                            .font(.system(size: 12 * textScale))
                            .foregroundStyle(theme.inkDimColor)
                            .help(date.formatted(date: .long, time: .shortened))
                    }
                }
                Spacer()
                if message.generated == true { Chip("Automatic", kind: .neutral) }
            }
            if let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                Text(body)
                    .font(.system(size: 14 * textScale))
                    .foregroundStyle(theme.inkColor)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("(Empty message)").font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
            }
            if let attachments = message.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(attachments) { file in AttachmentRow(file: file) }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .thubanPanel(padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message from \(authorName)")
    }
}

/// Paperclip, file name and size; opens the download URL in the browser (the link carries its own verifier).
private struct AttachmentRow: View {
    @Environment(\.thubanTheme) private var theme
    var file: CanvasFile
    @State private var hovering = false

    var body: some View {
        Button {
            if let raw = file.url, let url = URL(string: raw) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperclip").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                Text(file.displayName).font(ThubanFont.small).foregroundStyle(theme.inkColor).lineLimit(1)
                if let size = file.size {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkFaintColor)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(hovering ? theme.panel2Color : theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(file.url == nil)
        .accessibilityLabel("Open attachment \(file.displayName)")
        .help(file.url == nil ? "No download link" : "Open in the browser")
    }
}
