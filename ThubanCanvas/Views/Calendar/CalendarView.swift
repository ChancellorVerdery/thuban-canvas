import AppKit
import SwiftUI
import ThubanCanvasCore

/// Month grid / week columns / 30-day agenda view.
enum CalendarMode: String, CaseIterable, Hashable {
    case month, week, agenda

    var label: String {
        switch self {
        case .month: return "Month"
        case .week: return "Week"
        case .agenda: return "Agenda"
        }
    }
}

/// The Calendar panel: every due date across the starred courses plus the courses' calendar events, as a month
/// grid, a week, or a 30-day agenda. Work items open their assignment; events show a popover.
struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var model = CalendarModel()
    @State private var mode: CalendarMode = .month
    /// Any date inside the displayed month / week / agenda window.
    @State private var anchor = Date()
    @State private var hiddenCourses: Set<CanvasID> = []

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            bar
            CourseFilterStrip(hiddenCourses: $hiddenCourses)
            if let error = model.error(range: visibleRange), model.events(in: visibleRange).isEmpty {
                OfflineBanner(text: "Calendar events could not be loaded — \(error.localizedDescription)") {
                    await model.load(range: visibleRange, app: app, force: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: taskKey) {
            await app.loadHomeResources()
            await model.load(range: visibleRange, app: app)
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 8) {
            IconButton(glyph: .chevronLeft, label: "Previous", size: 30, iconSize: 15) { shift(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            IconButton(glyph: .chevronRight, label: "Next", size: 30, iconSize: 15) { shift(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Text(periodTitle)
                .font(ThubanFont.display(18))
                .foregroundStyle(theme.inkColor)
                .lineLimit(1)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            Button("Today") { anchor = Date() }
                .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 8))
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(isShowingToday)
                .accessibilityLabel("Go to today")
            if model.isLoading(range: visibleRange) {
                ProgressView().controlSize(.small).accessibilityLabel("Loading events")
            }
            Spacer(minLength: 12)
            SegmentedPicker(selection: $mode, options: CalendarMode.allCases.map { SegmentOption($0, $0.label) })
                .accessibilityLabel("Calendar view")
            Button("Close") { app.panel = nil }
                .buttonStyle(GhostButtonStyle(height: 30))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close calendar")
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: ThubanMetrics.sectionBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }

    @ViewBuilder
    private var content: some View {
        let entries = model.entries(in: visibleRange, workItems: app.allWorkItems, hiddenCourses: hiddenCourses, calendar: calendar)
        switch mode {
        case .month:
            MonthGridView(monthStart: monthStart, days: monthGridDays, entries: entries)
        case .week:
            WeekView(days: weekDays, entries: entries)
        case .agenda:
            AgendaView(start: agendaStart, days: agendaDays, entries: entries)
        }
    }

    // MARK: Periods

    private var monthStart: Date { calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor }

    /// 42 days (six rows) starting on the first weekday of the row containing the 1st.
    private var monthGridDays: [Date] {
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek) }
    }

    private var weekDays: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var agendaStart: Date { calendar.startOfDay(for: anchor) }

    private var agendaDays: [Date] {
        (0..<30).compactMap { calendar.date(byAdding: .day, value: $0, to: agendaStart) }
    }

    private var visibleRange: ClosedRange<Date> {
        let days: [Date]
        switch mode {
        case .month: days = monthGridDays
        case .week: days = weekDays
        case .agenda: days = agendaDays
        }
        guard let first = days.first, let last = days.last else { return anchor...anchor }
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return first...end.addingTimeInterval(-1)
    }

    private var taskKey: String { "\(mode.rawValue)-\(visibleRange.lowerBound.timeIntervalSinceReferenceDate)" }

    private var isShowingToday: Bool {
        switch mode {
        case .month: return calendar.isDate(anchor, equalTo: Date(), toGranularity: .month)
        case .week: return calendar.isDate(anchor, equalTo: Date(), toGranularity: .weekOfYear)
        case .agenda: return calendar.isDateInToday(anchor)
        }
    }

    private var periodTitle: String {
        switch mode {
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .week:
            guard let first = weekDays.first, let last = weekDays.last else { return "" }
            let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
            let start = first.formatted(.dateTime.month(.abbreviated).day())
            let end = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
            return "\(start) – \(end), \(last.formatted(.dateTime.year()))"
        case .agenda:
            if calendar.isDateInToday(anchor) { return "Next 30 days" }
            guard let last = agendaDays.last else { return "" }
            return "\(agendaStart.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private func shift(_ direction: Int) {
        let component: Calendar.Component
        let amount: Int
        switch mode {
        case .month: component = .month; amount = direction
        case .week: component = .weekOfYear; amount = direction
        case .agenda: component = .day; amount = direction * 30
        }
        if let next = calendar.date(byAdding: component, value: amount, to: anchor) { anchor = next }
    }
}

// MARK: - Course filter

/// One chip per starred course; click to hide or show that course's items. Right-click isolates a single course.
private struct CourseFilterStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Binding var hiddenCourses: Set<CanvasID>

    var body: some View {
        let sessions = app.orderedSessions
        if sessions.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sessions) { session in
                        CourseFilterChip(title: session.compactTitle, fullName: session.displayName, tint: session.preferences.tint,
                                         isOn: !hiddenCourses.contains(session.id)) {
                            if hiddenCourses.contains(session.id) { hiddenCourses.remove(session.id) } else { hiddenCourses.insert(session.id) }
                        }
                        .contextMenu {
                            Button("Only \(session.displayName)") { hiddenCourses = Set(sessions.map(\.id)).subtracting([session.id]) }
                            Button("Show all courses") { hiddenCourses = [] }
                        }
                    }
                    if !hiddenCourses.isEmpty {
                        Button("Show all") { hiddenCourses = [] }
                            .buttonStyle(GhostButtonStyle(height: 26, tinted: true, horizontalPadding: 8))
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 40)
            .thubanHairline(.bottom, color: theme.lineColor)
        }
    }
}

private struct CourseFilterChip: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var fullName: String
    var tint: String?
    var isOn: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                CourseDot(tint: tint, size: 7).opacity(isOn ? 1 : 0.4)
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? theme.inkColor : theme.inkDimColor)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(isOn ? theme.panelColor : (hovering ? theme.panel2Color : .clear), in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous)
                    .strokeBorder(isOn ? theme.line2Color : theme.lineColor, lineWidth: ThubanMetrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(fullName)
        .accessibilityLabel("Show \(fullName)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Month

/// 7 × 6 grid; each cell lists up to three entries as pills and a "+n more" popover.
private struct MonthGridView: View {
    @Environment(\.thubanTheme) private var theme
    var monthStart: Date
    var days: [Date]
    var entries: [Date: [CalendarEntry]]
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(ThubanFont.micro)
                        .kerning(0.5)
                        .foregroundStyle(theme.inkDimColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 30)
            .background(theme.bgColor)
            .thubanHairline(.bottom, color: theme.lineColor)
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(days[(row * 7)..<(row * 7 + 7)], id: \.self) { day in
                        MonthDayCell(day: day, inMonth: calendar.isDate(day, equalTo: monthStart, toGranularity: .month),
                                     entries: entries[day] ?? [])
                            .thubanHairline(.trailing, color: theme.lineColor)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .thubanHairline(.bottom, color: theme.lineColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panelColor)
    }
}

private struct MonthDayCell: View {
    @Environment(\.thubanTheme) private var theme
    var day: Date
    var inMonth: Bool
    var entries: [CalendarEntry]
    @State private var showingAll = false
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private let maxPills = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? theme.onAccentColor : (inMonth ? theme.inkColor : theme.inkFaintColor))
                    .frame(minWidth: 22, minHeight: 22)
                    .background(isToday ? theme.accentColor : .clear, in: Circle())
                Spacer(minLength: 0)
                if entries.count > maxPills {
                    Text(String(entries.count))
                        .font(ThubanFont.micro)
                        .foregroundStyle(theme.inkFaintColor)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 5)
            ForEach(entries.prefix(maxPills)) { entry in
                EntryPill(entry: entry)
            }
            if entries.count > maxPills {
                Button { showingAll = true } label: {
                    Text("+\(entries.count - maxPills) more").frame(minHeight: 24).contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.horizontal, 6)
                    .accessibilityLabel("Show all \(entries.count) items on \(day.formatted(date: .abbreviated, time: .omitted))")
                    .popover(isPresented: $showingAll, arrowEdge: .bottom) {
                        DayListPopover(day: day, entries: entries)
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isToday ? theme.accentTintColor : (inMonth ? theme.panelColor : theme.bgColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(entries.count) items")
    }
}

/// Course dot + truncated title, tinted by status; opens the assignment or an event popover.
private struct EntryPill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var entry: CalendarEntry
    var showsTime = false
    @State private var showingEvent = false
    @State private var hovering = false

    var body: some View {
        Button {
            open(entry, app: app, showEvent: $showingEvent)
        } label: {
            HStack(spacing: 5) {
                CourseDot(tint: app.sessions[entry.courseId ?? 0]?.preferences.tint, size: 6)
                if showsTime, let date = entry.date, !entry.isAllDay {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(theme.inkDimColor)
                        .monospacedDigit()
                }
                Text(entry.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(entry.workItem?.isDone == true, color: theme.inkFaintColor)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(entryColor(entry, theme: theme))
            .padding(.horizontal, 5)
            .frame(height: 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? theme.panel2Color : theme.panel2Color.opacity(0.55), in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .padding(.vertical, 2)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entryHelp(entry, app: app))
        .accessibilityLabel(entryHelp(entry, app: app))
        .popover(isPresented: $showingEvent, arrowEdge: .bottom) {
            if let event = entry.event { EventPopover(event: event) }
        }
    }
}

/// Status → color: overdue red, done dim, everything else ink.
private func entryColor(_ entry: CalendarEntry, theme: ResolvedTheme) -> Color {
    switch entry {
    case .event: return theme.inkColor
    case .work(let item):
        switch item.status {
        case .overdue: return theme.negTextColor
        case .submitted, .graded, .excused: return theme.inkDimColor
        case .upcoming, .noDate: return theme.inkColor
        }
    }
}

@MainActor
private func entryHelp(_ entry: CalendarEntry, app: AppModel) -> String {
    let course = app.sessions[entry.courseId ?? 0]?.displayName ?? entry.event?.contextName ?? entry.workItem?.courseName ?? ""
    let when: String
    if entry.isAllDay { when = "All day" } else if let date = entry.date { when = DueFormatter.relative(date) } else { when = "" }
    let status: String
    switch entry.workItem?.status {
    case .overdue: status = "Overdue"
    case .submitted: status = entry.workItem?.late == true ? "Submitted late" : "Submitted"
    case .graded: status = entry.workItem?.late == true ? "Graded, late" : "Graded"
    case .excused: status = "Excused"
    case .upcoming, .noDate, .none: status = ""
    }
    return [entry.title, course, when, status].filter { !$0.isEmpty }.joined(separator: " · ")
}

/// Work items open their assignment (and close the panel); events toggle their popover.
@MainActor
private func open(_ entry: CalendarEntry, app: AppModel, showEvent: Binding<Bool>) {
    switch entry {
    case .work(let item):
        guard let course = item.courseId, let assignment = item.assignmentId else { return }
        app.open(course: course, section: .assignments, route: .assignment(assignment))
        app.panel = nil
    case .event:
        showEvent.wrappedValue = true
    }
}

// MARK: - Popovers

/// A calendar event: when, where, the description as plain text, and a link to Canvas.
private struct EventPopover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title.isEmpty ? "Event" : event.title)
                .font(ThubanFont.display(16))
                .foregroundStyle(theme.inkColor)
                .fixedSize(horizontal: false, vertical: true)
            if let course = app.sessions[event.courseId ?? 0]?.displayName ?? event.contextName {
                HStack(spacing: 6) {
                    CourseDot(tint: app.sessions[event.courseId ?? 0]?.preferences.tint, size: 7)
                    Text(course).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                }
            }
            Label(whenText, systemImage: "clock")
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkColor)
            if let location = event.locationName, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkColor)
            }
            let description = CanvasHTML.plainText(event.description, limit: 600)
            if !description.isEmpty {
                Text(description)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let raw = event.htmlUrl, let url = URL(string: raw) {
                Button("Open in Canvas") { NSWorkspace.shared.open(url) }
                    .buttonStyle(GhostButtonStyle(height: 28, tinted: true, horizontalPadding: 8))
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(theme.panelColor)
    }

    private var whenText: String {
        guard let start = event.startAt else { return "No time" }
        if event.allDay == true { return start.formatted(date: .complete, time: .omitted) + " · All day" }
        let day = start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        var text = "\(day) · \(start.formatted(date: .omitted, time: .shortened))"
        if let end = event.endAt, end > start { text += " – \(end.formatted(date: .omitted, time: .shortened))" }
        return text
    }
}

/// Every entry on one day (the "+n more" popover).
private struct DayListPopover: View {
    @Environment(\.thubanTheme) private var theme
    var day: Date
    var entries: [CalendarEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(ThubanFont.display(16))
                .foregroundStyle(theme.inkColor)
            VStack(spacing: 4) {
                ForEach(entries) { entry in EntryPill(entry: entry, showsTime: true) }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(theme.panelColor)
    }
}

// MARK: - Week

/// Seven columns; each lists the day's entries in time order as small cards.
private struct WeekView: View {
    @Environment(\.thubanTheme) private var theme
    var days: [Date]
    var entries: [Date: [CalendarEntry]]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    WeekDayHeader(day: day, count: entries[day]?.count ?? 0)
                        .thubanHairline(.trailing, color: theme.lineColor)
                }
            }
            .frame(height: 48)
            .thubanHairline(.bottom, color: theme.lineColor)
            GeometryReader { geometry in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            VStack(spacing: 6) {
                                ForEach(entries[day] ?? []) { entry in
                                    WeekEntryCard(entry: entry)
                                }
                                if (entries[day] ?? []).isEmpty {
                                    Text("—").font(ThubanFont.small).foregroundStyle(theme.inkFaintColor).padding(.top, 10)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Calendar.current.isDateInToday(day) ? theme.accentTintColor.opacity(0.5) : .clear)
                            .thubanHairline(.trailing, color: theme.lineColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panelColor)
    }
}

private struct WeekDayHeader: View {
    @Environment(\.thubanTheme) private var theme
    var day: Date
    var count: Int
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        HStack(spacing: 8) {
            Text(day.formatted(.dateTime.day()))
                .font(ThubanFont.display(18))
                .monospacedDigit()
                .foregroundStyle(isToday ? theme.onAccentColor : theme.inkColor)
                .frame(width: 30, height: 30)
                .background(isToday ? theme.accentColor : .clear, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(ThubanFont.micro)
                    .kerning(0.5)
                    .foregroundStyle(isToday ? theme.brassInkColor : theme.inkDimColor)
                if count > 0 {
                    Text(count == 1 ? "1 item" : "\(count) items")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkFaintColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? theme.accentTintColor : theme.bgColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) items")
    }
}

private struct WeekEntryCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var entry: CalendarEntry
    @State private var showingEvent = false
    @State private var hovering = false

    var body: some View {
        Button {
            open(entry, app: app, showEvent: $showingEvent)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    CourseDot(tint: app.sessions[entry.courseId ?? 0]?.preferences.tint, size: 6)
                    Text(timeText)
                        .font(.system(size: 11 * textScale, weight: .semibold))
                        .foregroundStyle(entry.workItem?.status == .overdue ? theme.negTextColor : theme.inkDimColor)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if let location = entry.event?.locationName, !location.isEmpty {
                        Image(systemName: "mappin").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
                            .accessibilityLabel(location)
                    }
                }
                Text(entry.title)
                    .font(.system(size: 12 * textScale, weight: .medium))
                    .foregroundStyle(entryColor(entry, theme: theme))
                    .strikethrough(entry.workItem?.isDone == true, color: theme.inkFaintColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let course = app.sessions[entry.courseId ?? 0]?.compactTitle, !(entry.event != nil && entry.title.hasPrefix(course)) {
                    Text(course)
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? theme.panel2Color : theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entryHelp(entry, app: app))
        .accessibilityLabel(entryHelp(entry, app: app))
        .popover(isPresented: $showingEvent, arrowEdge: .trailing) {
            if let event = entry.event { EventPopover(event: event) }
        }
    }

    private var timeText: String {
        if entry.isAllDay { return "All day" }
        guard let date = entry.date else { return "No time" }
        if let item = entry.workItem {
            switch item.status {
            case .overdue: return "Overdue · " + date.formatted(date: .omitted, time: .shortened)
            case .submitted: return "Submitted"
            case .graded: return "Graded"
            case .excused: return "Excused"
            case .upcoming, .noDate: return "Due " + date.formatted(date: .omitted, time: .shortened)
            }
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Agenda

/// The next 30 days, grouped by day; days with nothing are skipped.
private struct AgendaView: View {
    @Environment(\.thubanTheme) private var theme
    var start: Date
    var days: [Date]
    var entries: [Date: [CalendarEntry]]

    var body: some View {
        let populated = days.filter { !(entries[$0] ?? []).isEmpty }
        if populated.isEmpty {
            EmptyState(title: "Nothing scheduled", message: "No due dates or events in this window for the courses shown.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(populated, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(dayTitle(day), count: entries[day]?.count)
                            ForEach(entries[day] ?? []) { entry in
                                AgendaRow(entry: entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let full = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if calendar.isDateInToday(day) { return "Today · \(full)" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow · \(full)" }
        return full
    }
}

private struct AgendaRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var entry: CalendarEntry
    @State private var showingEvent = false

    var body: some View {
        ListRowCard(action: { open(entry, app: app, showEvent: $showingEvent) }) {
            HStack(spacing: 12) {
                Text(timeText)
                    .font(.system(size: 12 * textScale, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                    .monospacedDigit()
                    .frame(width: 76, alignment: .leading)
                CourseDot(tint: app.sessions[entry.courseId ?? 0]?.preferences.tint, size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 14 * textScale, weight: .semibold))
                        .foregroundStyle(entryColor(entry, theme: theme))
                        .strikethrough(entry.workItem?.isDone == true, color: theme.inkFaintColor)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12 * textScale))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let item = entry.workItem {
                    if let points = item.pointsPossible, points > 0 {
                        Text("\(DueFormatter.points(points)) pts")
                            .font(.system(size: 12 * textScale))
                            .foregroundStyle(theme.inkDimColor)
                            .monospacedDigit()
                    }
                    if let chip = Chip.status(item) { chip }
                    if let due = item.dueAt, item.status == .upcoming {
                        Text(DueFormatter.countdown(due))
                            .font(.system(size: 12 * textScale, weight: .medium))
                            .foregroundStyle(theme.inkDimColor)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                } else if let location = entry.event?.locationName, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .font(.system(size: 12 * textScale))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .trailing)
                }
            }
        }
        .accessibilityLabel(entryHelp(entry, app: app))
        .popover(isPresented: $showingEvent, arrowEdge: .trailing) {
            if let event = entry.event { EventPopover(event: event) }
        }
    }

    private var timeText: String {
        if entry.isAllDay { return "All day" }
        guard let date = entry.date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var subtitle: String {
        let course = app.sessions[entry.courseId ?? 0]?.displayName ?? entry.event?.contextName ?? entry.workItem?.courseName ?? ""
        switch entry {
        case .work(let item):
            let kind: String
            switch item.kind {
            case .quiz: kind = "Quiz"
            case .discussion: kind = "Discussion"
            case .assignment: kind = "Assignment"
            case .event: kind = "Event"
            case .todo: kind = "To do"
            }
            return [course, kind].filter { !$0.isEmpty }.joined(separator: " · ")
        case .event(let event):
            // Event titles often carry the course name already; lead with "Event" and add the end time.
            let code = app.sessions[entry.courseId ?? 0]?.compactTitle
            let lead = (code.map { entry.title.hasPrefix($0) } ?? false) ? "Event" : course
            if let end = event.endAt, let start = event.startAt, end > start, event.allDay != true {
                return [lead, "until " + end.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return lead
        }
    }
}
