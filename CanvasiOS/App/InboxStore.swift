import Foundation
import Observation
import ThubanCanvasCore
@preconcurrency import UserNotifications

/// Canvas conversation mailboxes the Inbox tab shows.
enum MailScope: String, CaseIterable, Hashable {
    case inbox, unread, starred, sent, archived

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var apiScope: String? { self == .inbox ? nil : rawValue }
}

/// Read-only inbox: one cache-first list per mailbox and full threads fetched with `auto_mark_as_read=false`, so
/// opening a message on the phone never changes anything in Canvas.
@MainActor
@Observable
final class InboxStore {
    private(set) var lists: [MailScope: Resource<[Conversation]>] = [:]
    private(set) var threads: [CanvasID: Conversation] = [:]
    private(set) var threadErrors: [CanvasID: String] = [:]

    func resource(_ scope: MailScope) -> Resource<[Conversation]> {
        if let existing = lists[scope] { return existing }
        let created = Resource<[Conversation]>(key: "inbox/\(scope.rawValue)", ttl: 180)
        lists[scope] = created
        return created
    }

    func load(_ scope: MailScope, app: AppModel, force: Bool = false) async {
        let api = scope.apiScope
        await resource(scope).load(app: app, force: force) { try await $0.conversations(scope: api) }
        await app.refreshUnreadCount()
    }

    func loadThread(_ id: CanvasID, app: AppModel, force: Bool = false) async {
        guard force || threads[id] == nil, let client = app.client else { return }
        do {
            threads[id] = try await client.conversation(id, markAsRead: false)
            threadErrors[id] = nil
        } catch let error as ThubanError {
            if case .unauthorized = error { app.noteUnauthorized() }
            threadErrors[id] = error.localizedDescription
        } catch {
            threadErrors[id] = error.localizedDescription
        }
    }

    /// The list row for an id from any loaded mailbox.
    func summary(_ id: CanvasID) -> Conversation? {
        for resource in lists.values {
            if let hit = resource.value?.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }
}

/// Local due-date reminders (no push, no widgets). Scheduled from cached assignments whenever data or the
/// reminder settings change; requires the user's permission, asked only from Settings → Due-date reminders.
@MainActor
enum Reminders {
    nonisolated static let prefix = "thuban-canvas-due-"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    static func reschedule(app: AppModel) {
        guard !app.demoMode else { return }
        let preferences = app.settings.notifications
        let items = WorkItemBuilder.upcoming(app.allWorkItems, within: 14)
        let names = Dictionary(uniqueKeysWithValues: app.orderedSessions.map { ($0.id, $0.shortTitle) })
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            guard preferences.enabled, status == .authorized || status == .provisional else { return }
            var scheduled = 0
            for item in items {
                guard let due = item.dueAt else { continue }
                for hours in preferences.leadHours.sorted(by: >) where hours > 0 {
                    let fire = due.addingTimeInterval(-Double(hours) * 3_600)
                    guard fire > Date().addingTimeInterval(60), scheduled < 60 else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = item.title
                    let course = item.courseId.flatMap { names[$0] } ?? item.courseName
                    content.body = "\(course) · due \(DueFormatter.compact(due))"
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSinceNow, repeats: false)
                    let request = UNNotificationRequest(identifier: "\(prefix)\(item.id)-\(hours)", content: content, trigger: trigger)
                    try? await center.add(request)
                    scheduled += 1
                }
            }
        }
    }
}
