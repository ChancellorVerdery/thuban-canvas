import SwiftUI
import ThubanCanvasCore

/// New message: pick a course, choose recipients from its people (search, multi-select), subject and body.
/// "Send" swaps the sheet to a `ConfirmWriteSheet`; only its confirm button calls `createConversation`.
struct ComposeMessageSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var model: InboxModel
    @State private var courseId: CanvasID?
    @State private var recipients: [CanvasID] = []
    @State private var recipientSearch = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var choosingCourse = false
    @State private var confirming = false
    @State private var isSending = false
    @State private var sendError: String?

    private var session: CourseSession? { courseId.flatMap { app.sessions[$0] } }

    var body: some View {
        Group {
            if confirming {
                ConfirmWriteSheet(
                    title: "Send this message?",
                    message: "To \(recipientNames.joined(separator: ", ")) in \(session?.displayName ?? "the course") — “\(subject.trimmingCharacters(in: .whitespaces))”. Canvas delivers it to their inbox and email.",
                    actionLabel: "Send",
                    isWorking: isSending,
                    error: sendError,
                    confirm: send,
                    cancel: { confirming = false }
                )
            } else {
                form
            }
        }
        .onAppear { if courseId == nil { courseId = app.orderedSessions.first?.id } }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New message").font(ThubanFont.display(20)).foregroundStyle(theme.inkColor)
                Spacer()
                IconButton(glyph: .close, label: "Cancel", size: 28, iconSize: 14) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Course")
                Button {
                    choosingCourse.toggle()
                } label: {
                    HStack(spacing: 8) {
                        CourseDot(tint: session?.preferences.tint, size: 8)
                        Text(session?.displayName ?? "Choose a course").foregroundStyle(session == nil ? theme.inkFaintColor : theme.inkColor)
                        Spacer()
                        Glyph(.chevronDown, size: 14).foregroundStyle(theme.inkDimColor)
                    }
                    .font(ThubanFont.body(14))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                    .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Course: \(session?.displayName ?? "none chosen")")
                .popover(isPresented: $choosingCourse, arrowEdge: .bottom) {
                    VStack(spacing: 0) {
                        ForEach(app.orderedSessions) { candidate in
                            PickRow(title: candidate.displayName, detail: candidate.shortCode, tint: candidate.preferences.tint,
                                    isSelected: candidate.id == courseId) {
                                selectCourse(candidate.id)
                                choosingCourse = false
                            }
                        }
                    }
                    .padding(6)
                    .frame(width: 320)
                    .background(theme.panelColor)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                eyebrow("To")
                if !recipients.isEmpty {
                    FlowChips(items: recipients.compactMap { id in person(id).map { (id, $0.name) } }) { id in
                        recipients.removeAll { $0 == id }
                    }
                }
                SearchField(text: $recipientSearch, placeholder: session == nil ? "Choose a course first" : "Search people in \(session?.compactTitle ?? "the course")")
                    .disabled(session == nil)
                    .accessibilityLabel("Search recipients")
                peopleList
            }

            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Subject")
                TextField("Subject", text: $subject)
                    .thubanField(height: 34)
                    .accessibilityLabel("Subject")
            }

            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Message")
                TextEditor(text: $messageBody)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkColor)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(height: 150)
                    .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                    .accessibilityLabel("Message body")
            }

            HStack(spacing: 10) {
                if let error = sendError { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor).lineLimit(2) }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.thubanSecondary)
                Button("Send…") { sendError = nil; confirming = true }
                    .buttonStyle(.thubanPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
                    .help(canSend ? "Review and send" : "Choose recipients, a subject and a message")
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(theme.panelColor)
        .task(id: courseId) { await session?.loadPeople() }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
    }

    // MARK: People

    /// Everyone in the course except the signed-in user: teachers and TAs first, then by sortable name.
    private var people: [CourseUser] {
        let me = app.user?.id
        return (session?.people.value ?? [])
            .filter { $0.id != me }
            .sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                return (a.sortableName ?? a.name).localizedStandardCompare(b.sortableName ?? b.name) == .orderedAscending
            }
    }

    private func rank(_ user: CourseUser) -> Int {
        switch user.roleLabel {
        case "Teacher": return 0
        case "TA": return 1
        case "Designer": return 2
        default: return 3
        }
    }

    private var matches: [CourseUser] {
        let query = recipientSearch.trimmingCharacters(in: .whitespaces)
        let pool = query.isEmpty ? people.filter { rank($0) < 3 } : people.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return Array(pool.prefix(8))
    }

    private func person(_ id: CanvasID) -> CourseUser? { session?.people.value?.first { $0.id == id } }

    private var recipientNames: [String] { recipients.compactMap { person($0)?.name } }

    @ViewBuilder
    private var peopleList: some View {
        if let session {
            if session.people.isLoading && !session.people.hasValue {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading people…").font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                }
                .frame(height: 32)
            } else if session.people.unavailable {
                Text("The People list is hidden for this course, so recipients can’t be chosen here.")
                    .font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            } else if let error = session.people.error, !session.people.hasValue {
                Text(error.localizedDescription).font(ThubanFont.small).foregroundStyle(theme.negTextColor)
            } else if matches.isEmpty {
                Text(recipientSearch.isEmpty ? "Type a name to find classmates." : "No one matches “\(recipientSearch)”.")
                    .font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                    .frame(height: 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(matches) { user in
                        PersonRow(user: user, isSelected: recipients.contains(user.id)) {
                            if let index = recipients.firstIndex(of: user.id) { recipients.remove(at: index) } else { recipients.append(user.id) }
                        }
                    }
                }
                .thubanPanel(padding: 0)
            }
        }
    }

    private func selectCourse(_ id: CanvasID) {
        guard id != courseId else { return }
        courseId = id
        recipients = []
        recipientSearch = ""
    }

    // MARK: Send

    private var canSend: Bool {
        app.settings.writesEnabled && app.client != nil && courseId != nil && !recipients.isEmpty
            && !subject.trimmingCharacters(in: .whitespaces).isEmpty && !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// Runs only from the confirm sheet.
    private func send() {
        guard canSend, let client = app.client else { return }
        isSending = true
        sendError = nil
        let recipientIds = recipients
        let subjectText = subject.trimmingCharacters(in: .whitespaces)
        let bodyText = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let course = courseId
        Task {
            defer { isSending = false }
            do {
                try await client.createConversation(recipients: recipientIds, subject: subjectText, body: bodyText, course: course)
                await model.load(scope: .sent, app: app, force: true)
                await model.load(scope: .all, app: app, force: true)
                dismiss()
            } catch {
                sendError = error.localizedDescription
            }
        }
    }
}

/// One course in the course popover: dot, name, code; a check mark when selected.
private struct PickRow: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var detail: String
    var tint: String?
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CourseDot(tint: tint, size: 8)
                Text(title).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                Text(detail).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                Spacer()
                if isSelected { Glyph(.check, size: 14).foregroundStyle(theme.brassInkColor) }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear), in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A person in the recipient picker: avatar, name, role; a check mark when selected.
private struct PersonRow: View {
    @Environment(\.thubanTheme) private var theme
    var user: CourseUser
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AvatarView(name: user.name, url: user.avatarUrl, size: 24)
                Text(user.name).font(ThubanFont.body(14)).foregroundStyle(theme.inkColor).lineLimit(1)
                Text(user.roleLabel).font(ThubanFont.small).foregroundStyle(user.roleLabel == "Student" ? theme.inkFaintColor : theme.brassInkColor)
                Spacer()
                if isSelected { Glyph(.check, size: 14).foregroundStyle(theme.brassInkColor) }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(user.name), \(user.roleLabel)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Selected recipients as removable chips, wrapping onto new lines.
private struct FlowChips: View {
    @Environment(\.thubanTheme) private var theme
    var items: [(id: CanvasID, name: String)]
    var remove: (CanvasID) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.id) { item in
                HStack(spacing: 5) {
                    Text(item.name).lineLimit(1)
                    Button { remove(item.id) } label: { Glyph(.close, size: 11) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(item.name)")
                }
                .thubanChip(kind: .accent)
            }
        }
    }
}

/// Left-to-right wrapping layout for chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in placement.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}
