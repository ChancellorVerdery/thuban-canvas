import AppKit
import Foundation
import ThubanCanvasCore
import UserNotifications

/// Shows banners while the app is frontmost and routes clicks: a reminder opens its assignment, an announcement
/// opens it inside the course, an inbox alert opens Inbox, the overdue digest goes Home.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Keys stored in each request's `userInfo`.
    enum Key {
        static let kind = "kind"
        static let courseId = "courseId"
        static let assignmentId = "assignmentId"
        static let topicId = "topicId"
    }

    /// What a notification is about; decides where a click lands.
    enum Kind: String {
        case reminder, digest, announcement, grade, inbox, test
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { completionHandler(); return }
        let info = response.notification.request.content.userInfo
        let kind = (info[Key.kind] as? String).flatMap(Kind.init(rawValue:)) ?? .reminder
        let courseId = info[Key.courseId] as? Int
        let assignmentId = info[Key.assignmentId] as? Int
        let topicId = info[Key.topicId] as? Int
        Task { @MainActor in
            NotificationScheduler.handleActivation(kind: kind, courseId: courseId, assignmentId: assignmentId, topicId: topicId)
            completionHandler()
        }
    }
}
