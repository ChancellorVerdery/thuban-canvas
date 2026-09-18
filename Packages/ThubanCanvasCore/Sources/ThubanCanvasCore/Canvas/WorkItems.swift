import Foundation

/// One thing to do, normalized from assignments, quizzes, planner items and calendar events so the Home,
/// Calendar and menu bar all agree.
public struct WorkItem: Identifiable, Equatable, Sendable, Hashable {
    public enum Kind: String, Sendable { case assignment, quiz, discussion, event, todo }
    public enum Status: String, Sendable { case upcoming, overdue, submitted, graded, excused, noDate }

    public var id: String
    public var kind: Kind
    public var courseId: CanvasID?
    public var courseName: String
    public var title: String
    public var dueAt: Date?
    public var pointsPossible: Double?
    public var score: Double?
    public var status: Status
    public var htmlUrl: String?
    public var assignmentId: CanvasID?
    public var quizId: CanvasID?
    public var late: Bool
    public var missing: Bool
    public var lockedForUser: Bool
    public var acceptsOnlineSubmission: Bool
    public var submissionTypes: [String]

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: WorkItem, rhs: WorkItem) -> Bool { lhs.id == rhs.id }

    /// Key used for the dismissed-overdue set.
    public var dismissKey: String { "\(courseId ?? 0):\(assignmentId ?? quizId ?? 0)" }

    public init(assignment: Assignment, courseId: CanvasID, courseName: String, now: Date = Date()) {
        id = "assignment-\(assignment.id)"
        kind = assignment.isQuizAssignment == true || assignment.quizId != nil ? .quiz : (assignment.discussionTopic != nil ? .discussion : .assignment)
        self.courseId = courseId
        self.courseName = courseName
        title = assignment.name
        dueAt = assignment.dueAt
        pointsPossible = assignment.pointsPossible
        score = assignment.submission?.score
        htmlUrl = assignment.htmlUrl
        assignmentId = assignment.id
        quizId = assignment.quizId
        late = assignment.submission?.late ?? false
        missing = assignment.submission?.missing ?? false
        lockedForUser = assignment.lockedForUser ?? false
        acceptsOnlineSubmission = assignment.acceptsOnlineSubmission
        submissionTypes = assignment.submissionTypes ?? []
        status = Self.status(for: assignment, now: now)
    }

    static func status(for assignment: Assignment, now: Date) -> Status {
        let submission = assignment.submission
        if submission?.excused == true { return .excused }
        if submission?.isGraded == true { return .graded }
        if submission?.isSubmitted == true { return .submitted }
        guard let due = assignment.dueAt else { return .noDate }
        if due > now { return .upcoming }
        // Past due and nothing handed in. Paper / in-class work is only "overdue" when Canvas flags it missing.
        if submission?.missing == true { return .overdue }
        if assignment.isOnPaperOrNone || assignment.submissionTypes?.contains("external_tool") == true { return .noDate }
        return .overdue
    }

    public var isDone: Bool { status == .submitted || status == .graded || status == .excused }
}

public enum WorkItemBuilder {
    /// Flattens every course's assignment groups into work items.
    public static func items(for courseId: CanvasID, courseName: String, groups: [AssignmentGroup], now: Date = Date()) -> [WorkItem] {
        groups.flatMap { $0.assignments ?? [] }
            .filter { $0.published != false }
            .map { WorkItem(assignment: $0, courseId: courseId, courseName: courseName, now: now) }
    }

    /// Due after `now`, not done, soonest first.
    public static func upcoming(_ items: [WorkItem], now: Date = Date(), within days: Int? = nil) -> [WorkItem] {
        let limit = days.map { now.addingTimeInterval(Double($0) * 86_400) }
        return items.filter { item in
            guard item.status == .upcoming, let due = item.dueAt else { return false }
            if let limit { return due <= limit }
            return true
        }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    /// Past due, nothing handed in, not dismissed; most recent first.
    public static func overdue(_ items: [WorkItem], dismissed: Set<String>) -> [WorkItem] {
        items.filter { $0.status == .overdue && !dismissed.contains($0.dismissKey) }
            .sorted { ($0.dueAt ?? .distantPast) > ($1.dueAt ?? .distantPast) }
    }

    /// Graded or submitted, most recent activity first.
    public static func recentlyGraded(_ items: [WorkItem], limit: Int = 8) -> [WorkItem] {
        Array(items.filter { $0.status == .graded }.sorted { ($0.dueAt ?? .distantPast) > ($1.dueAt ?? .distantPast) }.prefix(limit))
    }

    /// Groups by calendar day (local), preserving order.
    public static func groupedByDay(_ items: [WorkItem], calendar: Calendar = .current) -> [(day: Date, items: [WorkItem])] {
        var order: [Date] = []
        var buckets: [Date: [WorkItem]] = [:]
        for item in items {
            guard let due = item.dueAt else { continue }
            let day = calendar.startOfDay(for: due)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

/// Human date strings shared by every list.
public enum DueFormatter {
    public static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = date.timeIntervalSince(now)
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today · \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow · \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday · \(time)" }
        if abs(seconds) < 6 * 86_400 {
            let weekday = date.formatted(.dateTime.weekday(.wide))
            return "\(weekday) · \(time)"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day()) + " · " + time
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    /// "in 3 h", "2 d ago"
    public static func countdown(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        let magnitude = abs(seconds)
        let text: String
        if magnitude < 3_600 { text = "\(max(1, Int(magnitude / 60))) min" }
        else if magnitude < 86_400 { text = "\(Int(magnitude / 3_600)) h" }
        else if magnitude < 86_400 * 14 { text = "\(Int(magnitude / 86_400)) d" }
        else { text = "\(Int(magnitude / (86_400 * 7))) wk" }
        return seconds >= 0 ? "in \(text)" : "\(text) ago"
    }

    public static func points(_ value: Double?) -> String {
        guard let value else { return "—" }
        guard abs(value) < 1e15 else { return String(format: "%.0f", value) }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    public static func percent(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f%%", value)
    }
}
