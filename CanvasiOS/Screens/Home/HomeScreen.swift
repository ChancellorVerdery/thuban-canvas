import SwiftUI
import ThubanCanvasCore

/// Home: refresh status + Settings gear, GPA, the course grade strip, Overdue (swipe to dismiss, kept on this
/// device only) and the next 7 days.
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        RootScreen("Home", eyebrow: eyebrow) {
            RefreshStatusPill()
        } trailing: {
            IconButton(systemName: "arrow.clockwise", label: "Refresh everything") {
                Task { await app.refreshAll() }
            }
            IconButton(systemName: "gearshape", label: "Settings") { app.showingSettings = true }
        } content: {
            if app.orderedSessions.isEmpty {
                noCourses.padding(.top, 24)
            } else {
                let items = app.allWorkItems
                VStack(alignment: .leading, spacing: IOSMetrics.sectionGap) {
                    GPASummaryCard()
                    GradeStrip()
                    OverdueSection(items: items)
                    NextSevenDays(items: items)
                }
                .padding(.top, 16)
            }
        }
        .refreshable { await app.refreshAll() }
        .task(id: app.courses.map(\.id)) {
            guard !app.courses.isEmpty else { return }
            await app.loadHomeResources()
        }
    }

    private var eyebrow: String {
        let date = Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        if let term = app.termName { return "\(date) · \(term)" }
        return date
    }

    @ViewBuilder
    private var noCourses: some View {
        if app.isLoadingCourses {
            LoadingCard(text: "Loading your courses…").gutter()
        } else if let error = app.coursesError {
            ScreenMessage(systemName: "wifi.exclamationmark", title: "Couldn’t load your courses", message: error.localizedDescription) {
                Task { await app.refreshAll() }
            }
        } else {
            ScreenMessage(systemName: "star", title: "No starred courses", message: "Star courses in Canvas and they appear here with the same layout.")
        }
    }
}

/// "Refreshed 4 min ago" with a signal dot; "Refreshing…" while a refresh runs; a loss dot when offline.
struct RefreshStatusPill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(text(now: context.date)).tFont(.text(13, .semibold)).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        if app.authenticationFailed || app.coursesError != nil { return theme.negColor }
        return theme.signalColor
    }

    private func text(now: Date) -> String {
        if app.isRefreshing { return "Refreshing…" }
        if app.authenticationFailed { return "Token rejected" }
        if app.coursesError != nil { return "Offline · saved data" }
        return DueFormatter.refreshed(app.lastRefresh, now: now)
    }
}

/// Term GPA (estimated from current letters) and cumulative with the change against past semesters alone.
struct GPASummaryCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let result = app.gpa
        let counted = app.gpaCourses.filter { $0.included && $0.points != nil && $0.credits > 0 }.count
        let past = app.settings.pastSemesters.filter { $0.gpa != nil && $0.credits > 0 }
        Card {
            HStack(alignment: .top, spacing: 0) {
                half(label: "Term GPA", value: result.term, note: "est.", noteColor: theme.inkFaintColor,
                     detail: "\(PointsText.short(result.termCredits)) credits · \(counted) class\(counted == 1 ? "" : "es")")
                Rectangle().fill(theme.lineColor).frame(width: 1).padding(.vertical, 12)
                Button { app.push(.pastSemesters) } label: {
                    if past.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cumulative").tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.inkDimColor)
                            Text("Add past semesters").tFont(.text(15, .semibold)).foregroundStyle(theme.brassInkColor)
                            Text("for a cumulative GPA").tFont(.footnote).foregroundStyle(theme.inkDimColor)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        half(label: "Cumulative", value: result.cumulative, note: delta(result.cumulative), noteColor: deltaColor(result.cumulative),
                             detail: "\(PointsText.short(result.cumulativeCredits)) credits · \(past.count + 1) terms")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens past semesters")
            }
        }
        .gutter()
    }

    private func half(label: String, value: Double?, note: String?, noteColor: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.inkDimColor)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GPACalculator.format(value)).tFont(.display(30)).foregroundStyle(value == nil ? theme.inkFaintColor : theme.inkColor).monospacedDigit()
                if let note { Text(note).tFont(.text(13, .semibold)).foregroundStyle(noteColor) }
            }
            Text(detail).tFont(.footnote).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func delta(_ cumulative: Double?) -> String? {
        guard let cumulative, let past = app.pastCumulative else { return nil }
        let change = (cumulative * 100).rounded() / 100 - (past * 100).rounded() / 100
        if abs(change) < 0.005 { return "±0.00" }
        return (change > 0 ? "+" : "−") + String(format: "%.2f", abs(change))
    }

    private func deltaColor(_ cumulative: Double?) -> Color {
        guard let cumulative, let past = app.pastCumulative else { return theme.inkDimColor }
        return cumulative >= past ? (theme.isDark ? theme.posColor : theme.posTextColor) : theme.negTextColor
    }
}

/// One small card per course: dot + code, score and letter. Taps open the course's grades.
struct GradeStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Grades") {
                LinkButton("All courses") { app.show(.courses) }
            }
            .gutter()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(app.orderedSessions) { session in
                        Button { app.push(.grades(session.id)) } label: { card(session) }
                            .buttonStyle(PressFadeStyle())
                    }
                }
                .padding(.horizontal, IOSMetrics.gutter)
            }
        }
    }

    private func card(_ session: CourseSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CourseDot(color: app.tint(for: session.id))
                Text(session.shortTitle).tFont(.mono(12, .semibold)).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(session.displayScore.map { String(format: "%.1f", $0) } ?? "—")
                    .tFont(.display(22)).foregroundStyle(session.displayScore == nil ? theme.inkFaintColor : theme.inkColor).monospacedDigit()
                Spacer(minLength: 4)
                if let letter = session.displayLetter { LetterChip(letter: letter) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 116, alignment: .leading)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.shortTitle), \(session.displayScore.map { String(format: "%.1f percent", $0) } ?? "no score")\(session.displayLetter.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens grades")
    }
}

/// Past due with nothing handed in. Swiping left dismisses an item from this list on this device only.
struct OverdueSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var items: [WorkItem]

    var body: some View {
        let dismissed = app.settings.dismissedOverdue
        let all = items.filter { $0.status == .overdue }
        let visible = WorkItemBuilder.overdue(items, dismissed: dismissed)
        let hidden = all.filter { dismissed.contains($0.dismissKey) }
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Overdue") {
                if !visible.isEmpty { Text("Swipe left to dismiss").tFont(.footnote).foregroundStyle(theme.inkFaintColor) }
            }
            VStack(spacing: 8) {
                if visible.isEmpty {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.posTextColor)
                            Text("Nothing overdue.").tFont(.secondary).foregroundStyle(theme.inkDimColor)
                            Spacer(minLength: 4)
                            if !hidden.isEmpty {
                                Button("Show dismissed (\(hidden.count))") { app.restoreAllOverdue(hidden.map(\.dismissKey)) }
                                    .tFont(.text(15, .semibold))
                                    .foregroundStyle(theme.brassInkColor)
                                    .frame(minHeight: 44)
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                        .frame(minHeight: 66)
                    }
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        SwipeToDismissRow(startOpen: index == 0 && SmokeHarness.opensFirstSwipe, onDismiss: { app.dismissOverdue(item) }) {
                            Button { openItem(item) } label: { row(item) }.buttonStyle(RowPressStyle())
                        }
                    }
                }
            }
        }
        .gutter()
    }

    private func row(_ item: WorkItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(theme.negColor).frame(width: 4).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).tFont(.bodyStrong).foregroundStyle(theme.inkColor).lineLimit(1)
                HStack(spacing: 0) {
                    Text(app.shortName(for: item.courseId, fallback: item.courseName)).tFont(.mono(13))
                    Text(" · ")
                    if let due = item.dueAt { Text(DueFormatter.lateness(due)).fontWeight(.semibold).foregroundStyle(theme.negTextColor) }
                }
                .tFont(.footnote)
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let points = item.pointsPossible { Text("\(PointsText.short(points)) pts").tFont(.mono(13)).foregroundStyle(theme.inkDimColor) }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(minHeight: 66)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func openItem(_ item: WorkItem) {
        if let course = item.courseId, let id = item.assignmentId { app.push(.assignment(course: course, id: id)) }
    }
}

/// A card whose content slides left to reveal a Dismiss action (the brief's swipe action); a long swipe dismisses.
/// VoiceOver gets the same action through the rotor.
struct SwipeToDismissRow<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var startOpen = false
    var onDismiss: () -> Void
    @ViewBuilder var content: Content
    @State private var offset: CGFloat = 0
    @State private var dragging: CGFloat = 0
    @State private var didStart = false
    private let reveal: CGFloat = 92

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: dismiss) {
                VStack(spacing: 3) {
                    Image(systemName: "trash").font(.system(size: 18, weight: .medium))
                    Text("Dismiss").tFont(.text(13, .semibold))
                }
                .foregroundStyle(theme.onAccentColor)
                .frame(width: reveal)
                .frame(maxHeight: .infinity)
                .background(theme.accentColor)
            }
            .buttonStyle(.plain)
            .opacity(offset + dragging < -4 ? 1 : 0)
            .accessibilityHidden(true)

            content
                .background(theme.panelColor)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(offset + dragging < -1 ? theme.lineColor : .clear).frame(width: 1)
                }
                .offset(x: offset + dragging)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                            dragging = min(max(value.translation.width, -reveal * 2.2 - offset), -offset)
                        }
                        .onEnded { value in
                            let final = offset + dragging
                            dragging = 0
                            if final < -reveal * 1.8 { dismiss(); return }
                            withAnimation(.snappy(duration: 0.22)) { offset = final < -reveal / 2 ? -reveal : 0 }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
        .accessibilityAction(named: "Dismiss from Overdue") { onDismiss() }
        .onAppear {
            guard startOpen, !didStart else { return }
            didStart = true
            offset = -reveal
        }
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.2)) { offset = 0 }
        onDismiss()
    }
}

/// Upcoming work due in the next week, soonest first.
struct NextSevenDays: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var items: [WorkItem]

    var body: some View {
        let upcoming = WorkItemBuilder.upcoming(items, within: 7)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Next 7 days") {
                LinkButton("Calendar") { app.show(.calendar) }
            }
            if upcoming.isEmpty {
                if app.orderedSessions.contains(where: { $0.groups.isLoading && !$0.groups.hasValue }) {
                    LoadingCard()
                } else {
                    Card { EmptyNote(systemName: "calendar", text: "Nothing due in the next 7 days.") }
                }
            } else {
                Card {
                    ForEach(Array(upcoming.prefix(8).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider(inset: 32) }
                        WorkRow(item: item, showCourse: true)
                    }
                }
            }
        }
        .gutter()
    }
}

/// A due-work row: course colour bar, title, "MATH 2171 · Tomorrow · 11:59 PM", points or a Quiz chip.
struct WorkRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: WorkItem
    var showCourse = true

    var body: some View {
        Button {
            if let course = item.courseId, let id = item.assignmentId { app.push(.assignment(course: course, id: id)) }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(app.tint(for: item.courseId)).frame(width: 4, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).tFont(.bodyStrong).foregroundStyle(theme.inkColor).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 0) {
                        if showCourse {
                            Text(app.shortName(for: item.courseId, fallback: item.courseName)).tFont(.mono(13))
                            Text(" · ")
                        }
                        if let due = item.dueAt {
                            Text(DueFormatter.compact(due))
                                .fontWeight(isSoon ? .semibold : .regular)
                                .foregroundStyle(isSoon ? theme.brassInkColor : theme.inkDimColor)
                        }
                    }
                    .tFont(.footnote)
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                if item.kind == .quiz {
                    ChipView("Quiz", kind: .signal)
                } else if let points = item.pointsPossible {
                    Text("\(PointsText.short(points)) pts").tFont(.mono(13)).foregroundStyle(theme.inkDimColor)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
    }

    private var isSoon: Bool {
        guard let due = item.dueAt else { return false }
        return due.timeIntervalSinceNow < 48 * 3_600
    }
}
