import Foundation
import Observation
import UserNotifications

/// What the Notifications settings pane reads: the macOS authorization state and a summary of what is scheduled.
/// Owned by `NotificationScheduler`; views observe it and never write to it.
@MainActor
@Observable
final class NotificationStatus {
    /// Last known `UNAuthorizationStatus` (refreshed after every request and schedule pass).
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Whether the app has asked macOS this launch (the prompt itself only ever shows once per install).
    private(set) var hasRequested = false
    /// Pending due-date reminders after the last schedule pass.
    private(set) var pendingReminders = 0
    /// When the soonest pending reminder fires, if any.
    private(set) var nextReminderAt: Date?
    /// Whether an overdue digest is queued for the next 8:00.
    private(set) var digestScheduled = false
    /// Last failure from the notification center (adding a request, requesting authorization).
    private(set) var lastError: String?

    var isAuthorized: Bool { authorization == .authorized || authorization == .provisional }
    var isDenied: Bool { authorization == .denied }

    func update(authorization: UNAuthorizationStatus) { self.authorization = authorization }
    func markRequested() { hasRequested = true }
    func update(pendingReminders: Int, nextReminderAt: Date?, digestScheduled: Bool) {
        self.pendingReminders = pendingReminders
        self.nextReminderAt = nextReminderAt
        self.digestScheduled = digestScheduled
    }
    func note(error: String?) { lastError = error }
}
