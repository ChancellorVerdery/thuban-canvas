import SwiftUI
import ThubanCanvasCore

/// A classic quiz: title, dates, points, question count, time limit, attempts and the description, with one
/// action — take it on the Canvas website (quizzes are web-only). When the Quizzes API is unavailable for the
/// course, the matching assignment's detail is shown instead.
struct QuizDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var quizId: CanvasID

    private var quiz: Quiz? { session.quizzes.value?.first { $0.id == quizId } }
    private var fallbackAssignment: Assignment? { session.assignments.first { $0.quizId == quizId } }

    var body: some View {
        Group {
            if let quiz {
                content(quiz)
            } else if session.quizzes.isLoading, !session.quizzes.hasValue {
                LoadingView()
            } else if let assignment = fallbackAssignment {
                AssignmentDetailView(session: session, assignmentId: assignment.id)
            } else if session.quizzes.unavailable {
                EmptyState(title: "Quiz not available", message: "Canvas does not expose quizzes for this course.")
            } else if let error = session.quizzes.error {
                EmptyState(title: "Couldn’t load quiz", message: error.localizedDescription) {
                    Button("Try again") { Task { await session.loadQuizzes(force: true) } }.buttonStyle(.thubanSecondary)
                }
            } else if session.quizzes.hasAttempted {
                EmptyState(title: "Quiz not found", message: "It may have been unpublished or removed.")
            } else {
                LoadingView()
            }
        }
        .task(id: quizId) {
            await session.loadQuizzes()
            if session.quizzes.value == nil { await session.loadGroups() }
        }
    }

    private func content(_ quiz: Quiz) -> some View {
        let assignment = quiz.assignmentId.flatMap { session.assignment($0) }
        let submission = assignment?.submission
        return VStack(spacing: 0) {
            DetailHeader(eyebrow: eyebrow(quiz), title: quiz.title, titleLineLimit: 3) {
                HStack(spacing: 6) {
                    if let assignment, let chip = Chip.status(WorkItem(assignment: assignment, courseId: session.id, courseName: session.displayName)) { chip }
                    if quiz.published == false { Chip("Unpublished", kind: .warn) }
                    if quiz.lockedForUser == true { Chip("Locked", kind: .neutral) }
                    if let score = submission?.score, submission?.isGraded == true {
                        Chip("Score " + DueFormatter.points(score) + " / " + DueFormatter.points(quiz.pointsPossible ?? assignment?.pointsPossible), kind: .pos)
                    }
                }
            } actions: {
                HStack(spacing: 8) {
                    Button(quiz.lockedForUser == true ? "Open in Canvas" : "Take quiz in Canvas") { CanvasBrowser.open(quiz.htmlUrl) }
                        .buttonStyle(.thubanPrimary)
                        .disabled(quiz.htmlUrl == nil)
                        .accessibilityLabel(quiz.lockedForUser == true ? "Open in Canvas (opens your browser)" : "Take quiz in Canvas (opens your browser)")
                    if let assignment {
                        Button("Assignment details") { session.path.append(.assignment(assignment.id)) }
                            .buttonStyle(.thubanGhostTinted)
                    }
                }
            } below: {
                HStack(alignment: .top, spacing: 28) {
                    MetaField(label: "Due", value: quiz.dueAt.map { WorkText.full($0) + " · " + DueFormatter.countdown($0) } ?? "No due date",
                              tone: quiz.dueAt.map { $0 < Date() && submission?.isSubmitted != true } == true ? .neg : .normal)
                    MetaField(label: "Points", value: DueFormatter.points(quiz.pointsPossible), tone: quiz.pointsPossible == nil ? .dim : .normal)
                    MetaField(label: "Questions", value: quiz.questionCount.map(String.init) ?? "—", tone: quiz.questionCount == nil ? .dim : .normal)
                    MetaField(label: "Time limit", value: quiz.timeLimit.map { "\($0) min" } ?? "None")
                    MetaField(label: "Attempts", value: attemptsText(quiz))
                    if let unlock = quiz.unlockAt, unlock > Date() { MetaField(label: "Opens", value: WorkText.full(unlock)) }
                    if let lock = quiz.lockAt { MetaField(label: lock > Date() ? "Closes" : "Closed", value: WorkText.full(lock), tone: lock > Date() ? .normal : .dim) }
                }
                if quiz.lockedForUser == true {
                    InlineNote(symbol: "lock", text: "This quiz is locked" + (quiz.lockAt.map { $0 < Date() ? " — it closed \(WorkText.full($0))." : "." } ?? "."))
                } else {
                    InlineNote(symbol: "arrow.up.right.square", text: "Quizzes run on the Canvas website; your score shows here once it is graded.")
                }
            }
            if let html = quiz.description, !CanvasHTML.plainText(html, limit: 4).isEmpty || html.contains("<img") {
                CanvasHTMLView(html: html).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(title: "No description", message: "The instructor did not add instructions for this quiz.")
            }
        }
    }

    private func eyebrow(_ quiz: Quiz) -> String {
        var parts = ["QUIZ"]
        switch quiz.quizType {
        case "practice_quiz": parts.append("PRACTICE")
        case "graded_survey": parts.append("GRADED SURVEY")
        case "survey": parts.append("SURVEY")
        default: break
        }
        return parts.joined(separator: "  ·  ")
    }

    private func attemptsText(_ quiz: Quiz) -> String {
        guard let allowed = quiz.allowedAttempts else { return "1" }
        return allowed < 0 ? "Unlimited" : String(allowed)
    }
}
