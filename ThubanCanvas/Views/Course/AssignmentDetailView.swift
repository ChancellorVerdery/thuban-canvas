import SwiftUI
import ThubanCanvasCore

/// One assignment: header (name, due, points, submission types, group, lock state, actions), the description as
/// themed HTML filling the remaining height, and a grade panel on the right (score, dates, class statistics,
/// grader comments, your files). Submitting opens `SubmitSheet`, which confirms before anything is sent.
struct AssignmentDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var assignmentId: CanvasID

    @State private var fetched: Assignment?
    @State private var fetchError: String?
    @State private var submission: Submission?
    @State private var showingSubmit = false
    @State private var successNote: String?

    private var assignment: Assignment? { session.assignment(assignmentId) ?? fetched }

    var body: some View {
        Group {
            if let assignment {
                content(assignment)
            } else if let fetchError {
                EmptyState(title: "Couldn’t load assignment", message: fetchError) {
                    Button("Try again") { Task { await load() } }.buttonStyle(.thubanSecondary)
                }
            } else {
                LoadingView()
            }
        }
        .task(id: assignmentId) { await load() }
        .sheet(isPresented: $showingSubmit) {
            if let assignment {
                SubmitSheet(session: session, assignment: assignment, onSubmitted: { result in
                    submission = result
                    successNote = "Submitted to Canvas · " + WorkText.full(result.submittedAt ?? Date())
                }, dismiss: { showingSubmit = false })
            }
        }
    }

    // MARK: Layout

    private func content(_ assignment: Assignment) -> some View {
        VStack(spacing: 0) {
            header(assignment)
            HStack(spacing: 0) {
                description(assignment)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(theme.lineColor).frame(width: ThubanMetrics.hairline)
                ScrollView {
                    GradePanel(assignment: assignment, submission: submission ?? assignment.submission, session: session)
                        .padding(20)
                }
                .frame(width: 320)
                .background(theme.panelColor)
            }
        }
    }

    @ViewBuilder
    private func description(_ assignment: Assignment) -> some View {
        if let html = assignment.description, !CanvasHTML.plainText(html, limit: 4).isEmpty || html.contains("<img") || html.contains("<iframe") {
            CanvasHTMLView(html: html)
        } else {
            EmptyState(title: "No description", message: "The instructor did not add details for this assignment.")
        }
    }

    // MARK: Header

    private func header(_ assignment: Assignment) -> some View {
        let item = WorkItem(assignment: assignment, courseId: session.id, courseName: session.displayName)
        return DetailHeader(eyebrow: eyebrow(for: assignment), title: assignment.name, titleLineLimit: 3) {
            HStack(spacing: 6) {
                if let chip = Chip.status(item) { chip }
                if assignment.published == false { Chip("Unpublished", kind: .warn) }
                if assignment.lockedForUser == true { Chip("Locked", kind: .neutral) }
                ForEach(WorkText.submissionTypes(assignment), id: \.self) { Chip($0, kind: .neutral) }
                if assignment.omitFromFinalGrade == true { Chip("Not in final grade", kind: .neutral) }
            }
        } actions: {
            actions(assignment)
        } below: {
            HStack(alignment: .top, spacing: 28) {
                MetaField(label: "Due", value: dueText(assignment), tone: item.status == .overdue ? .neg : .normal)
                MetaField(label: "Points", value: assignment.pointsPossible.map { DueFormatter.points($0) } ?? "Ungraded", tone: assignment.pointsPossible == nil ? .dim : .normal)
                if let unlock = assignment.unlockAt, unlock > Date() {
                    MetaField(label: "Opens", value: WorkText.full(unlock))
                }
                if let lock = assignment.lockAt {
                    MetaField(label: lock > Date() ? "Closes" : "Closed", value: WorkText.full(lock), tone: lock > Date() ? .normal : .dim)
                }
                if let attempts = assignment.allowedAttempts, attempts > 0 {
                    MetaField(label: "Attempts", value: "\(attempts)")
                }
            }
            notes(assignment)
        }
    }

    private func eyebrow(for assignment: Assignment) -> String {
        var parts = [assignment.kind.label.uppercased()]
        if let group = session.groups.value?.first(where: { $0.id == assignment.assignmentGroupId }) {
            var name = group.name.uppercased()
            if let weight = WorkText.weight(group.groupWeight), (group.groupWeight ?? 0) > 0 { name += " · \(weight)" }
            parts.append(name)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func dueText(_ assignment: Assignment) -> String {
        guard let due = assignment.dueAt else { return "No due date" }
        return WorkText.full(due) + " · " + DueFormatter.countdown(due)
    }

    @ViewBuilder
    private func notes(_ assignment: Assignment) -> some View {
        if let successNote {
            InlineNote(symbol: "checkmark.circle", text: successNote, tone: .pos)
        }
        if assignment.lockedForUser == true {
            let explanation = CanvasHTML.plainText(assignment.lockExplanation, limit: 240)
            InlineNote(symbol: "lock", text: explanation.isEmpty ? "This assignment is locked." : explanation)
        }
        if assignment.kind == .quiz {
            InlineNote(symbol: "arrow.up.right.square", text: "Quizzes are taken on the Canvas website. Your score shows here once it is graded.")
        } else if assignment.isExternalTool {
            InlineNote(symbol: "arrow.up.right.square", text: "Opens in Canvas — this assignment runs in an external tool.")
        } else if !assignment.acceptsOnlineSubmission, assignment.isOnPaperOrNone {
            InlineNote(symbol: "hand.raised", text: assignment.submissionTypes?.contains("on_paper") == true ? "Handed in on paper — nothing to upload here." : "No submission is collected for this assignment.")
        }
    }

    @ViewBuilder
    private func actions(_ assignment: Assignment) -> some View {
        HStack(spacing: 8) {
            if assignment.kind == .quiz {
                Button("Take quiz in Canvas") { CanvasBrowser.open(assignment.htmlUrl) }
                    .buttonStyle(.thubanPrimary)
                    .disabled(assignment.htmlUrl == nil)
                    .accessibilityLabel("Take quiz in Canvas (opens your browser)")
                if let quiz = assignment.quizId {
                    Button("Quiz details") { session.path.append(.quiz(quiz)) }.buttonStyle(.thubanGhostTinted)
                }
            } else if assignment.isExternalTool {
                Button("Open in Canvas") { CanvasBrowser.open(assignment.htmlUrl) }
                    .buttonStyle(.thubanPrimary)
                    .disabled(assignment.htmlUrl == nil)
                    .accessibilityLabel("Open in Canvas (opens your browser)")
            } else {
                if app.settings.writesEnabled, assignment.acceptsOnlineSubmission, assignment.lockedForUser != true {
                    Button(hasSubmission(assignment) ? "Resubmit" : "Submit") { showingSubmit = true }
                        .buttonStyle(.thubanSecondary)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel(hasSubmission(assignment) ? "Resubmit this assignment" : "Submit this assignment")
                }
                Button("Open in Canvas") { CanvasBrowser.open(assignment.htmlUrl) }
                    .buttonStyle(.thubanGhostTinted)
                    .disabled(assignment.htmlUrl == nil)
                    .accessibilityLabel("Open in Canvas (opens your browser)")
            }
        }
    }

    private func hasSubmission(_ assignment: Assignment) -> Bool {
        (submission ?? assignment.submission)?.isSubmitted == true
    }

    // MARK: Loading

    private func load() async {
        await session.loadGroups()
        guard let client = app.client else { return }
        if session.assignment(assignmentId) == nil {
            do { fetched = try await client.assignment(course: session.id, id: assignmentId) }
            catch { fetchError = error.localizedDescription }
        }
        if let detailed = try? await client.submission(course: session.id, assignment: assignmentId) {
            submission = detailed
        }
    }
}

// MARK: - Grade panel

/// Right-hand column: your score and dates, the class distribution, grader comments and your submitted files.
private struct GradePanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var assignment: Assignment
    var submission: Submission?
    var session: CourseSession

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            score
            if let statistics = assignment.scoreStatistics, statistics.mean != nil || statistics.max != nil {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Class")
                    ScoreRangeBar(statistics: statistics, possible: assignment.pointsPossible, score: submission?.excused == true ? nil : submission?.score)
                }
            }
            if let comments = submission?.submissionComments, !comments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Comments", count: comments.count)
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(comment.authorName ?? "Comment").font(ThubanFont.body(13, weight: .semibold)).foregroundStyle(theme.inkColor)
                                if let date = comment.createdAt {
                                    Text(WorkText.day(date)).font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                                }
                            }
                            Text(comment.comment).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let attachments = submission?.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Your files", count: attachments.count)
                    ForEach(attachments) { file in
                        Button {
                            session.path.append(.file(file.id))
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc").font(.system(size: 13, weight: .semibold))
                                Text(file.displayName).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 8))
                        .accessibilityLabel("Open \(file.displayName)")
                    }
                }
            }
            if let url = submission?.url, submission?.submissionType == "online_url" {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Submitted link")
                    Button(url) { CanvasBrowser.open(url) }
                        .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 8))
                        .lineLimit(1)
                }
            }
        }
    }

    private var score: some View {
        let item = WorkItem(assignment: assignment, courseId: session.id, courseName: session.displayName)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Your grade")
            if submission?.excused == true {
                Text("Excused").font(ThubanFont.display(26)).foregroundStyle(theme.inkColor)
                Text("Does not count toward your grade.").font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
            } else if let score = submission?.score, submission?.isGraded == true {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ScoreText(score: score, possible: assignment.pointsPossible, size: 26)
                    if let percent = WorkText.percent(score: score, possible: assignment.pointsPossible) {
                        Text(percent).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor).monospacedDigit()
                    }
                }
                if let grade = submission?.grade, assignment.gradingType != "points", grade != DueFormatter.points(score) {
                    Text(grade).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                }
            } else {
                Text(pendingText).font(ThubanFont.display(20)).foregroundStyle(theme.inkDimColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let submitted = submission?.submittedAt {
                    detail("Submitted", WorkText.full(submitted) + (submission?.late == true ? " · late" : ""), neg: submission?.late == true)
                }
                if let graded = submission?.gradedAt, submission?.isGraded == true {
                    detail("Graded", WorkText.full(graded))
                }
                if let deducted = submission?.pointsDeducted, deducted > 0 {
                    detail("Late penalty", "−" + DueFormatter.points(deducted) + " pts", neg: true)
                }
                if let attempt = submission?.attempt, attempt > 1 {
                    detail("Attempt", "\(attempt)")
                }
                if submission?.missing == true, item.status == .overdue {
                    detail("Status", "Marked missing", neg: true)
                }
            }
        }
    }

    private var pendingText: String {
        guard let submission else { return "Not graded yet" }
        if submission.workflowState == "pending_review" { return "Awaiting grade" }
        if submission.isSubmitted { return "Submitted · not graded" }
        if assignment.acceptsOnlineSubmission { return "Not submitted yet" }
        return "Not graded yet"
    }

    private func detail(_ label: String, _ value: String, neg: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).frame(width: 84, alignment: .leading)
            Text(value).font(ThubanFont.small).foregroundStyle(neg ? theme.negTextColor : theme.inkColor).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
