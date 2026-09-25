import SwiftUI
import ThubanCanvasCore
import UIKit

struct GradesScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("Grades", back: back) {
                BarTextButton("Reset what-if") { session.whatIf = .none }
                    .opacity(session.whatIf.isEmpty ? 0.45 : 1)
                    .disabled(session.whatIf.isEmpty)
                    .accessibilityLabel("Reset what-if scores")
            } content: {
                GradesContent(session: session)
            }
            .refreshable { await session.loadGroups(force: true) }
        }
    }
}

/// Current grade next to the what-if grade, steppers for ungraded work (stored per course on this device only,
/// computed with the shared `GradeCalculator`), then graded work with class statistics.
struct GradesContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    @State private var showAll = false
    @State private var editing: Assignment?
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let groups = session.groups.value {
                summary(groups)
                tryScores
                graded(groups)
                weights(groups)
            } else if session.groups.isLoading || !session.groups.hasAttempted {
                LoadingCard(text: "Loading grades…")
            } else if let error = session.groups.error {
                Card { EmptyNote(systemName: "wifi.exclamationmark", text: error.localizedDescription, tint: theme.negTextColor) }
            }
        }
        .padding(.top, 10)
        .gutter()
        .task(id: session.id) {
            await session.loadGroups()
            await session.loadGradingStandards()
        }
        .alert("What-if score", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Points", text: $typed).keyboardType(.decimalPad)
            Button("Apply") {
                if let assignment = editing, let value = Double(typed.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0 {
                    set(assignment, value)
                }
                editing = nil
            }
            Button("Clear", role: .destructive) { if let assignment = editing { clear(assignment) }; editing = nil }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            if let assignment = editing { Text("\(assignment.name), out of \(PointsText.short(assignment.pointsPossible)). Stays on this device.") }
        }
    }

    // MARK: Summary

    private var weighted: Bool { session.course.applyAssignmentGroupWeights ?? false }

    private var currentScore: Double? {
        session.canvasScore ?? GradeCalculator.compute(groups: session.groups.value ?? [], weighted: weighted).percent
    }

    private var currentLetter: String? {
        if let letter = session.canvasLetter, session.preferences.customCutoffs == nil { return letter }
        return currentScore.map { session.gradingScheme.letter(for: $0) }
    }

    private func summary(_ groups: [AssignmentGroup]) -> some View {
        let whatIf = session.whatIf.isEmpty ? currentScore : GradeCalculator.compute(groups: groups, weighted: weighted, whatIf: session.whatIf).percent
        let whatIfLetter = session.whatIf.isEmpty ? currentLetter : whatIf.map { session.gradingScheme.letter(for: $0) }
        let delta = (whatIf ?? 0) - (currentScore ?? 0)
        return Card {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current").tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.inkDimColor)
                    scoreLine(currentScore, letter: currentLetter)
                    Text("Graded work only").tFont(.footnote).foregroundStyle(theme.inkDimColor)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Rectangle().fill(theme.lineColor).frame(width: 1).padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What-if").tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.brassInkColor)
                    scoreLine(whatIf, letter: whatIfLetter)
                    Text(session.whatIf.isEmpty ? "Try a score below" : (delta >= 0 ? "+" : "−") + String(format: "%.1f", abs(delta)) + " vs current")
                        .tFont(.text(13, .semibold))
                        .foregroundStyle(session.whatIf.isEmpty ? theme.inkDimColor : (delta >= 0 ? (theme.isDark ? theme.posColor : theme.posTextColor) : theme.negTextColor))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(theme.accentTintColor)
                .accessibilityElement(children: .combine)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scoreLine(_ score: Double?, letter: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(score.map { DueFormatter.percent($0) } ?? "—").tFont(.display(30)).foregroundStyle(theme.inkColor).monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1)
            if let letter { LetterChip(letter: letter) }
        }
    }

    // MARK: What-if steppers

    private var ungraded: [Assignment] {
        session.countedAssignments
            .filter { $0.submission?.isGraded != true && $0.submission?.excused != true && ($0.pointsPossible ?? 0) > 0 }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    @ViewBuilder
    private var tryScores: some View {
        let list = ungraded
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Try a score") {
                    Text(UIDevice.current.userInterfaceIdiom == .pad ? "Stays on this iPad" : "Stays on this iPhone").tFont(.footnote).foregroundStyle(theme.inkFaintColor)
                }
                Card {
                    let shown = showAll ? list : Array(list.prefix(4))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, assignment in
                        if index > 0 { RowDivider() }
                        stepperRow(assignment)
                    }
                    if list.count > 4 {
                        RowDivider()
                        Button(showAll ? "Show fewer" : "Show all \(list.count)") { showAll.toggle() }
                            .tFont(.text(15, .semibold)).foregroundStyle(theme.brassInkColor)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
    }

    private func stepperRow(_ assignment: Assignment) -> some View {
        let value = override(assignment)
        let possible = assignment.pointsPossible ?? 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(assignment.name).tFont(.text(16, .semibold)).foregroundStyle(theme.inkColor).lineLimit(2)
                Text([session.groupLabel(of: assignment)?.replacingOccurrences(of: " · ", with: " "), assignment.dueAt.map { DueFormatter.compactDay($0) }].compactMap { $0 }.joined(separator: " · "))
                    .tFont(.footnote).foregroundStyle(theme.inkDimColor).lineLimit(2)
            }
            Spacer(minLength: 6)
            stepButton("minus", label: "Lower \(assignment.name) what-if score") { nudge(assignment, by: -1) }
            Button { typed = value.map { PointsText.short($0) } ?? ""; editing = assignment } label: {
                HStack(spacing: 0) {
                    Text(value.map { PointsText.short($0) } ?? "—").foregroundStyle(value == nil ? theme.inkFaintColor : theme.inkColor)
                    Text("/\(PointsText.short(possible))").foregroundStyle(theme.inkFaintColor).fontWeight(.regular)
                }
                .tFont(.mono(15, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 64, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What-if score for \(assignment.name)")
            .accessibilityValue(value.map { "\(PointsText.short($0)) out of \(PointsText.short(possible))" } ?? "not set")
            .accessibilityHint("Type a score")
            stepButton("plus", label: "Raise \(assignment.name) what-if score") { nudge(assignment, by: 1) }
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 8)
        .frame(minHeight: 64)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.inkColor)
                .frame(width: 36, height: 36)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
        .accessibilityLabel(label)
    }

    private func override(_ assignment: Assignment) -> Double? {
        if case .score(let value)? = session.whatIf.scores[assignment.id] { return value }
        return nil
    }

    private func step(_ possible: Double) -> Double {
        possible >= 50 ? 5 : (possible >= 5 ? 1 : 0.5)
    }

    private func nudge(_ assignment: Assignment, by direction: Double) {
        let possible = assignment.pointsPossible ?? 0
        let unit = step(possible)
        let start: Double
        if let value = override(assignment) {
            start = value + direction * unit
        } else {
            let base = (currentScore ?? 90) / 100 * possible
            start = (base / unit).rounded() * unit
        }
        set(assignment, min(max(0, start), possible * 1.5))
    }

    private func set(_ assignment: Assignment, _ value: Double) {
        var whatIf = session.whatIf
        whatIf.scores[assignment.id] = .score(value)
        session.whatIf = whatIf
    }

    private func clear(_ assignment: Assignment) {
        var whatIf = session.whatIf
        whatIf.scores[assignment.id] = nil
        session.whatIf = whatIf
    }

    // MARK: Graded

    @ViewBuilder
    private func graded(_ groups: [AssignmentGroup]) -> some View {
        let dropped = Set(GradeCalculator.compute(groups: groups, weighted: weighted).groups.flatMap(\.dropped))
        let list = session.countedAssignments
            .filter { $0.submission?.isGraded == true || $0.submission?.excused == true }
            .filter(\.showsInGradebook)
            .sorted { ($0.submission?.gradedAt ?? $0.dueAt ?? .distantPast) > ($1.submission?.gradedAt ?? $1.dueAt ?? .distantPast) }
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Graded")
            if list.isEmpty {
                Card { EmptyNote(systemName: "chart.bar", text: "Nothing has been graded yet.") }
            } else {
                Card {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, assignment in
                        if index > 0 { Rectangle().fill(theme.lineColor).frame(height: 1) }
                        Button { app.push(.assignment(course: session.id, id: assignment.id)) } label: {
                            gradedRow(assignment, dropped: dropped.contains(assignment.id))
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
            }
        }
    }

    private func gradedRow(_ assignment: Assignment, dropped: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(assignment.name).tFont(.text(16, assignment.scoreStatistics != nil ? .semibold : .regular))
                    .foregroundStyle(dropped ? theme.inkDimColor : theme.inkColor).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                if session.isNewlyGraded(assignment) { ChipView("New", kind: .pos) }
                if dropped { ChipView("Dropped", kind: .neutral) }
                if assignment.submission?.excused == true {
                    ChipView("Excused", kind: .neutral)
                } else {
                    ScoreLabel(score: assignment.submission?.score, possible: assignment.pointsPossible, dim: dropped)
                }
            }
            if let stats = assignment.scoreStatistics {
                ScoreDistribution(stats: stats, score: assignment.submission?.score, possible: assignment.pointsPossible)
            }
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 12)
        .frame(minHeight: IOSMetrics.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Weights

    @ViewBuilder
    private func weights(_ groups: [AssignmentGroup]) -> some View {
        let result = GradeCalculator.compute(groups: groups, weighted: weighted, whatIf: session.whatIf)
        let shown = result.groups.filter { $0.possible > 0 || ($0.weight ?? 0) > 0 }
        if shown.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(weighted ? "Weighted groups" : "Groups")
                Card {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { RowDivider() }
                        HStack {
                            Text(group.name).tFont(.body).foregroundStyle(theme.inkColor)
                            if weighted, let weight = group.weight { Text("\(PointsText.short(weight))%").tFont(.footnote).foregroundStyle(theme.inkDimColor) }
                            Spacer()
                            Text(group.percent.map { DueFormatter.percent($0) } ?? "—").tFont(.mono(15, .semibold)).foregroundStyle(theme.inkColor)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: IOSMetrics.rowHeight)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
