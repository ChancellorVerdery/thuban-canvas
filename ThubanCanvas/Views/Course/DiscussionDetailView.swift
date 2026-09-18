import SwiftUI
import ThubanCanvasCore

/// A discussion topic or announcement: header (title, author, date, attachments), then the message and every
/// threaded reply in one themed web view, and a reply box at the bottom that confirms before posting. Reading
/// here never marks the topic read.
struct DiscussionDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var topicId: CanvasID

    @State private var fetched: DiscussionTopic?
    @State private var fetchError: String?
    @State private var thread: DiscussionView?
    @State private var threadError: String?
    @State private var isLoadingThread = false
    @State private var isReplying = false
    @State private var replyText = ""
    @State private var confirming = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var successNote: String?

    private var topic: DiscussionTopic? {
        session.announcements.value?.first { $0.id == topicId }
            ?? session.discussions.value?.first { $0.id == topicId }
            ?? app.announcements.value?.first { $0.id == topicId && $0.courseId == session.id }
            ?? fetched
    }

    var body: some View {
        Group {
            if let topic {
                content(topic)
            } else if let fetchError {
                EmptyState(title: "Couldn’t load discussion", message: fetchError) {
                    Button("Try again") { Task { await load() } }.buttonStyle(.thubanSecondary)
                }
            } else {
                LoadingView()
            }
        }
        .task(id: topicId) { await load() }
        .sheet(isPresented: $confirming) {
            if let topic {
                ConfirmWriteSheet(
                    title: "Post reply?",
                    message: "This posts your reply to “\(topic.title)” in \(session.displayName) and cannot be undone here.",
                    actionLabel: "Post reply",
                    isWorking: isSending,
                    error: sendError,
                    confirm: { Task { await postReply(to: topic) } },
                    cancel: { if !isSending { confirming = false } }
                )
            }
        }
    }

    // MARK: Layout

    private func content(_ topic: DiscussionTopic) -> some View {
        VStack(spacing: 0) {
            header(topic)
            CanvasHTMLView(html: DiscussionThreadHTML.compose(topic: topic, thread: thread))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            replyArea(topic)
        }
    }

    private func header(_ topic: DiscussionTopic) -> some View {
        let author = topic.author?.displayName ?? topic.userName
        return DetailHeader(eyebrow: eyebrow(topic), title: topic.title, titleLineLimit: 3) {
            HStack(spacing: 10) {
                if let author {
                    HStack(spacing: 8) {
                        AvatarView(name: author, url: topic.author?.avatarImageUrl, size: 26)
                        Text(author).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Posted by \(author)")
                }
                if let posted = topic.postedAt {
                    Text(WorkText.full(posted)).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkDimColor)
                } else if let delayed = topic.delayedPostUntil {
                    Text("Scheduled for " + WorkText.full(delayed)).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkDimColor)
                }
                if let unread = topic.unreadCount, unread > 0 { Chip("\(unread) unread", kind: .accent) }
                else if topic.readState == "unread" { Chip("Unread", kind: .accent) }
                if topic.assignmentId != nil { Chip("Graded", kind: .signal) }
                if topic.locked == true || topic.lockedForUser == true { Chip("Locked", kind: .neutral) }
            }
        } actions: {
            HStack(spacing: 8) {
                if let assignmentId = topic.assignmentId {
                    Button("Assignment") { session.path.append(.assignment(assignmentId)) }.buttonStyle(.thubanGhostTinted)
                }
                Button("Open in Canvas") { CanvasBrowser.open(topic.htmlUrl) }
                    .buttonStyle(.thubanGhostTinted)
                    .disabled(topic.htmlUrl == nil)
                    .accessibilityLabel("Open in Canvas (opens your browser)")
            }
        } below: {
            if let attachments = topic.attachments, !attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(attachments) { file in
                        Button {
                            session.path.append(.file(file.id))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "paperclip").font(.system(size: 12, weight: .semibold))
                                Text(file.displayName).lineLimit(1)
                                if let size = file.size {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).foregroundStyle(theme.inkFaintColor)
                                }
                            }
                        }
                        .buttonStyle(.thubanSecondary)
                        .accessibilityLabel("Open attachment \(file.displayName)")
                    }
                }
            }
            if let threadError {
                InlineNote(symbol: "bubble.left.and.exclamationmark.bubble.right", text: threadError, tone: .warn)
            }
            if let successNote {
                InlineNote(symbol: "checkmark.circle", text: successNote, tone: .pos)
            }
        }
    }

    private func eyebrow(_ topic: DiscussionTopic) -> String {
        var parts = [topic.isAnnouncement == true || session.announcements.value?.contains { $0.id == topic.id } == true ? "ANNOUNCEMENT" : "DISCUSSION"]
        if topic.pinned == true { parts.append("PINNED") }
        if let count = topic.discussionSubentryCount, count > 0 { parts.append(WorkText.count(count, "REPLY", "REPLIES")) }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Reply box

    private func canReply(_ topic: DiscussionTopic) -> Bool {
        app.settings.writesEnabled && topic.canReply != false && topic.lockedForUser != true && topic.locked != true
    }

    @ViewBuilder
    private func replyArea(_ topic: DiscussionTopic) -> some View {
        if canReply(topic) {
            VStack(alignment: .leading, spacing: 10) {
                if isReplying {
                    TextEditor(text: $replyText)
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkColor)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 110)
                        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                        .accessibilityLabel("Your reply")
                    HStack {
                        Text("You will confirm before it is posted.").font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                        Spacer()
                        Button("Cancel") { isReplying = false }.buttonStyle(.thubanGhost).keyboardShortcut(.cancelAction)
                        Button("Post reply…") { sendError = nil; confirming = true }
                            .buttonStyle(.thubanPrimary)
                            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                            .accessibilityLabel("Post reply to Canvas")
                    }
                } else {
                    HStack {
                        Button {
                            isReplying = true
                        } label: {
                            HStack(spacing: 6) { Image(systemName: "arrowshape.turn.up.left").font(.system(size: 12, weight: .semibold)); Text("Reply") }
                        }
                        .buttonStyle(.thubanSecondary)
                        .accessibilityLabel("Write a reply")
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(theme.panelColor)
            .thubanHairline(.top, color: theme.lineColor)
        } else if topic.locked == true || topic.lockedForUser == true {
            HStack(spacing: 8) {
                Glyph(.lock, size: 13).foregroundStyle(theme.inkFaintColor)
                Text("Replies are closed for this topic.").font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 40)
            .background(theme.panelColor)
            .thubanHairline(.top, color: theme.lineColor)
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client = app.client else { return }
        if topic == nil {
            do { fetched = try await client.discussion(course: session.id, id: topicId) }
            catch { fetchError = error.localizedDescription; return }
        }
        guard !isLoadingThread else { return }
        isLoadingThread = true
        defer { isLoadingThread = false }
        do {
            thread = try await client.discussionView(course: session.id, topic: topicId)
            threadError = nil
        } catch let error as ThubanError {
            if case .unavailable = error, topic?.discussionType != nil, topic?.canReply != false {
                threadError = "Replies are hidden until you post your own."
            } else if case .unavailable = error {
                threadError = "Canvas did not return the replies for this topic."
            } else {
                threadError = "Couldn’t load replies — \(error.localizedDescription)"
            }
        } catch {
            threadError = "Couldn’t load replies — \(error.localizedDescription)"
        }
    }

    // MARK: Posting (only after ConfirmWriteSheet)

    private func postReply(to topic: DiscussionTopic) async {
        guard let client = app.client, !isSending else { return }
        isSending = true
        defer { isSending = false }
        let message = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let entry = try await client.postDiscussionEntry(course: session.id, topic: topic.id, message: message)
            // Re-read the thread so the new entry shows with its participant name; fall back to appending locally.
            if let refreshed = try? await client.discussionView(course: session.id, topic: topic.id) {
                thread = refreshed
                threadError = nil
            } else if var updated = thread {
                updated.view = (updated.view ?? []) + [entry]
                thread = updated
            }
            replyText = ""
            isReplying = false
            confirming = false
            successNote = "Reply posted · " + WorkText.full(entry.createdAt ?? Date())
            // The list rows and eyebrow show reply counts from the cached topic list; refresh it.
            if topic.isAnnouncement == true || session.announcements.value?.contains { $0.id == topic.id } == true {
                await session.loadAnnouncements(force: true)
            } else {
                await session.loadDiscussions(force: true)
            }
        } catch {
            sendError = error.localizedDescription
        }
    }
}
