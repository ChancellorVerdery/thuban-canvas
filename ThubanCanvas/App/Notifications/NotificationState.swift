import Foundation
import ThubanCanvasCore

/// What the last full refresh saw, so "new since last check" alerts (announcements, grades, inbox) can be derived
/// by comparing ids and scores across refreshes. Persisted in `notification-state.json` next to settings.
///
/// Each source is only compared once it has been recorded at least once (`announcementsRecorded`,
/// `recordedCourses`, `inboxRecorded`), so the first sighting of a feed never fires a burst of alerts.
struct NotificationState: Codable, Equatable {
    /// Announcement ids already seen (notified about, or present when first recorded). Never shrinks.
    var seenAnnouncements: Set<CanvasID> = []
    var announcementsRecorded = false
    /// Assignment id → score the student had last time; a graded item absent here is newly graded. Never shrinks.
    var gradedScores: [CanvasID: Double] = [:]
    /// Courses whose graded work has been recorded at least once.
    var recordedCourses: Set<CanvasID> = []
    /// Unread inbox count at the last check.
    var unreadInbox: Int = 0
    var inboxRecorded = false
    var lastCheck: Date?

    static var file: URL { AppPaths.home.appendingPathComponent("notification-state.json") }

    static func load() -> NotificationState {
        (try? JSONFile.read(NotificationState.self, from: file)) ?? NotificationState()
    }

    func save() {
        try? JSONFile.write(self, to: Self.file)
    }
}
