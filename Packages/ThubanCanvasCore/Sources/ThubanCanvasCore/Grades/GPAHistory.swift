import Foundation

/// One day's record of the GPA and every counted course's score (Canvas's own current score, never what-if).
public struct GPASnapshot: Codable, Equatable, Identifiable, Sendable {
    /// Local calendar day, "yyyy-MM-dd" — at most one snapshot per day (the latest of the day wins).
    public var day: String
    public var recordedAt: Date
    public var termName: String?
    public var term: Double?
    public var cumulative: Double?
    public var termCredits: Double
    /// Course id → current score (percent).
    public var scores: [CanvasID: Double]
    /// Course id → name at the time, so the graph can label courses that are no longer starred.
    public var names: [CanvasID: String]

    public var id: String { day }

    public init(day: String, recordedAt: Date, termName: String?, term: Double?, cumulative: Double?, termCredits: Double,
                scores: [CanvasID: Double], names: [CanvasID: String]) {
        self.day = day
        self.recordedAt = recordedAt
        self.termName = termName
        self.term = term
        self.cumulative = cumulative
        self.termCredits = termCredits
        self.scores = scores
        self.names = names
    }

    /// Noon of `day` in the current time zone (stable x position for a chart).
    public var date: Date {
        GPAHistory.dayFormatter.date(from: day).map { Calendar.current.date(byAdding: .hour, value: 12, to: $0) ?? $0 } ?? recordedAt
    }
}

/// The daily GPA log in `gpa-history.json` under the app home.
public enum GPAHistory {
    public static var fileURL: URL { AppPaths.home.appendingPathComponent("gpa-history.json") }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func day(for date: Date) -> String { dayFormatter.string(from: date) }

    public static func load() -> [GPASnapshot] {
        ((try? JSONFile.read([GPASnapshot].self, from: fileURL)) ?? nil)?.sorted { $0.day < $1.day } ?? []
    }

    public static func save(_ snapshots: [GPASnapshot]) {
        try? AppPaths.ensureDirectories()
        try? JSONFile.write(snapshots, to: fileURL)
    }

    /// Inserts `snapshot`, replacing any earlier one from the same day. Returns the sorted log.
    public static func recording(_ snapshot: GPASnapshot, into log: [GPASnapshot]) -> [GPASnapshot] {
        var next = log.filter { $0.day != snapshot.day }
        next.append(snapshot)
        return next.sorted { $0.day < $1.day }
    }
}
