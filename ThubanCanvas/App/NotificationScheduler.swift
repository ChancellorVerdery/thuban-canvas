import AppKit
import Foundation
import ThubanCanvasCore
import UserNotifications
import os

/// Due-date reminders through `UNUserNotificationCenter`, plus the 8:00 overdue digest, the Dock badge and
/// "new since last check" alerts for announcements, grades and inbox.
///
/// Runs a schedule pass after every `refreshAll` (`.thubanDataRefreshed`) and on a 60 s tick whenever the inputs
/// (settings, work items, announcements, inbox count) changed. Authorization is requested lazily — only once
/// reminders are on and a course is loaded — and never under the smoke harness. Everything here is read-only
/// with respect to Canvas.
@MainActor
enum NotificationScheduler {
    static let status = NotificationStatus()
    private static let logger = Logger(subsystem: "com.thuban.canvas", category: "notifications")
    private static let center = UNUserNotificationCenter.current()

    static let reminderPrefix = "due-"
    static let digestIdentifier = "overdue-digest"
    /// Most pending reminders kept at once (soonest first). macOS itself caps pending requests at 64.
    static let reminderCap = 60
    static let leadChoices = [1, 2, 6, 12, 24, 48]

    private static weak var app: AppModel?
    private static var observer: NSObjectProtocol?
    private static var timer: Timer?
    private static var lastFingerprint: String?
    private static var isScheduling = false
    private static var pendingRun: Reason?
    /// identifier → content key of what was last handed to the center, so unchanged reminders are not re-added.
    private static var scheduledKeys: [String: String] = [:]

    /// Why a pass runs. Only a full refresh compares announcements, grades and inbox: that is when every feed is
    /// guaranteed to have been fetched, so a half-loaded state never reads as "new".
    enum Reason { case tick, refresh, settings }

    // MARK: Configuration

    /// Called once from `AppModel.load()`.
    static func configure(app model: AppModel) {
        app = model
        center.delegate = NotificationDelegate.shared
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .thubanDataRefreshed, object: nil, queue: .main) { _ in
                Task { @MainActor in reschedule(reason: .refresh) }
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in reschedule() }
        }
        Task { await refreshAuthorization() }
        guard !SmokeHarness.isEnabled else { return }
        Task {
            // Home normally loads the assignment groups; make sure they arrive even when it has not been shown.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let app, app.client != nil, !app.courses.isEmpty, app.orderedSessions.allSatisfy({ !$0.groups.hasValue }) else { return }
            await app.loadHomeResources()
            reschedule(reason: .settings)
        }
    }

    /// Runs a schedule pass. A `.tick` only works when the inputs changed; the other reasons always run.
    static func reschedule(reason: Reason = .tick) {
        guard let app else { return }
        let fingerprint = fingerprint(app)
        guard reason != .tick || fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        if isScheduling {
            if pendingRun != .refresh { pendingRun = reason == .tick ? .settings : reason }
            return
        }
        isScheduling = true
        Task {
            await runPass(app: app, reason: reason)
            isScheduling = false
            if let queued = pendingRun { pendingRun = nil; reschedule(reason: queued) }
        }
    }

    // MARK: Authorization

    /// Asks macOS once (alert, sound, badge). Called lazily by the schedule pass and by the settings pane.
    static func requestAuthorization() async {
        guard !SmokeHarness.isEnabled else { return }
        status.markRequested()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            status.note(error: nil)
        } catch {
            status.note(error: error.localizedDescription)
            logger.error("authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshAuthorization()
    }

    static func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        status.update(authorization: settings.authorizationStatus)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Test

    /// Delivers a sample reminder a second from now (Settings → "Send test notification").
    static func sendTest() {
        Task {
            if status.authorization == .notDetermined { await requestAuthorization() }
            let content = UNMutableNotificationContent()
            let sample = app?.orderedSessions.first?.tabTitle ?? "Calc III"
            content.title = "\(sample) · due in 2 h"
            content.body = "Problem Set 4 · \(DueFormatter.relative(Date().addingTimeInterval(7_200)))"
            content.sound = .default
            content.userInfo = [NotificationDelegate.Key.kind: NotificationDelegate.Kind.test.rawValue]
            let request = UNNotificationRequest(identifier: "test-\(Int(Date().timeIntervalSince1970))", content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            do {
                try await center.add(request)
                status.note(error: nil)
            } catch {
                status.note(error: error.localizedDescription)
            }
        }
    }

    // MARK: Activation

    /// A notification was clicked: bring the app forward and open what it was about.
    static func handleActivation(kind: NotificationDelegate.Kind, courseId: CanvasID?, assignmentId: CanvasID?, topicId: CanvasID?) {
        guard let app else { return }
        app.bringToFront()
        switch kind {
        case .reminder, .grade:
            if let courseId, let assignmentId { app.open(course: courseId, section: .assignments, route: .assignment(assignmentId)) }
            else { app.select(.home) }
        case .announcement:
            if let courseId, let topicId { app.open(course: courseId, section: .announcements, route: .discussion(topicId)) }
            else if let courseId { app.open(course: courseId, section: .announcements) }
        case .inbox:
            app.panel = .inbox
        case .digest, .test:
            app.select(.home)
        }
    }

    // MARK: Schedule pass

    private static func runPass(app: AppModel, reason: Reason) async {
        let preferences = app.settings.notifications
        let items = app.allWorkItems
        let overdue = WorkItemBuilder.overdue(items, dismissed: app.settings.dismissedOverdue)
        applyBadge(count: preferences.enabled ? overdue.count : 0)
        guard !SmokeHarness.isEnabled else { return }

        guard preferences.enabled else {
            await removeAllOurs()
            status.update(pendingReminders: 0, nextReminderAt: nil, digestScheduled: false)
            return
        }
        guard !app.courses.isEmpty else { return }
        if status.authorization == .notDetermined, !status.hasRequested { await requestAuthorization() }
        else { await refreshAuthorization() }
        guard !status.isDenied else {
            // Nothing can be delivered; keep the queue empty rather than failing every add.
            await removeAllOurs()
            status.update(pendingReminders: 0, nextReminderAt: nil, digestScheduled: false)
            return
        }

        let now = Date()
        var desired = reminders(for: items, leadHours: preferences.leadHours, now: now)
        if let digest = digest(for: overdue, now: now) { desired.append(digest) }

        let pending = await center.pendingNotificationRequests()
        let wanted = Set(desired.map(\.request.identifier))
        let stale = pending.map(\.identifier).filter { isOurs($0) && !wanted.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for id in scheduledKeys.keys where !wanted.contains(id) { scheduledKeys[id] = nil }

        let pendingIds = Set(pending.map(\.identifier))
        var failure: String?
        for planned in desired where scheduledKeys[planned.request.identifier] != planned.key || !pendingIds.contains(planned.request.identifier) {
            do {
                try await center.add(planned.request)
                scheduledKeys[planned.request.identifier] = planned.key
            } catch {
                failure = error.localizedDescription
            }
        }
        if let failure { logger.error("scheduling failed: \(failure, privacy: .public)") }
        status.note(error: failure)

        let reminderDates = desired.filter { $0.request.identifier.hasPrefix(reminderPrefix) }.map(\.fireAt)
        status.update(pendingReminders: reminderDates.count, nextReminderAt: reminderDates.min(),
                      digestScheduled: desired.contains { $0.request.identifier == digestIdentifier })

        if reason == .refresh { await deliverAlerts(app: app, items: items, preferences: preferences) }
    }

    private struct Planned {
        var request: UNNotificationRequest
        var fireAt: Date
        /// Content + trigger digest; a changed key means the request must be re-added.
        var key: String
    }

    /// One request per (upcoming, gradable or submittable) item and lead time whose fire date is still ahead.
    private static func reminders(for items: [WorkItem], leadHours: [Int], now: Date) -> [Planned] {
        var planned: [Planned] = []
        for item in items {
            guard item.status == .upcoming, let due = item.dueAt, let assignmentId = item.assignmentId ?? item.quizId else { continue }
            guard (item.pointsPossible ?? 0) > 0 || item.acceptsOnlineSubmission else { continue }
            for lead in Set(leadHours).sorted() where lead > 0 {
                let fireAt = due.addingTimeInterval(-Double(lead) * 3_600)
                guard fireAt > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(item.courseName) · due in \(lead) h"
                content.body = "\(item.title) · \(DueFormatter.relative(due, now: fireAt))"
                content.sound = .default
                content.threadIdentifier = "course-\(item.courseId ?? 0)"
                content.userInfo = [
                    NotificationDelegate.Key.kind: NotificationDelegate.Kind.reminder.rawValue,
                    NotificationDelegate.Key.courseId: item.courseId ?? 0,
                    NotificationDelegate.Key.assignmentId: assignmentId,
                ]
                let trigger = UNCalendarNotificationTrigger(dateMatching: components(for: fireAt), repeats: false)
                let request = UNNotificationRequest(identifier: "\(reminderPrefix)\(assignmentId)-\(lead)", content: content, trigger: trigger)
                planned.append(Planned(request: request, fireAt: fireAt, key: "\(Int(fireAt.timeIntervalSince1970))|\(content.title)|\(content.body)"))
            }
        }
        return Array(planned.sorted { $0.fireAt < $1.fireAt }.prefix(reminderCap))
    }

    /// The overdue list at the next 8:00 local, when anything is overdue.
    private static func digest(for overdue: [WorkItem], now: Date) -> Planned? {
        guard !overdue.isEmpty else { return nil }
        let calendar = Calendar.current
        var eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        if eight <= now { eight = calendar.date(byAdding: .day, value: 1, to: eight) ?? eight }
        let content = UNMutableNotificationContent()
        content.title = overdue.count == 1 ? "1 item overdue" : "\(overdue.count) items overdue"
        let lines = overdue.prefix(4).map { "\($0.courseName) · \($0.title)" }
        let rest = overdue.count - lines.count
        content.body = (lines + (rest > 0 ? ["and \(rest) more"] : [])).joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = "digest"
        content.userInfo = [NotificationDelegate.Key.kind: NotificationDelegate.Kind.digest.rawValue]
        let trigger = UNCalendarNotificationTrigger(dateMatching: components(for: eight), repeats: false)
        let request = UNNotificationRequest(identifier: digestIdentifier, content: content, trigger: trigger)
        return Planned(request: request, fireAt: eight, key: "\(Int(eight.timeIntervalSince1970))|\(content.title)|\(content.body)")
    }

    private static func components(for date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    private static func isOurs(_ identifier: String) -> Bool {
        identifier.hasPrefix(reminderPrefix) || identifier == digestIdentifier
    }

    private static func removeAllOurs() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(isOurs)
        if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending) }
        scheduledKeys = [:]
    }

    private static func applyBadge(count: Int) {
        let label = count > 0 ? String(count) : nil
        if NSApplication.shared.dockTile.badgeLabel != label { NSApplication.shared.dockTile.badgeLabel = label }
    }

    // MARK: New-since-last-check alerts

    /// After a full refresh: compares announcements, graded scores and the unread count with the persisted state.
    /// A feed is only compared once it has been recorded before; the first sighting just records it.
    private static func deliverAlerts(app: AppModel, items: [WorkItem], preferences: NotificationPreferences) async {
        let previous = NotificationState.load()
        var next = previous
        next.lastCheck = Date()
        var alerts: [UNNotificationRequest] = []

        if app.announcements.hasValue {
            let announcements = app.announcements.value ?? []
            let fresh = announcements.filter { !previous.seenAnnouncements.contains($0.id) }
                .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            next.seenAnnouncements.formUnion(announcements.map(\.id))
            if previous.announcementsRecorded, preferences.announcements {
                for topic in fresh.prefix(5) {
                    let course = topic.courseId.flatMap { app.sessions[$0]?.tabTitle } ?? "Canvas"
                    let content = UNMutableNotificationContent()
                    content.title = "\(course) · New announcement"
                    content.body = topic.title
                    content.sound = .default
                    content.threadIdentifier = "course-\(topic.courseId ?? 0)"
                    content.userInfo = [
                        NotificationDelegate.Key.kind: NotificationDelegate.Kind.announcement.rawValue,
                        NotificationDelegate.Key.courseId: topic.courseId ?? 0,
                        NotificationDelegate.Key.topicId: topic.id,
                    ]
                    alerts.append(UNNotificationRequest(identifier: "announcement-\(topic.id)", content: content, trigger: nil))
                }
            }
            next.announcementsRecorded = true
        }

        let loadedCourses = Set(app.orderedSessions.filter { $0.groups.hasValue }.map(\.id))
        let graded = items.filter { $0.status == .graded && $0.score != nil && $0.courseId.map(loadedCourses.contains) == true }
        let recentCutoff = Date().addingTimeInterval(-3 * 86_400)
        let fresh = graded.filter { item in
            guard let id = item.assignmentId, let courseId = item.courseId else { return false }
            guard previous.recordedCourses.contains(courseId), previous.gradedScores[id] == nil else { return false }
            // Skip grades that were posted long ago and only now became visible (e.g. a newly starred course).
            if let gradedAt = app.sessions[courseId]?.assignment(id)?.submission?.gradedAt, gradedAt < recentCutoff { return false }
            return true
        }
        for item in graded { if let id = item.assignmentId { next.gradedScores[id] = item.score ?? 0 } }
        next.recordedCourses.formUnion(loadedCourses)
        if preferences.grades {
            for item in fresh.prefix(5) {
                let content = UNMutableNotificationContent()
                content.title = "\(item.courseName) · Graded"
                content.body = "\(item.title) · \(DueFormatter.points(item.score)) / \(DueFormatter.points(item.pointsPossible))"
                content.sound = .default
                content.threadIdentifier = "course-\(item.courseId ?? 0)"
                content.userInfo = [
                    NotificationDelegate.Key.kind: NotificationDelegate.Kind.grade.rawValue,
                    NotificationDelegate.Key.courseId: item.courseId ?? 0,
                    NotificationDelegate.Key.assignmentId: item.assignmentId ?? 0,
                ]
                alerts.append(UNNotificationRequest(identifier: "grade-\(item.assignmentId ?? 0)", content: content, trigger: nil))
            }
        }

        if app.client != nil {
            if previous.inboxRecorded, preferences.inbox, app.unreadInbox > previous.unreadInbox {
                let added = app.unreadInbox - previous.unreadInbox
                let content = UNMutableNotificationContent()
                content.title = added == 1 ? "New message" : "\(added) new messages"
                content.body = app.unreadInbox == 1 ? "1 unread in Inbox" : "\(app.unreadInbox) unread in Inbox"
                content.sound = .default
                content.threadIdentifier = "inbox"
                content.userInfo = [NotificationDelegate.Key.kind: NotificationDelegate.Kind.inbox.rawValue]
                alerts.append(UNNotificationRequest(identifier: "inbox-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil))
            }
            next.unreadInbox = app.unreadInbox
            next.inboxRecorded = true
        }

        if next != previous { next.save() }
        for request in alerts {
            do { try await center.add(request) } catch { logger.error("alert failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: Fingerprint

    /// Cheap digest of everything a pass depends on, so the 60 s tick only works when something moved.
    private static func fingerprint(_ app: AppModel) -> String {
        var hasher = Hasher()
        let preferences = app.settings.notifications
        hasher.combine(preferences.enabled)
        hasher.combine(preferences.leadHours)
        hasher.combine(preferences.announcements)
        hasher.combine(preferences.grades)
        hasher.combine(preferences.inbox)
        hasher.combine(app.settings.dismissedOverdue)
        for item in app.allWorkItems {
            hasher.combine(item.id)
            hasher.combine(item.status.rawValue)
            hasher.combine(item.dueAt?.timeIntervalSince1970 ?? 0)
            hasher.combine(item.score ?? -1)
        }
        hasher.combine((app.announcements.value ?? []).map(\.id))
        hasher.combine(app.unreadInbox)
        return String(hasher.finalize())
    }
}

// MARK: - Activation helper

extension AppModel {
    /// Activates the app and brings the main window forward, reopening it if the user closed it.
    func bringToFront() {
        MenuBarResidency.shared.showInDock()
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.title != "Settings" && $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            _ = NSApplication.shared.delegate?.applicationShouldHandleReopen?(NSApplication.shared, hasVisibleWindows: false)
        }
    }
}
