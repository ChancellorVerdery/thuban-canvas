import SwiftUI
import ThubanCanvasCore

/// How far ahead the Upcoming card looks.
enum HomeUpcomingWindow: Hashable, CaseIterable {
    case week, fortnight, all

    var label: String {
        switch self {
        case .week: return "7 days"
        case .fortnight: return "14 days"
        case .all: return "All"
        }
    }

    var days: Int? {
        switch self {
        case .week: return 7
        case .fortnight: return 14
        case .all: return nil
        }
    }
}

/// Everything due across the starred courses, grouped by day, with a 7 / 14 / all-days toggle.
struct HomeUpcomingCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var items: [WorkItem]
    @State private var window: HomeUpcomingWindow = .fortnight

    var body: some View {
        let now = Date()
        let upcoming = WorkItemBuilder.upcoming(items, now: now, within: window.days)
        let days = WorkItemBuilder.groupedByDay(upcoming)
        HomeCard("Upcoming", count: upcoming.count) {
            SegmentedPicker(selection: $window, options: HomeUpcomingWindow.allCases.map { SegmentOption($0, $0.label) }, segmentHeight: SegmentedPickerHeight.card)
                .accessibilityLabel("Upcoming window")
        } content: {
            if upcoming.isEmpty {
                HomeEmptyRow(symbol: "checkmark.circle", text: emptyText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HomeSummary.dayTitle(group.day, now: now).uppercased())
                                .font(ThubanFont.micro)
                                .kerning(0.5)
                                .foregroundStyle(theme.inkFaintColor)
                                .padding(.bottom, 2)
                            HomeRowList(data: group.items) { item in
                                HomeRow(label: rowLabel(item, now: now), action: { open(item) }) {
                                    HomeWorkRow(item: item, detail: item.dueAt.map { "\(DueFormatter.relative($0, now: now)) · \(DueFormatter.countdown($0, now: now))" }) {
                                        HStack(spacing: 8) {
                                            if let chip = Chip.status(item, now: now) { chip }
                                            Text(points(item))
                                                .font(ThubanFont.small)
                                                .foregroundStyle(theme.inkDimColor)
                                                .monospacedDigit()
                                                .frame(minWidth: 44, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyText: String {
        if items.isEmpty && app.orderedSessions.contains(where: { $0.groups.value == nil }) { return "Loading assignments from Canvas…" }
        switch window {
        case .week: return "Nothing due in the next 7 days."
        case .fortnight: return "Nothing due in the next 14 days."
        case .all: return "Nothing due. Enjoy it."
        }
    }

    private func points(_ item: WorkItem) -> String {
        guard let possible = item.pointsPossible, possible > 0 else { return "" }
        return "\(DueFormatter.points(possible)) pts"
    }

    private func rowLabel(_ item: WorkItem, now: Date) -> String {
        var text = "\(item.title), \(item.courseName)"
        if let due = item.dueAt { text += ", due \(DueFormatter.relative(due, now: now))" }
        if let possible = item.pointsPossible, possible > 0 { text += ", \(DueFormatter.points(possible)) points" }
        return text
    }

    private func open(_ item: WorkItem) {
        guard let course = item.courseId, let id = item.assignmentId else { return }
        app.open(course: course, section: .assignments, route: .assignment(id))
    }
}

/// Past-due work with nothing handed in. Each row can be dismissed (kept in Settings, restorable here).
struct HomeOverdueCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var items: [WorkItem]
    @State private var showDismissed = false

    var body: some View {
        let now = Date()
        let dismissed = app.settings.dismissedOverdue
        let overdue = WorkItemBuilder.overdue(items, dismissed: dismissed)
        let hidden = dismissedRows(dismissed)
        HomeCard("Overdue", count: overdue.count) {
            if !hidden.isEmpty {
                Button {
                    showDismissed.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(showDismissed ? "Hide dismissed" : "Show dismissed (\(hidden.count))")
                        Glyph(showDismissed ? .chevronDown : .chevronRight, size: 12)
                    }
                }
                .buttonStyle(GhostButtonStyle(height: 24, horizontalPadding: 6))
                .accessibilityLabel(showDismissed ? "Hide dismissed items" : "Show \(hidden.count) dismissed items")
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if overdue.isEmpty {
                    HomeEmptyRow(symbol: "checkmark.circle", text: items.isEmpty ? "Nothing overdue so far." : "Nothing overdue.")
                } else {
                    HomeRowList(data: overdue) { item in
                        HStack(spacing: 4) {
                            HomeRow(label: rowLabel(item, now: now), action: { open(item) }) {
                                HomeWorkRow(item: item, detail: item.dueAt.map { "was due \(DueFormatter.relative($0, now: now)) · \(DueFormatter.countdown($0, now: now))" }) {
                                    HStack(spacing: 8) {
                                        if let chip = Chip.status(item, now: now) { chip }
                                        if let possible = item.pointsPossible, possible > 0 {
                                            Text("\(DueFormatter.points(possible)) pts")
                                                .font(ThubanFont.small)
                                                .foregroundStyle(theme.inkDimColor)
                                                .monospacedDigit()
                                        }
                                    }
                                }
                            }
                            Button("Dismiss") { app.dismissOverdue(item) }
                                .buttonStyle(GhostButtonStyle(height: 26, horizontalPadding: 8))
                                .accessibilityLabel("Dismiss \(item.title) from overdue")
                                .padding(.trailing, 8)
                        }
                    }
                }
                if showDismissed, !hidden.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dismissed".uppercased())
                            .font(ThubanFont.micro)
                            .kerning(0.5)
                            .foregroundStyle(theme.inkFaintColor)
                            .padding(.bottom, 2)
                        HomeRowList(data: hidden) { row in
                            HStack(spacing: 8) {
                                CourseDot(tint: row.courseId.flatMap { app.sessions[$0]?.preferences.tint })
                                Text(row.title)
                                    .font(ThubanFont.small)
                                    .foregroundStyle(theme.inkDimColor)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(row.courseName)
                                    .font(ThubanFont.small)
                                    .foregroundStyle(theme.inkFaintColor)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Button("Restore") { app.restoreOverdue(row.id) }
                                    .buttonStyle(GhostButtonStyle(height: 24, tinted: true, horizontalPadding: 6))
                                    .accessibilityLabel("Restore \(row.title) to overdue")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
    }

    /// A dismissed key resolved back to a title where the item is still known.
    struct DismissedRow: Identifiable {
        var id: String
        var title: String
        var courseName: String
        var courseId: CanvasID?
    }

    private func dismissedRows(_ keys: Set<String>) -> [DismissedRow] {
        keys.sorted().map { key in
            if let item = items.first(where: { $0.dismissKey == key }) {
                return DismissedRow(id: key, title: item.title, courseName: item.courseName, courseId: item.courseId)
            }
            let courseId = key.split(separator: ":").first.flatMap { CanvasID($0) }
            let courseName = courseId.flatMap { app.sessions[$0]?.displayName } ?? "Course no longer starred"
            return DismissedRow(id: key, title: "Assignment \(key.split(separator: ":").last.map(String.init) ?? key)", courseName: courseName, courseId: courseId)
        }
    }

    private func rowLabel(_ item: WorkItem, now: Date) -> String {
        var text = "\(item.title), \(item.courseName), overdue"
        if let due = item.dueAt { text += ", was due \(DueFormatter.relative(due, now: now))" }
        return text
    }

    private func open(_ item: WorkItem) {
        guard let course = item.courseId, let id = item.assignmentId else { return }
        app.open(course: course, section: .assignments, route: .assignment(id))
    }
}

/// The latest graded work with score, course and the class mean when Canvas shares it.
struct HomeRecentlyGradedCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var items: [WorkItem]

    var body: some View {
        let graded = WorkItemBuilder.recentlyGraded(items)
        HomeCard("Recently graded") {
            if graded.isEmpty {
                HomeEmptyRow(symbol: "checkmark.seal", text: "Nothing graded yet.")
            } else {
                HomeRowList(data: graded) { item in
                    HomeRow(label: rowLabel(item), action: { open(item) }) {
                        HomeWorkRow(item: item, detail: detail(item)) {
                            ScoreText(score: item.score, possible: item.pointsPossible, size: 13)
                        }
                    }
                }
            }
        }
    }

    private func mean(_ item: WorkItem) -> Double? {
        guard let course = item.courseId, let id = item.assignmentId else { return nil }
        return app.sessions[course]?.assignment(id)?.scoreStatistics?.mean
    }

    /// "class mean 90.6 · graded Sep 17"
    private func detail(_ item: WorkItem) -> String {
        var parts: [String] = []
        if let mean = mean(item) { parts.append("class mean \(Self.oneDecimal(mean))") }
        if let date = dateLabel(item) { parts.append(date) }
        return parts.joined(separator: " · ")
    }

    /// "graded Sep 17" (or "due Sep 17" when Canvas gives no graded date).
    private func dateLabel(_ item: WorkItem) -> String? {
        guard let date = item.gradedAt ?? item.dueAt else { return nil }
        let day = Calendar.current.isDateInToday(date) ? "today" : date.formatted(.dateTime.month(.abbreviated).day())
        return (item.gradedAt != nil ? "graded " : "due ") + day
    }

    private static func oneDecimal(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func rowLabel(_ item: WorkItem) -> String {
        var text = "\(item.title), \(item.courseName), \(DueFormatter.points(item.score)) of \(DueFormatter.points(item.pointsPossible))"
        if let mean = mean(item) { text += ", class mean \(Self.oneDecimal(mean))" }
        if let date = dateLabel(item) { text += ", \(date)" }
        return text
    }

    private func open(_ item: WorkItem) {
        guard let course = item.courseId, let id = item.assignmentId else { return }
        app.open(course: course, section: .assignments, route: .assignment(id))
    }
}
