import SwiftUI
import ThubanCanvasCore

/// The course grade: a summary card (score, letter, scheme, next cutoff, Canvas's own number), the group
/// breakdown, and every assignment by group with a what-if column. What-if scores persist per course and
/// recompute the grade live through `CourseSession.computedGrade`.
struct GradesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    @AppStorage("grades.showClassAverages") private var showAverages = false

    var body: some View {
        ResourceStateView(resource: session.groups, emptyTitle: "No grades yet",
                          emptyMessage: "Nothing has been published for this course.", isEmpty: { groups in
            groups.allSatisfy { ($0.assignments ?? []).isEmpty }
        }, retry: { await session.loadGroups(force: true) }) { groups in
            let grade = session.computedGrade
            SectionPage {
                GradeSummaryCard(session: session, grade: grade, showAverages: $showAverages)
                if let grade, grade.groups.filter({ $0.possible > 0 || ($0.weight ?? 0) > 0 }).count > 1 {
                    GroupBreakdown(grade: grade)
                }
                ForEach(orderedGroups(groups), id: \.id) { group in
                    GroupTable(session: session, group: group, result: grade?.groups.first { $0.id == group.id }, showAverages: showAverages)
                }
            }
        }
        .task(id: session.id) {
            await session.loadGroups()
            await session.loadGradingStandards()
        }
    }

    private func orderedGroups(_ groups: [AssignmentGroup]) -> [AssignmentGroup] {
        groups
            .filter { ($0.assignments ?? []).contains { $0.showsInGradebook } }
            .sorted { ($0.position ?? 0, $0.id) < ($1.position ?? 0, $1.id) }
    }
}

// MARK: - Summary

/// Big number + letter, the scheme in use, the next cutoff, Canvas's number when it differs, and the what-if controls.
private struct GradeSummaryCard: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var grade: CourseGrade?
    @Binding var showAverages: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Current grade").font(ThubanFont.micro).kerning(0.5).textCase(.uppercase).foregroundStyle(theme.inkDimColor)
                    if !session.whatIf.isEmpty { Chip("What-if", kind: .warn) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(session.displayScore.map { DueFormatter.percent($0) } ?? "—")
                        .font(ThubanFont.display(44))
                        .foregroundStyle(session.displayScore == nil ? theme.inkFaintColor : theme.inkColor)
                        .monospacedDigit()
                    if let letter = session.displayLetter { Chip.letter(letter) }
                }
                Text(schemeLine).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)

            Rectangle().fill(theme.lineColor).frame(width: ThubanMetrics.hairline).frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                if let next = nextCutoffLine { fact("arrow.up.right", next) }
                if let canvas = canvasLine { fact("info.circle", canvas) }
                if let grade { fact(grade.weighted ? "scalemass" : "sum", basisLine(grade)) }
            }
            .frame(maxWidth: 440, alignment: .leading)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                toggleRow("Count ungraded as zero", isOn: Binding(
                    get: { session.whatIf.ungradedAsZero },
                    set: { value in var whatIf = session.whatIf; whatIf.ungradedAsZero = value; session.whatIf = whatIf }
                ))
                toggleRow("Show class averages", isOn: $showAverages)
                if !session.whatIf.isEmpty {
                    Button {
                        session.whatIf = .none
                    } label: {
                        HStack(spacing: 6) { Glyph(.reset, size: 13); Text("Reset what-if") }
                    }
                    .buttonStyle(GhostButtonStyle(height: 30, tinted: true))
                    .accessibilityLabel("Reset what-if scores")
                }
            }
        }
        .thubanPanel(padding: 20)
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.brassInkColor).frame(width: 16)
            Text(text).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkColor).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
            ThubanToggle(isOn: isOn, label: label).controlSize(.small)
        }
    }

    // MARK: Copy

    private var schemeLine: String {
        let scheme = session.gradingScheme
        let source: String
        if session.preferences.customCutoffs != nil, session.hasCourseScheme { source = "your cutoffs" }
        else if session.hasCourseScheme { source = "course scheme" }
        else { source = "app scale — the course’s own scheme isn’t visible to students" }
        return "\(scheme.title) · \(scheme.summary) · \(source)"
    }

    private var nextCutoffLine: String? {
        guard let score = session.displayScore else { return nil }
        if !session.hasCourseScheme, session.canvasLetter != nil, session.displayLetter == session.canvasLetter {
            return "Canvas’s letter comes from a scheme the app can’t read; cutoffs aren’t shown."
        }
        let scheme = session.gradingScheme
        guard let cutoff = scheme.nextCutoff(above: score) else {
            return "Top of the scale."
        }
        let gap = cutoff.minimum - score
        let gapText = String(format: "%.1f", gap)
        if let grade, !grade.weighted, !session.whatIf.ungradedAsZero, let next = nextUngraded, let possible = next.pointsPossible, possible > 0 {
            let name = next.name.count > 40 ? String(next.name.prefix(38)).trimmingCharacters(in: .whitespaces) + "…" : next.name
            if let needed = GradeCalculator.pointsNeeded(currentEarned: grade.earned, currentPossible: grade.possible, upcoming: possible, target: cutoff.minimum) {
                return "Score \(DueFormatter.points((needed * 100).rounded(.up) / 100)) / \(DueFormatter.points(possible)) on \(name) to reach \(article(cutoff.letter))."
            }
            return "\(gapText) points to \(article(cutoff.letter)) — more than \(name) alone can cover."
        }
        return "\(gapText) points to \(article(cutoff.letter))."
    }

    /// The soonest-due assignment that counts, has points, and has no grade yet (and no what-if score).
    private var nextUngraded: Assignment? {
        session.assignments
            .filter { $0.showsInGradebook && $0.countsTowardGrade && session.whatIf.scores[$0.id] == nil }
            .filter { $0.submission?.isGraded != true && $0.submission?.excused != true }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .first
    }

    private var canvasLine: String? {
        guard let canvas = session.canvasScore else {
            return session.course.hideFinalGrades == true ? "Canvas hides the total for this course; this number is the app’s own count." : nil
        }
        if !session.whatIf.isEmpty {
            return "Without what-if, Canvas shows \(DueFormatter.percent(canvas))."
        }
        guard let computed = grade?.percent, abs(computed - canvas) >= 0.05 else { return nil }
        return "Canvas shows \(DueFormatter.percent(canvas)); recounting the visible assignments gives \(DueFormatter.percent(computed)) — hidden or muted grades and drop rules explain the gap."
    }

    private func basisLine(_ grade: CourseGrade) -> String {
        if grade.weighted { return "Weighted by assignment group." }
        return "Points-based · \(DueFormatter.points(grade.earned)) of \(DueFormatter.points(grade.possible)) so far."
    }

    private func article(_ letter: String) -> String {
        let vowel = ["A", "F"].contains(String(letter.prefix(1)).uppercased())
        return (vowel ? "an " : "a ") + letter
    }

    private var accessibilitySummary: String {
        var parts = ["Current grade " + (session.displayScore.map { DueFormatter.percent($0) } ?? "unknown")]
        if let letter = session.displayLetter { parts.append("letter \(letter)") }
        if !session.whatIf.isEmpty { parts.append("what-if active") }
        parts.append(schemeLine)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Group breakdown

/// Name · weight · earned / possible · percent · dropped, one row per assignment group.
private struct GroupBreakdown: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var grade: CourseGrade

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Groups")
            VStack(spacing: 0) {
                row("Group", grade.weighted ? "Weight" : "", "Earned / possible", "Percent", "Dropped", header: true)
                ForEach(grade.groups.filter { $0.possible > 0 || ($0.weight ?? 0) > 0 }) { group in
                    Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline)
                    row(group.name,
                        grade.weighted ? (WorkText.weight(group.weight) ?? "—") : "",
                        group.possible > 0 ? "\(DueFormatter.points(group.earned)) / \(DueFormatter.points(group.possible))" : "—",
                        group.percent.map { DueFormatter.percent($0) } ?? "—",
                        group.dropped.isEmpty ? "" : String(group.dropped.count),
                        dim: group.possible == 0)
                }
            }
            .thubanPanel(padding: 0)
        }
    }

    private func row(_ name: String, _ weight: String, _ earned: String, _ percent: String, _ dropped: String, header: Bool = false, dim: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(header ? name.uppercased() : name)
                .font(header ? ThubanFont.micro : ThubanFont.scaled(13.5, scale: textScale, weight: .semibold))
                .kerning(header ? 0.5 : 0)
                .foregroundStyle(header ? theme.inkDimColor : (dim ? theme.inkFaintColor : theme.inkColor))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if grade.weighted { cell(weight, header: header, dim: dim).frame(width: 70, alignment: .trailing) }
            cell(earned, header: header, dim: dim).frame(width: 140, alignment: .trailing)
            cell(percent, header: header, dim: dim).frame(width: 80, alignment: .trailing)
            cell(dropped, header: header, dim: dim).frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: header ? 32 : 36)
        .accessibilityElement(children: .combine)
    }

    private func cell(_ text: String, header: Bool, dim: Bool) -> some View {
        Text(header ? text.uppercased() : text)
            .font(header ? ThubanFont.micro : ThubanFont.scaled(13.5, scale: textScale))
            .kerning(header ? 0.5 : 0)
            .monospacedDigit()
            .foregroundStyle(header ? theme.inkDimColor : (dim ? theme.inkFaintColor : theme.inkColor))
            .lineLimit(1)
    }
}

// MARK: - Assignment tables

/// One assignment group's table with the what-if column.
private struct GroupTable: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var group: AssignmentGroup
    var result: CourseGrade.GroupResult?
    var showAverages: Bool

    private var assignments: [Assignment] {
        (group.assignments ?? [])
            .filter { $0.showsInGradebook }
            .sorted { ($0.dueAt ?? .distantFuture, $0.position ?? 0) < ($1.dueAt ?? .distantFuture, $1.position ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(group.name, count: assignments.count) {
                HStack(spacing: 8) {
                    if let result, result.possible > 0 {
                        Text("\(DueFormatter.points(result.earned)) / \(DueFormatter.points(result.possible)) · \(result.percent.map { DueFormatter.percent($0) } ?? "—")")
                            .font(ThubanFont.small).foregroundStyle(theme.inkDimColor).monospacedDigit()
                    }
                    if let weight = WorkText.weight(group.groupWeight), (group.groupWeight ?? 0) > 0 {
                        Chip(weight, kind: .neutral).accessibilityLabel("Weight \(weight)")
                    }
                }
            }
            VStack(spacing: 0) {
                GradeTableHeader(showAverages: showAverages)
                ForEach(assignments) { assignment in
                    Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline)
                    GradeRow(session: session, assignment: assignment, dropped: result?.dropped.contains(assignment.id) ?? false, showAverages: showAverages)
                }
            }
            .thubanPanel(padding: 0)
        }
    }
}

/// Column widths shared by the header and rows.
private enum GradeColumns {
    static let due: CGFloat = 92
    static let score: CGFloat = 104
    static let percent: CGFloat = 62
    static let average: CGFloat = 64
    static let status: CGFloat = 118
    static let whatIf: CGFloat = 96
    static let spacing: CGFloat = 12
}

private struct GradeTableHeader: View {
    @Environment(\.thubanTheme) private var theme
    var showAverages: Bool

    var body: some View {
        HStack(spacing: GradeColumns.spacing) {
            label("Assignment").frame(maxWidth: .infinity, alignment: .leading)
            label("Due").frame(width: GradeColumns.due, alignment: .leading)
            label("Score").frame(width: GradeColumns.score, alignment: .trailing)
            label("%").frame(width: GradeColumns.percent, alignment: .trailing)
            if showAverages { label("Class").frame(width: GradeColumns.average, alignment: .trailing) }
            label("Status").frame(width: GradeColumns.status, alignment: .leading)
            label("What-if").frame(width: GradeColumns.whatIf, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor).lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One assignment: name (opens the detail), due, score / possible, percent, class mean, status, what-if field.
private struct GradeRow: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    @Bindable var session: CourseSession
    var assignment: Assignment
    var dropped: Bool
    var showAverages: Bool
    @State private var hovering = false

    private var submission: Submission? { assignment.submission }
    private var override: WhatIfScore? { session.whatIf.scores[assignment.id] }
    private var excused: Bool { submission?.excused == true }
    private var graded: Bool { submission?.isGraded == true }
    private var item: WorkItem { WorkItem(assignment: assignment, courseId: session.id, courseName: session.displayName) }

    var body: some View {
        HStack(spacing: GradeColumns.spacing) {
            Button {
                session.path.append(.assignment(assignment.id))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: assignment.kind.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.inkFaintColor)
                        .frame(width: 16)
                    Text(assignment.name)
                        .font(ThubanFont.scaled(13.5, scale: textScale, weight: .semibold))
                        .foregroundStyle(hovering ? theme.brassInkColor : theme.inkColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(assignment.name)
            .accessibilityLabel("Open \(assignment.name)")
            .frame(maxWidth: .infinity, alignment: .leading)

            // The read-only cells are one VoiceOver element that names the assignment, so the numbers
            // never read as unrelated strings; the name button and what-if field stay separately focusable.
            Group {
            Text(assignment.dueAt.map { WorkText.day($0) } ?? "—")
                .font(ThubanFont.scaled(13, scale: textScale))
                .foregroundStyle(item.status == .overdue ? theme.negTextColor : theme.inkDimColor)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: GradeColumns.due, alignment: .leading)

            scoreCell
                .frame(width: GradeColumns.score, alignment: .trailing)

            Text(percentText)
                .font(ThubanFont.scaled(13, scale: textScale))
                .foregroundStyle(percentText == "—" ? theme.inkFaintColor : theme.inkDimColor)
                .monospacedDigit()
                .frame(width: GradeColumns.percent, alignment: .trailing)

            if showAverages {
                Text(ScoreRangeBar.number(assignment.scoreStatistics?.mean))
                    .font(ThubanFont.scaled(13, scale: textScale))
                    .foregroundStyle(assignment.scoreStatistics?.mean == nil ? theme.inkFaintColor : theme.inkDimColor)
                    .monospacedDigit()
                    .frame(width: GradeColumns.average, alignment: .trailing)
                    .help("Class mean")
            }

            HStack(spacing: 4) {
                if let status = statusText { Chip(status.text, kind: status.kind) }
            }
            .frame(width: GradeColumns.status, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowSummary)

            Group {
                if assignment.countsTowardGrade, !excused {
                    WhatIfField(assignment: assignment, override: override) { value in
                        var whatIf = session.whatIf
                        if let value { whatIf.scores[assignment.id] = value } else { whatIf.scores.removeValue(forKey: assignment.id) }
                        session.whatIf = whatIf
                    }
                } else {
                    Text(excused ? "EX" : "—").font(ThubanFont.mono(12.5 * textScale)).foregroundStyle(theme.inkFaintColor).frame(width: 66)
                        .accessibilityLabel(excused ? "What-if not applicable, excused" : "What-if not applicable")
                }
            }
            .frame(width: GradeColumns.whatIf, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40 * textScale)
        .opacity(dropped ? 0.6 : 1)
        .background(override != nil ? theme.accentTintColor.opacity(0.35) : .clear)
    }

    @ViewBuilder
    private var scoreCell: some View {
        if excused {
            Text("EX").font(ThubanFont.body(14, weight: .medium)).foregroundStyle(theme.inkDimColor)
        } else if graded, let score = submission?.score {
            HStack(spacing: 2) {
                ScoreText(score: score, possible: assignment.pointsPossible)
                if let grade = submission?.grade, assignment.gradingType == "letter_grade" || assignment.gradingType == "pass_fail" || assignment.gradingType == "gpa_scale" {
                    Text(grade).font(ThubanFont.scaled(13, scale: textScale)).foregroundStyle(theme.brassInkColor).padding(.leading, 4)
                }
            }
        } else {
            ScoreText(score: nil, possible: assignment.pointsPossible)
        }
    }

    private var percentText: String {
        guard !excused, graded, let score = submission?.score else { return "—" }
        return WorkText.percent(score: score, possible: assignment.pointsPossible) ?? "—"
    }

    /// The status chip's text and kind (nil → no chip). Shared by the chip and the spoken row summary.
    private var statusText: (text: String, kind: ChipKind)? {
        if dropped { return ("Dropped", .neutral) }
        if excused { return ("Excused", .neutral) }
        if let chip = Chip.status(item) { return (chip.text, chip.kind) }
        if submission?.workflowState == "pending_review" { return ("Awaiting grade", .signal) }
        if assignment.lockedForUser == true { return ("Locked", .neutral) }
        return nil
    }

    private var rowSummary: String {
        var parts: [String] = [assignment.name]
        parts.append(assignment.dueAt.map { "due \(WorkText.day($0))" } ?? "no due date")
        if excused { parts.append("excused") }
        else if graded, let score = submission?.score {
            parts.append("\(DueFormatter.points(score)) of \(DueFormatter.points(assignment.pointsPossible ?? 0))")
            if percentText != "—" { parts.append(percentText) }
        } else { parts.append("not graded") }
        if showAverages, let mean = assignment.scoreStatistics?.mean { parts.append("class mean \(ScoreRangeBar.number(mean))") }
        if let status = statusText, status.text.lowercased() != "excused" { parts.append(status.text.lowercased()) }
        return parts.joined(separator: ", ")
    }
}
