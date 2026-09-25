import SwiftUI
import ThubanCanvasCore

/// Calendar: Agenda (week strip + day groups) or Month (grid + the chosen day), filtered by course. Work items come
/// from each course's assignments; events from Canvas calendar events. Read-only.
struct CalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var filter: CanvasID? = nil
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    private let calendar = Calendar.current

    var body: some View {
        @Bindable var app = app
        RootScreen(title, eyebrow: eyebrow) {
            Segmented(options: [(false, "Agenda"), (true, "Month")], selection: $app.calendarMonthMode)
                .accessibilityLabel("Calendar view")
        } trailing: {
            BarTextButton("Today") { selectedDay = calendar.startOfDay(for: Date()) }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if app.calendarMonthMode { MonthGrid(selectedDay: $selectedDay, entries: entries(in: monthGridRange)) }
                else { WeekStrip(selectedDay: $selectedDay, entries: entries(in: weekRange)) }
                FilterChips(options: [(CanvasID?.none, "All")] + app.orderedSessions.map { (CanvasID?.some($0.id), $0.shortTitle) },
                            selection: $filter, accessibilityLabel: "Filter by course")
                    .padding(.horizontal, -IOSMetrics.gutter)
                if app.calendarMonthMode { dayList } else { agenda }
            }
            .padding(.top, 12)
            .gutter()
        }
        .refreshable {
            await app.refreshAll()
            await app.calendar.load(range: loadRange, app: app, force: true)
        }
        .task(id: loadKey) {
            await app.loadHomeResources()
            await app.calendar.load(range: loadRange, app: app)
        }
    }

    // MARK: Ranges

    private var weekStart: Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
    }

    private var weekRange: ClosedRange<Date> { weekStart...(calendar.date(byAdding: .day, value: 7, to: weekStart)!.addingTimeInterval(-1)) }

    private var agendaRange: ClosedRange<Date> {
        let start = selectedDay
        return start...(calendar.date(byAdding: .day, value: 21, to: start)!.addingTimeInterval(-1))
    }

    private var monthInterval: DateInterval { calendar.dateInterval(of: .month, for: selectedDay)! }

    private var monthGridRange: ClosedRange<Date> { monthInterval.start...monthInterval.end.addingTimeInterval(-1) }

    private var loadRange: ClosedRange<Date> {
        let lower = min(weekRange.lowerBound, monthGridRange.lowerBound)
        let upper = max(agendaRange.upperBound, monthGridRange.upperBound)
        return lower...upper
    }

    private var loadKey: String { "\(CalendarModel.monthKey(for: selectedDay))-\(app.courses.count)" }

    private func entries(in range: ClosedRange<Date>) -> [Date: [CalendarEntry]] {
        let hidden = Set(app.courses.map(\.id)).subtracting(filter.map { [$0] } ?? app.orderedSessions.map(\.id))
        return app.calendar.entries(in: range, workItems: app.allWorkItems, hiddenCourses: hidden)
    }

    // MARK: Header copy

    private var title: String { selectedDay.formatted(.dateTime.month(.wide)) }

    private var eyebrow: String {
        if app.calendarMonthMode {
            let all = entries(in: monthGridRange).values.flatMap { $0 }
            let due = all.filter { $0.workItem != nil }.count
            return [selectedDay.formatted(.dateTime.year()), "\(due) due this month"].joined(separator: " · ")
        }
        let all = entries(in: weekRange).values.flatMap { $0 }
        let due = all.filter { $0.workItem != nil }.count
        let events = all.count - due
        return "Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day())) · \(due) due · \(events) event\(events == 1 ? "" : "s")"
    }

    // MARK: Lists

    @ViewBuilder
    private var agenda: some View {
        let buckets = entries(in: agendaRange)
        let days = buckets.keys.sorted()
        if days.isEmpty {
            if app.calendar.isLoading(range: agendaRange) { LoadingCard() }
            else { Card { EmptyNote(systemName: "calendar", text: "Nothing in the next three weeks.") } }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(days, id: \.self) { day in
                    DaySection(day: day, entries: buckets[day] ?? [])
                }
            }
        }
    }

    @ViewBuilder
    private var dayList: some View {
        let list = entries(in: selectedDay...(calendar.date(byAdding: .day, value: 1, to: selectedDay)!.addingTimeInterval(-1)))[selectedDay] ?? []
        if list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(DayLabel.title(selectedDay)) { Text(DayLabel.subtitle(selectedDay)).tFont(.footnote).foregroundStyle(theme.inkFaintColor) }
                Card { EmptyNote(systemName: "calendar", text: "Nothing on this day.") }
            }
        } else {
            DaySection(day: selectedDay, entries: list)
        }
    }
}

enum DayLabel {
    static func title(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    static func subtitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) || calendar.isDateInTomorrow(day) || calendar.isDateInYesterday(day) {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// "TODAY  Fri Sep 25" then a card of entries.
struct DaySection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var day: Date
    var entries: [CalendarEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Eyebrow(DayLabel.title(day), color: Calendar.current.isDateInToday(day) ? theme.brassInkColor : nil).accessibilityAddTraits(.isHeader)
                Text(DayLabel.subtitle(day)).tFont(.footnote).foregroundStyle(theme.inkFaintColor)
            }
            .padding(.bottom, 6)
            Card {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Rectangle().fill(theme.lineColor).frame(height: 1) }
                    Button { open(entry) } label: { row(entry) }.buttonStyle(RowPressStyle())
                }
            }
        }
    }

    private func row(_ entry: CalendarEntry) -> some View {
        HStack(spacing: 12) {
            Text(timeText(entry)).tFont(.mono(13)).foregroundStyle(theme.inkDimColor).frame(width: 64, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.8)
            RoundedRectangle(cornerRadius: 2).fill(app.tint(for: entry.courseId)).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).tFont(.text(16, .semibold)).foregroundStyle(entry.workItem?.isDone == true ? theme.inkDimColor : theme.inkColor)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Text(app.shortName(for: entry.courseId, fallback: entry.event?.contextName)).tFont(.mono(13))
                    Text(" · " + meta(entry))
                }
                .tFont(.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            Spacer(minLength: 0)
            if entry.workItem?.isDone == true {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.posTextColor).accessibilityLabel("Done")
            } else if entry.workItem?.status == .overdue {
                ChipView("Missing", kind: .neg)
            }
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 8)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func timeText(_ entry: CalendarEntry) -> String {
        if entry.isAllDay { return "All day" }
        guard let date = entry.date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func meta(_ entry: CalendarEntry) -> String {
        switch entry {
        case .work(let item):
            var parts: [String] = []
            if let points = item.pointsPossible { parts.append("\(PointsText.short(points)) pts") }
            if let first = item.submissionTypes.first {
                switch first {
                case "online_upload": parts.append("File upload")
                case "online_text_entry": parts.append("Text entry")
                case "online_quiz": parts.append("Quiz")
                case "external_tool": parts.append("External tool")
                case "on_paper": parts.append("On paper")
                case "discussion_topic": parts.append("Discussion")
                default: break
                }
            }
            return parts.isEmpty ? "Due" : parts.joined(separator: " · ")
        case .event(let event):
            return ["Event", event.locationName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private func open(_ entry: CalendarEntry) {
        switch entry {
        case .work(let item):
            if let course = item.courseId, let id = item.assignmentId { app.push(.assignment(course: course, id: id)) }
        case .event(let event):
            app.push(.event(event.id))
        }
    }
}

/// Mon–Sun with a dot per day; swipe to change week.
struct WeekStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Binding var selectedDay: Date
    var entries: [Date: [CalendarEntry]]
    private let calendar = Calendar.current

    var body: some View {
        let start = weekStart
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                cell(day)
            }
        }
        .padding(.horizontal, -6)
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            shift(value.translation.width < 0 ? 7 : -7)
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week")
        .accessibilityAction(named: "Next week") { shift(7) }
        .accessibilityAction(named: "Previous week") { shift(-7) }
    }

    private var weekStart: Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
    }

    private func shift(_ days: Int) {
        selectedDay = calendar.date(byAdding: .day, value: days, to: weekStart) ?? selectedDay
    }

    private func cell(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let selected = calendar.isDate(day, inSameDayAs: selectedDay)
        let past = day < calendar.startOfDay(for: Date())
        return Button { selectedDay = day } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(today ? theme.brassInkColor : theme.inkFaintColor)
                ZStack {
                    if today { Circle().fill(theme.accentColor).frame(width: 30, height: 30) }
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 17, weight: today ? .bold : .regular))
                        .foregroundStyle(today ? theme.onAccentColor : (past ? theme.inkDimColor : theme.inkColor))
                }
                .frame(height: 22)
                Circle().fill(dotColor(day)).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(selected ? theme.panelColor : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? theme.lineColor : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + ", \(entries[calendar.startOfDay(for: day)]?.count ?? 0) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dotColor(_ day: Date) -> Color {
        CalendarDots.color(for: entries[calendar.startOfDay(for: day)] ?? [], app: app, theme: theme)
    }
}

enum CalendarDots {
    @MainActor
    static func color(for list: [CalendarEntry], app: AppModel, theme: ResolvedTheme) -> Color {
        guard !list.isEmpty else { return .clear }
        if list.contains(where: { $0.workItem?.status == .overdue }) { return theme.negColor }
        if list.allSatisfy({ $0.workItem?.isDone == true }) { return theme.line2Color }
        let open = list.first { $0.workItem?.isDone != true } ?? list[0]
        return app.tint(for: open.courseId)
    }
}

/// A month of days with dots; the chosen day's entries list below it.
struct MonthGrid: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Binding var selectedDay: Date
    var entries: [Date: [CalendarEntry]]
    private let calendar = Calendar.current

    var body: some View {
        let days = gridDays
        VStack(spacing: 6) {
            HStack {
                IconButton(systemName: "chevron.left", label: "Previous month", size: 16) { shift(-1) }
                Spacer()
                Text(selectedDay.formatted(.dateTime.month(.wide).year())).tFont(.text(15, .semibold)).foregroundStyle(theme.inkDimColor)
                Spacer()
                IconButton(systemName: "chevron.right", label: "Next month", size: 16) { shift(1) }
            }
            .padding(.horizontal, -10)
            HStack(spacing: 0) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { index in
                    Text(["M", "T", "W", "T", "F", "S", "S"][index]).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(days, id: \.self) { day in
                    if let day { cell(day) } else { Color.clear.frame(height: 48) }
                }
            }
        }
        .padding(10)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
    }

    private var gridDays: [Date?] {
        let interval = calendar.dateInterval(of: .month, for: selectedDay)!
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday + 5) % 7
        let count = calendar.range(of: .day, in: .month, for: selectedDay)?.count ?? 30
        return Array(repeating: nil, count: leading) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func shift(_ months: Int) {
        let start = calendar.dateInterval(of: .month, for: selectedDay)!.start
        let target = calendar.date(byAdding: .month, value: months, to: start) ?? start
        selectedDay = calendar.isDate(target, equalTo: Date(), toGranularity: .month) ? calendar.startOfDay(for: Date()) : target
    }

    private func cell(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let selected = calendar.isDate(day, inSameDayAs: selectedDay)
        let list = entries[calendar.startOfDay(for: day)] ?? []
        return Button { selectedDay = day } label: {
            VStack(spacing: 3) {
                ZStack {
                    if today { Circle().fill(theme.accentColor).frame(width: 30, height: 30) }
                    else if selected { Circle().strokeBorder(theme.accentColor, lineWidth: 1.5).frame(width: 30, height: 30) }
                    Text(day.formatted(.dateTime.day())).font(.system(size: 16, weight: today ? .bold : .regular))
                        .foregroundStyle(today ? theme.onAccentColor : (day < calendar.startOfDay(for: Date()) ? theme.inkDimColor : theme.inkColor))
                }
                .frame(height: 30)
                HStack(spacing: 2) {
                    ForEach(Array(list.prefix(3).enumerated()), id: \.offset) { _, entry in
                        Circle().fill(CalendarDots.color(for: [entry], app: app, theme: theme)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + ", \(list.count) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A Canvas calendar event.
struct EventScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var eventId: String
    var back: String

    var body: some View {
        let event = app.calendar.months.values.compactMap(\.value).flatMap { $0 }.first { $0.id == eventId }
        PushedScreen("Event", back: back) {
            if let raw = event?.htmlUrl, let url = URL(string: raw) {
                IconButton(systemName: "safari", label: "Open in Canvas") { app.openInSafari(url) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let event {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow([app.shortName(for: event.courseId, fallback: event.contextName), "Event"].joined(separator: " · "))
                        Text(event.title).tFont(.display(26)).foregroundStyle(theme.inkColor)
                    }
                    Card {
                        detailRow("clock", timeLine(event))
                        if let location = event.locationName, !location.isEmpty {
                            RowDivider()
                            detailRow("mappin.and.ellipse", location)
                        }
                    }
                    if let description = event.description, !CanvasHTML.plainText(description).isEmpty {
                        Card { HTMLContentView(html: description) }
                    }
                } else {
                    Card { EmptyNote(systemName: "calendar", text: "This event is no longer in the calendar.") }
                }
            }
            .padding(.top, 8)
            .gutter()
        }
    }

    private func detailRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(theme.brassInkColor).frame(width: 22)
            Text(text).tFont(.body).foregroundStyle(theme.inkColor)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: IOSMetrics.rowHeight)
    }

    private func timeLine(_ event: CalendarEvent) -> String {
        guard let start = event.startAt else { return "No time set" }
        if event.allDay == true { return DueFormatter.compactDay(start) + " · all day" }
        let end = event.endAt.map { " – " + DueFormatter.time($0) } ?? ""
        return DueFormatter.compactDay(start) + " · " + DueFormatter.time(start) + end
    }
}
