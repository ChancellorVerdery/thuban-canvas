import Foundation
import Observation
import ThubanCanvasCore

/// Canvas's SIS-style names ("202680-Fall 2026-MATH-2171-005-Differential Equations") shortened for display.
enum CourseNaming {
    /// "MATH 2171 · Differential Equations", or "MEGR 2152" when nothing readable follows the code; nil when the
    /// text is not an SIS-style name.
    static func shorten(_ raw: String) -> String? {
        // "202680-Fall 2026-MATH-2171-" or "Spring_2026_PHYS_2101_", then the section and/or the readable name.
        let prefixPattern = #"^(\d{6}-[^-]*-|(Spring|Summer|Fall|Winter)[_ ]\d{4}[_-])[A-Z]{2,5}[-_]\d{3,4}[A-Z]?[-_]?"#
        guard let match = raw.range(of: prefixPattern, options: .regularExpression) else { return nil }
        let prefix = String(raw[match])
        guard let codeRange = prefix.range(of: #"[A-Z]{2,5}[-_]\d{3,4}[A-Z]?"#, options: .regularExpression) else { return nil }
        let code = String(prefix[codeRange]).replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
        var rest = String(raw[match.upperBound...])
        // Cross-listed sections ("L01:ECGR-2161-L03:…") carry nothing readable.
        if rest.contains(":") { return code }
        rest = rest.replacingOccurrences(of: #"^[A-Z]?\d{3}[-_ ]?"#, with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"[-_ ]?Combined$"#, with: "", options: [.regularExpression, .caseInsensitive])
        rest = rest.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? code : "\(code) · \(rest)"
    }
}

/// One thing on the calendar: a work item (assignment / quiz due) or a Canvas calendar event (class meeting,
/// office hours …). Both sort by `date`; events carry their own span and location.
enum CalendarEntry: Identifiable, Hashable {
    case work(WorkItem)
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .work(let item): return "work-" + item.id
        case .event(let event): return "event-" + event.id
        }
    }

    /// The moment used for sorting and day grouping (a due date, or the event's start).
    var date: Date? {
        switch self {
        case .work(let item): return item.dueAt
        case .event(let event): return event.startAt
        }
    }

    var title: String {
        switch self {
        case .work(let item): return item.title
        case .event(let event):
            if event.title.isEmpty { return "Event" }
            return CourseNaming.shorten(event.title) ?? event.title
        }
    }

    var courseId: CanvasID? {
        switch self {
        case .work(let item): return item.courseId
        case .event(let event): return event.courseId
        }
    }

    var isAllDay: Bool {
        if case .event(let event) = self { return event.allDay == true }
        return false
    }

    var workItem: WorkItem? {
        if case .work(let item) = self { return item }
        return nil
    }

    var event: CalendarEvent? {
        if case .event(let event) = self { return event }
        return nil
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CalendarEntry, rhs: CalendarEntry) -> Bool { lhs.id == rhs.id }
}

/// Owns the calendar events per month (cache-first, one `Resource` per visible month) and merges them with the
/// work items across the starred courses into day buckets for the month / week / agenda views.
@MainActor
@Observable
final class CalendarModel {
    /// Calendar events keyed by `yyyy-MM`.
    private(set) var months: [String: Resource<[CalendarEvent]>] = [:]

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func resource(forMonthKey key: String) -> Resource<[CalendarEvent]> {
        if let existing = months[key] { return existing }
        let created = Resource<[CalendarEvent]>(key: "calendar/events/\(key)", ttl: 600)
        months[key] = created
        return created
    }

    /// The months whose events cover `range` (inclusive of the month containing `range.upperBound`).
    static func monthStarts(covering range: ClosedRange<Date>, calendar: Calendar = .current) -> [Date] {
        guard let first = calendar.dateInterval(of: .month, for: range.lowerBound)?.start else { return [] }
        var starts: [Date] = []
        var cursor = first
        while cursor <= range.upperBound, starts.count < 6 {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return starts
    }

    /// Loads (cache first) every month that intersects `range` for the starred courses, in parallel.
    func load(range: ClosedRange<Date>, app: AppModel, force: Bool = false) async {
        let courseIds = app.courses.map(\.id)
        let calendar = Calendar.current
        await withTaskGroup(of: Void.self) { group in
            for start in Self.monthStarts(covering: range, calendar: calendar) {
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                let resource = self.resource(forMonthKey: Self.monthKey(for: start, calendar: calendar))
                group.addTask { @MainActor in
                    await resource.load(app: app, force: force) { client in
                        try await client.calendarEvents(courses: courseIds, from: start, to: end, type: "event")
                    }
                }
            }
        }
    }

    /// True while any month in `range` is fetching for the first time.
    func isLoading(range: ClosedRange<Date>) -> Bool {
        Self.monthStarts(covering: range).contains { start in
            guard let resource = months[Self.monthKey(for: start)] else { return false }
            return resource.isLoading && !resource.hasValue
        }
    }

    /// The first error among the months in `range` (when nothing else could be shown for that month).
    func error(range: ClosedRange<Date>) -> ThubanError? {
        for start in Self.monthStarts(covering: range) {
            if let resource = months[Self.monthKey(for: start)], let error = resource.error { return error }
        }
        return nil
    }

    /// Calendar events with a start inside `range`, deduplicated across month boundaries.
    func events(in range: ClosedRange<Date>) -> [CalendarEvent] {
        var seen = Set<String>()
        var result: [CalendarEvent] = []
        for start in Self.monthStarts(covering: range) {
            guard let events = months[Self.monthKey(for: start)]?.value else { continue }
            for event in events {
                guard event.workflowState != "deleted", let date = event.startAt, range.contains(date) else { continue }
                if seen.insert(event.id).inserted { result.append(event) }
            }
        }
        return result
    }

    /// Everything in `range` (work items with due dates + events), filtered by course, grouped by local day.
    func entries(in range: ClosedRange<Date>, workItems: [WorkItem], hiddenCourses: Set<CanvasID>, calendar: Calendar = .current) -> [Date: [CalendarEntry]] {
        var buckets: [Date: [CalendarEntry]] = [:]
        for item in workItems {
            guard let due = item.dueAt, range.contains(due) else { continue }
            if let course = item.courseId, hiddenCourses.contains(course) { continue }
            buckets[calendar.startOfDay(for: due), default: []].append(.work(item))
        }
        for event in events(in: range) {
            guard let start = event.startAt else { continue }
            if let course = event.courseId, hiddenCourses.contains(course) { continue }
            buckets[calendar.startOfDay(for: start), default: []].append(.event(event))
        }
        for (day, entries) in buckets {
            buckets[day] = entries.sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                let da = a.date ?? .distantFuture, db = b.date ?? .distantFuture
                if da != db { return da < db }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
        return buckets
    }
}
