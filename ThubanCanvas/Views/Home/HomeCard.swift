import SwiftUI
import ThubanCanvasCore

/// A Home card: eyebrow header (title · count · optional accessory) above the content, in a panel.
struct HomeCard<Content: View, Accessory: View>: View {
    var title: String
    var count: Int?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, count: Int? = nil, @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title, count: count, accessory: accessory)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .thubanPanel(padding: 16)
    }
}

extension HomeCard where Accessory == EmptyView {
    init(_ title: String, count: Int? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, count: count, accessory: { EmptyView() }, content: content)
    }
}

/// A list of rows inside a card, separated by hairlines. Rows sit 8 pt outside the card's text margin so their
/// hover highlight lines up with the header.
struct HomeRowList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    @Environment(\.thubanTheme) private var theme
    var data: Data
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 { HomeHairline() }
                row(element)
            }
        }
        .padding(.horizontal, -8)
    }
}

/// A 1 px `line` separator between rows.
struct HomeHairline: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View {
        Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline).padding(.horizontal, 8)
    }
}

/// A clickable row inside a card: hover highlight (`panel2`, radius 6), plain button, one accessibility label.
struct HomeRow<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// A quiet one-line empty state for a card ("Nothing due in the next 14 days").
struct HomeEmptyRow: View {
    @Environment(\.thubanTheme) private var theme
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.brassInkColor)
            Text(text).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Title + course line for a work item (used by Upcoming, Overdue and Recently graded).
struct HomeWorkRow<Trailing: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var item: WorkItem
    /// Second-line text after the course name (due date, graded, …).
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CourseDot(tint: item.courseId.flatMap { app.sessions[$0]?.preferences.tint })
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(ThubanFont.scaled(14, scale: textScale, weight: .medium))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text([item.courseName, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(ThubanFont.scaled(12.5, scale: textScale))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// "3 due this week · 1 overdue" for one course, from its loaded work items.
@MainActor
enum HomeSummary {
    static func dueLine(for session: CourseSession, dismissed: Set<String>, now: Date = Date()) -> String? {
        guard session.groups.value != nil else { return nil }
        let items = session.workItems
        let week = WorkItemBuilder.upcoming(items, now: now, within: 7).count
        let overdue = WorkItemBuilder.overdue(items, dismissed: dismissed).count
        var parts: [String] = []
        if week > 0 { parts.append("\(week) due this week") }
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if parts.isEmpty {
            let later = WorkItemBuilder.upcoming(items, now: now).first
            if let later, let due = later.dueAt { return "Next: \(DueFormatter.relative(due, now: now))" }
            return "Nothing due"
        }
        return parts.joined(separator: " · ")
    }

    /// "Today", "Tomorrow", else "Thursday, Sep 18".
    static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        if calendar.component(.year, from: day) == calendar.component(.year, from: now) {
            return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    /// "Fall 2026" — the term most of the starred courses share (ignoring Canvas's "Default Term").
    static func termName(for sessions: [CourseSession]) -> String? {
        var counts: [String: Int] = [:]
        for session in sessions {
            guard let name = session.course.term?.name, name != "Default Term" else { continue }
            counts[name, default: 0] += 1
        }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }
}
