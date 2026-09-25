import SwiftUI
import ThubanCanvasCore

/// Assignment detail. Read-only: "Submit in Canvas" opens the assignment in Safari, where Canvas handles the
/// submission; nothing here writes.
struct AssignmentScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var courseId: CanvasID
    var assignmentId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            let assignment = session.assignment(assignmentId)
            PushedScreen(assignment?.isQuizAssignment == true ? "Quiz" : "Assignment", back: back) {
                if let assignment { AssignmentShareMenu(assignment: assignment) }
            } content: {
                AssignmentContent(session: session, assignmentId: assignmentId)
            } bottom: {
                if let assignment { SubmitInCanvasBar(assignment: assignment) }
            }
            .refreshable { await session.loadGroups(force: true) }
        }
    }
}

struct AssignmentShareMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var assignment: Assignment

    var body: some View {
        if let raw = assignment.htmlUrl, let url = URL(string: raw) {
            Menu {
                Button { app.openInSafari(url) } label: { Label("Open in Canvas", systemImage: "safari") }
                ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 19, weight: .regular)).foregroundStyle(theme.brassInkColor)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Share or open in Canvas")
        }
    }
}

/// Bottom bar: the one primary action, plus the read-only note.
struct SubmitInCanvasBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var assignment: Assignment
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: title, systemImage: "arrow.up.forward.square") {
                if let raw = assignment.htmlUrl, let url = URL(string: raw) { app.openInSafari(url) }
            }
            .disabled(assignment.htmlUrl == nil)
            Text(note).tFont(.footnote).foregroundStyle(theme.inkDimColor).multilineTextAlignment(.center)
        }
        .padding(.horizontal, IOSMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, compact ? 12 : 8)
        .frame(maxWidth: .infinity)
        .background(theme.panelColor.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
    }

    private var canSubmit: Bool {
        assignment.acceptsOnlineSubmission || assignment.submissionTypes?.contains("online_quiz") == true
            || assignment.submissionTypes?.contains("external_tool") == true
    }

    private var title: String { canSubmit ? (assignment.isQuizAssignment == true ? "Take quiz in Canvas" : "Submit in Canvas") : "Open in Canvas" }

    private var note: String {
        canSubmit ? "Thuban Canvas only reads. Submitting opens Safari." : "Nothing to hand in online. Thuban Canvas only reads."
    }
}

struct AssignmentContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    var assignmentId: CanvasID
    var showsTitle = true
    @State private var fileSizes: [CanvasID: Int] = [:]
    @State private var comments: [SubmissionComment] = []

    var body: some View {
        Group {
            if let assignment = session.assignment(assignmentId) {
                VStack(alignment: .leading, spacing: 14) {
                    if showsTitle { header(assignment) }
                    dueCard(assignment)
                    facts(assignment)
                    if let html = assignment.description, !CanvasHTML.plainText(html).isEmpty || html.contains("<img") {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeading("Instructions")
                            Card { HTMLContentView(html: html) }
                        }
                    }
                    if let stats = assignment.scoreStatistics, let submission = assignment.submission, submission.isGraded {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeading("Class scores")
                            Card { ScoreDistribution(stats: stats, score: submission.score, possible: assignment.pointsPossible).padding(16) }
                        }
                    }
                    filesAndReminders(assignment)
                    if !comments.isEmpty { commentsCard }
                }
                .padding(.top, showsTitle ? 8 : 0)
                .gutter()
                .task(id: assignment.id) { await loadExtras(assignment) }
            } else if session.groups.isLoading || !session.groups.hasAttempted {
                LoadingCard().gutter().padding(.top, 12)
            } else {
                ScreenMessage(systemName: "questionmark.square.dashed", title: "Assignment not found", message: "It may have been unpublished.")
            }
        }
        .task(id: session.id) { await session.loadGroups(); if session.course.hasTab("modules") { await session.loadModules() } }
    }

    private func header(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(eyebrow(assignment))
            Text(assignment.name).tFont(.display(26)).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
        }
    }

    private func eyebrow(_ assignment: Assignment) -> String {
        var parts = [session.shortTitle]
        if let module = (session.modules.value ?? []).first(where: { ($0.items ?? []).contains { $0.contentId == assignment.id || ($0.type == "Quiz" && $0.contentId == assignment.quizId) } }) {
            parts.append(ModuleName.split(module.name).eyebrow ?? module.name)
        }
        parts.append(assignment.isQuizAssignment == true ? "Quiz" : (assignment.discussionTopic != nil ? "Discussion" : "Assignment"))
        return parts.joined(separator: " · ")
    }

    // MARK: Due card

    private func dueCard(_ assignment: Assignment) -> some View {
        let item = WorkItem(assignment: assignment, courseId: session.id, courseName: session.displayName)
        let overdue = item.status == .overdue
        let fill = overdue ? theme.negSoftColor : theme.accentTintColor
        let border = overdue ? theme.negColor : theme.accentColor
        let eyebrowColor = overdue ? theme.negTextColor : theme.brassInkColor
        return Card(border: border, fill: fill) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(assignment.dueAt.map { DueFormatter.dueEyebrow($0) } ?? "No due date")
                        .tFont(.text(13, .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(eyebrowColor)
                    Spacer(minLength: 6)
                    statusChip(assignment, item: item)
                }
                if let due = assignment.dueAt {
                    Text(DueFormatter.full(due)).tFont(.display(24)).foregroundStyle(theme.inkColor)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        countdownLine(due: due, item: item, now: context.date)
                    }
                } else if let unlock = assignment.unlockAt, assignment.lockedForUser == true {
                    Text("Opens \(DueFormatter.full(unlock))").tFont(.display(22)).foregroundStyle(theme.inkColor)
                }
                if assignment.lockedForUser == true, let explanation = assignment.lockExplanation {
                    Text(CanvasHTML.plainText(explanation)).tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func countdownLine(due: Date, item: WorkItem, now: Date) -> some View {
        if item.status == .upcoming {
            (Text("in ") + Text(DueFormatter.preciseCountdown(due, now: now).replacingOccurrences(of: "in ", with: ""))
                .font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundColor(theme.inkColor))
                .tFont(.secondary).foregroundStyle(theme.inkDimColor)
        } else if item.status == .overdue {
            Text(DueFormatter.lateness(due, now: now)).tFont(.text(15, .semibold)).foregroundStyle(theme.negTextColor)
        } else if let submitted = session.assignment(assignmentId)?.submission?.submittedAt {
            Text("Handed in \(DueFormatter.compact(submitted, now: now))").tFont(.secondary).foregroundStyle(theme.inkDimColor)
        }
    }

    @ViewBuilder
    private func statusChip(_ assignment: Assignment, item: WorkItem) -> some View {
        switch item.status {
        case .graded:
            ChipView("Graded \(PointsText.short(assignment.submission?.score)) / \(PointsText.short(assignment.pointsPossible))", kind: .pos)
        case .submitted: ChipView("Submitted", kind: .pos)
        case .excused: ChipView("Excused", kind: .neutral)
        case .overdue: ChipView("Missing", kind: .neg)
        case .upcoming, .noDate:
            Text(assignment.lockedForUser == true ? "Locked" : "Not submitted yet")
                .tFont(.text(12.5, .semibold)).foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 8).frame(minHeight: 22)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: Facts

    private func facts(_ assignment: Assignment) -> some View {
        Card {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    fact("Points", PointsText.short(assignment.pointsPossible), mono: true)
                    Rectangle().fill(theme.lineColor).frame(width: 1)
                    fact("Submit as", assignment.submitAsLabel)
                }
                Rectangle().fill(theme.lineColor).frame(height: 1).gridCellColumns(3)
                GridRow {
                    fact("Attempts", assignment.attemptsLabel)
                    Rectangle().fill(theme.lineColor).frame(width: 1)
                    fact("Group", session.groupLabel(of: assignment) ?? "—")
                }
            }
        }
    }

    private func fact(_ key: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).tFont(.text(12, .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(theme.inkFaintColor)
            Text(value).tFont(mono ? .mono(17, .semibold) : .text(16, .semibold)).foregroundStyle(theme.inkColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Files & reminders

    private func filesAndReminders(_ assignment: Assignment) -> some View {
        let links = CanvasHTML.fileLinks(assignment.description, host: app.host)
        return Card {
            ForEach(links, id: \.id) { link in
                Button { Task { await app.openFile(course: link.course ?? session.id, id: link.id) } } label: {
                    HStack(spacing: 12) {
                        FileBadge(name: link.name)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.name).tFont(.text(16, .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
                            Text([fileSizes[link.id].map { DueFormatter.bytes($0) }, "attached by instructor"].compactMap { $0 }.joined(separator: " · "))
                                .tFont(.footnote).foregroundStyle(theme.inkDimColor)
                        }
                        Spacer(minLength: 8)
                        if app.downloadingFile == link.id { ProgressView().tint(theme.brassInkColor) } else { RowChevron() }
                    }
                    .padding(.leading, 16).padding(.trailing, 12)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens in Quick Look")
                RowDivider()
            }
            Button { app.settingsPage = .reminders; app.showingSettings = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 18, weight: .regular)).foregroundStyle(theme.brassInkColor)
                    Text("Reminders").tFont(.body).foregroundStyle(theme.inkColor)
                    Spacer(minLength: 8)
                    Text(reminderText).tFont(.secondary).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: IOSMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Opens reminder settings")
        }
    }

    private var reminderText: String {
        let prefs = app.settings.notifications
        guard prefs.enabled, !prefs.leadHours.isEmpty else { return "Off" }
        return DueFormatter.leadTimes(prefs.leadHours) + " before"
    }

    private var commentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Comments")
            Card {
                ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                    if index > 0 { RowDivider() }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(comment.authorName ?? "Instructor").tFont(.text(15, .semibold)).foregroundStyle(theme.inkColor)
                            Spacer()
                            if let date = comment.createdAt { Text(DueFormatter.compact(date)).tFont(.footnote).foregroundStyle(theme.inkFaintColor) }
                        }
                        Text(comment.comment).tFont(.secondary).foregroundStyle(theme.inkColor)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }

    private func loadExtras(_ assignment: Assignment) async {
        guard let client = app.client else { return }
        for link in CanvasHTML.fileLinks(assignment.description, host: app.host) where fileSizes[link.id] == nil {
            if let file = try? await client.courseFile(course: link.course ?? session.id, id: link.id), let size = file.size {
                fileSizes[link.id] = size
            }
        }
        if assignment.submission?.isGraded == true || assignment.submission?.isSubmitted == true,
           let submission = try? await client.submission(course: session.id, assignment: assignment.id) {
            comments = submission.submissionComments ?? []
        }
    }
}

/// "PDF" tile in loss tones (the brief's file badge); other kinds in neutral.
struct FileBadge: View {
    @Environment(\.thubanTheme) private var theme
    var name: String

    var body: some View {
        let ext = (name as NSString).pathExtension.uppercased()
        let isPDF = ext == "PDF"
        Text(ext.isEmpty ? "FILE" : String(ext.prefix(4)))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isPDF ? theme.negTextColor : theme.inkDimColor)
            .frame(width: 32, height: 32)
            .background(isPDF ? theme.negSoftColor : theme.panel2Color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Low / middle half / median / high with the student's mark.
struct ScoreDistribution: View {
    @Environment(\.thubanTheme) private var theme
    var stats: ScoreStatistics
    var score: Double?
    var possible: Double?

    var body: some View {
        let low = stats.min ?? 0
        let high = max(stats.max ?? possible ?? 100, low + 0.001)
        let span = high - low
        func x(_ value: Double?, _ width: CGFloat) -> CGFloat {
            guard let value else { return 0 }
            return CGFloat((min(max(value, low), high) - low) / span) * width
        }
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(theme.lineColor).frame(height: 2).offset(y: 12)
                    if let lower = stats.lowerQ, let upper = stats.upperQ {
                        RoundedRectangle(cornerRadius: 3).fill(theme.signalSoftColor)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(theme.signalColor, lineWidth: 1))
                            .frame(width: max(2, x(upper, width) - x(lower, width)), height: 12)
                            .offset(x: x(lower, width), y: 7)
                    }
                    if let median = stats.median {
                        Rectangle().fill(theme.signalTextColor).frame(width: 2, height: 16).offset(x: x(median, width) - 1, y: 5)
                    }
                    if let score {
                        RoundedRectangle(cornerRadius: 4).fill(theme.accentColor)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.panelColor, lineWidth: 2))
                            .frame(width: 14, height: 20)
                            .offset(x: x(score, width) - 7, y: 3)
                    }
                }
            }
            .frame(height: 26)
            HStack {
                Text(PointsText.short(stats.min))
                Spacer()
                Text("median \(PointsText.short(stats.median)) · mean \(String(format: "%.1f", stats.mean ?? 0))")
                Spacer()
                Text(PointsText.short(stats.max))
            }
            .tFont(.mono(12))
            .foregroundStyle(theme.inkFaintColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Class scores: low \(PointsText.short(stats.min)), middle half \(PointsText.short(stats.lowerQ)) to \(PointsText.short(stats.upperQ)), median \(PointsText.short(stats.median)), high \(PointsText.short(stats.max))\(score.map { "; you \(PointsText.short($0))" } ?? "")")
    }
}
