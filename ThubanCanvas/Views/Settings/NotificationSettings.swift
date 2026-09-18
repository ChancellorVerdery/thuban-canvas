import SwiftUI
import ThubanCanvasCore
import UserNotifications

/// Notifications pane: due-date reminders and their lead times, the macOS permission state, the extra alerts
/// (announcements, grades, inbox) and the menu bar item. Every control binds through `app.settings`, which persists.
struct NotificationSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    private let status = NotificationScheduler.status

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Reminders", caption: "A notification before each due date, for anything worth points or handed in through Canvas. Items without a due date are skipped.") {
                SettingsRow("Due-date reminders", detail: reminderDetail) {
                    ThubanToggle(isOn: binding(\.enabled), label: "Due-date reminders")
                }
                SettingsRow("Remind me before", detail: leadDetail) {
                    HStack(spacing: 6) {
                        ForEach(NotificationScheduler.leadChoices, id: \.self) { hours in
                            LeadChip(hours: hours, isOn: app.settings.notifications.leadHours.contains(hours)) { toggleLead(hours) }
                        }
                    }
                }
                .disabled(!app.settings.notifications.enabled)
                .opacity(app.settings.notifications.enabled ? 1 : 0.55)
                SettingsRow("Overdue digest", detail: "One notification at 8:00 each morning listing everything overdue, while anything is.") {
                    Chip(digestLabel, kind: status.digestScheduled ? .accent : .neutral)
                }
            }

            SettingsGroup("macOS permission", caption: "Reminders are delivered by macOS. Thuban Canvas asks once, the first time a reminder is scheduled.") {
                SettingsRow(permissionLabel, detail: permissionDetail) {
                    HStack(spacing: 8) {
                        if status.isAuthorized {
                            Chip("Allowed", kind: .pos, dot: true)
                            Button("System Settings") { NotificationScheduler.openSystemSettings() }
                                .buttonStyle(.thubanGhost)
                                .accessibilityLabel("Open Notifications in System Settings")
                        } else if status.isDenied {
                            Button("Open System Settings") { NotificationScheduler.openSystemSettings() }
                                .buttonStyle(.thubanSecondary)
                                .accessibilityLabel("Open Notifications in System Settings")
                        } else {
                            Button("Allow notifications") { Task { await NotificationScheduler.requestAuthorization() } }
                                .buttonStyle(.thubanSecondary)
                        }
                    }
                }
                SettingsRow("Preview", detail: "Sends a sample reminder a second from now, so you can see how one looks.") {
                    Button("Send test notification") { NotificationScheduler.sendTest() }
                        .buttonStyle(.thubanSecondary)
                        .disabled(status.isDenied)
                }
                if let error = status.lastError {
                    SettingsNote(text: error, tone: .negative)
                }
            }

            SettingsGroup("Also notify about", caption: "Compared against the last refresh (every \(app.settings.refreshMinutes) min while the app runs).") {
                SettingsRow("New announcements", detail: "One alert per announcement posted since the last check, across starred courses.") {
                    ThubanToggle(isOn: binding(\.announcements), label: "New announcements")
                }
                SettingsRow("New grades", detail: "When an assignment is graded and the score is visible to you.") {
                    ThubanToggle(isOn: binding(\.grades), label: "New grades")
                }
                SettingsRow("Inbox", detail: "When the unread count in Canvas Inbox goes up.") {
                    ThubanToggle(isOn: binding(\.inbox), label: "Inbox")
                }
            }
            .disabled(!app.settings.notifications.enabled)
            .opacity(app.settings.notifications.enabled ? 1 : 0.55)

            SettingsGroup("Menu bar", caption: "The Thuban mark in the menu bar shows how many items are due today and lists what is due next, what is overdue and every course's grade.") {
                SettingsRow("Show in the menu bar") {
                    ThubanToggle(isOn: Binding(
                        get: { app.settings.menuBarEnabled },
                        set: { app.settings.menuBarEnabled = $0; MenuBarController.shared.rebuild() }
                    ), label: "Show in the menu bar")
                }
                SettingsNote(text: "Calendar and Inbox open from anywhere in the app with ⌘K and ⌘I; ⌘1 is Home and ⌘2–⌘9 are your courses.")
            }
        }
        .task { await NotificationScheduler.refreshAuthorization() }
    }

    // MARK: Copy

    private var reminderDetail: String {
        guard app.settings.notifications.enabled else { return "Off. Nothing is scheduled." }
        let count = status.pendingReminders
        var text = count == 0 ? "Nothing scheduled yet." : (count == 1 ? "1 reminder scheduled" : "\(count) reminders scheduled")
        if let next = status.nextReminderAt { text += " · next \(DueFormatter.relative(next))" }
        return text
    }

    private var leadDetail: String {
        let hours = app.settings.notifications.leadHours.sorted()
        if hours.isEmpty { return "Pick at least one lead time." }
        return hours.map { $0 == 1 ? "1 hour" : "\($0) hours" }.joined(separator: ", ") + " before the due date."
    }

    private var digestLabel: String {
        guard app.settings.notifications.enabled else { return "Off" }
        return status.digestScheduled ? "Queued for 8:00" : "Nothing overdue"
    }

    private var permissionLabel: String {
        switch status.authorization {
        case .authorized, .provisional, .ephemeral: return "Notifications allowed"
        case .denied: return "Notifications are off in System Settings"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Notifications"
        }
    }

    private var permissionDetail: String {
        switch status.authorization {
        case .authorized, .provisional, .ephemeral: return "Banners, sounds and the Dock badge are on for Thuban Canvas."
        case .denied: return "Turn on Thuban Canvas under Notifications to receive reminders."
        case .notDetermined: return "macOS will ask when the first reminder is scheduled, or right now."
        @unknown default: return ""
        }
    }

    // MARK: Bindings

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.settings.notifications[keyPath: keyPath] },
            set: { app.settings.notifications[keyPath: keyPath] = $0; NotificationScheduler.reschedule(reason: .settings) }
        )
    }

    private func toggleLead(_ hours: Int) {
        var lead = Set(app.settings.notifications.leadHours)
        if lead.contains(hours) { lead.remove(hours) } else { lead.insert(hours) }
        app.settings.notifications.leadHours = lead.sorted()
        NotificationScheduler.reschedule(reason: .settings)
    }
}

/// One selectable lead time ("24 h"): accent chip when on, neutral when off.
private struct LeadChip: View {
    @Environment(\.thubanTheme) private var theme
    var hours: Int
    var isOn: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(hours) h")
                .monospacedDigit()
                .thubanChip(kind: isOn ? .accent : .neutral)
                .opacity(hovering && !isOn ? 0.8 : 1)
                .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(hours == 1 ? "1 hour before" : "\(hours) hours before")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .help(hours == 1 ? "Remind 1 hour before" : "Remind \(hours) hours before")
    }
}
