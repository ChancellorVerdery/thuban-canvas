import AppKit
import SwiftUI
import ThubanCanvasCore

/// The menu bar item: the Thuban mark plus today's due count, and a menu with what is due next, what is overdue,
/// a grade line per course and the app commands. Read-only; every click lands somewhere in the main window.
///
/// Present whenever `settings.menuBarEnabled`; the setting is re-checked on every `.thubanDataRefreshed` and on a
/// 60 s tick (also what keeps "Today"/"Tomorrow" and the count honest as time passes).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private weak var app: AppModel?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private lazy var menu: NSMenu = {
        let menu = NSMenu(title: "Thuban Canvas")
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }()

    /// Called once from `AppModel.load()`.
    func configure(app model: AppModel) {
        app = model
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .thubanDataRefreshed, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rebuild() }
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        rebuild()
    }

    /// Adds or removes the status item to match the setting and refreshes its title.
    func rebuild() {
        guard let app else { return }
        guard app.settings.menuBarEnabled else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = menu
            item.button?.image = Self.markImage
            item.button?.imagePosition = .imageOnly
            statusItem = item
        }
        updateButton()
    }

    // MARK: Button

    private func updateButton() {
        guard let button = statusItem?.button, let app else { return }
        let dueToday = Self.dueToday(app.allWorkItems).count
        if dueToday > 0 {
            button.attributedTitle = NSAttributedString(string: String(dueToday), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .medium),
                .baselineOffset: 0.5,
            ])
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        let summary = dueToday == 0 ? "nothing due today" : (dueToday == 1 ? "1 item due today" : "\(dueToday) items due today")
        button.toolTip = "Thuban Canvas — \(summary)"
        button.setAccessibilityLabel("Thuban Canvas, \(summary)")
    }

    /// The app's mark as a 16 pt template image (tints with the menu bar; knockouts punch through).
    static let markImage: NSImage = {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            AppArt.draw(in: context, rect: rect) { role in
                role == .panelFill || role == .bgFill ? nil : NSColor.black.cgColor
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Thuban Canvas"
        return image
    }()

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app else { return }
        let items = app.allWorkItems
        let now = Date()
        let upcoming = Array(WorkItemBuilder.upcoming(items, now: now).prefix(6))
        let overdue = WorkItemBuilder.overdue(items, dismissed: app.settings.dismissedOverdue)

        menu.addItem(.sectionHeader(title: "Due next"))
        if upcoming.isEmpty {
            menu.addItem(disabled(app.courses.isEmpty ? "No starred courses" : "Nothing due"))
        }
        for item in upcoming {
            let due = item.dueAt.map { DueFormatter.relative($0, now: now) } ?? "No date"
            menu.addItem(workItem(item, title: "\(due) · \(Self.trim(item.title)) — \(Self.trim(item.courseName, to: 28))"))
        }

        if !overdue.isEmpty {
            menu.addItem(.sectionHeader(title: "Overdue (\(overdue.count))"))
            for item in overdue.prefix(6) {
                let due = item.dueAt.map { DueFormatter.relative($0, now: now) } ?? "No date"
                menu.addItem(workItem(item, title: "\(due) · \(Self.trim(item.title)) — \(Self.trim(item.courseName, to: 28))"))
            }
            if overdue.count > 6 { menu.addItem(disabled("and \(overdue.count - 6) more")) }
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Grades"))
        if app.orderedSessions.isEmpty { menu.addItem(disabled("No starred courses")) }
        for session in app.orderedSessions {
            let score = session.displayScore.map { DueFormatter.percent($0) } ?? "—"
            let letter = session.displayLetter.map { " \($0)" } ?? ""
            let item = NSMenuItem(title: "", action: #selector(openGrades(_:)), keyEquivalent: "")
            item.attributedTitle = Self.attributed("\(Self.trim(session.tabTitle, to: 32)) · \(score)\(letter)")
            item.target = self
            item.representedObject = session.id
            item.toolTip = session.displayName
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: app.isRefreshing ? "Refreshing…" : "Refresh", action: #selector(refresh(_:)), keyEquivalent: "")
        refresh.target = self
        refresh.isEnabled = !app.isRefreshing && app.client != nil
        menu.addItem(refresh)
        if let last = app.lastRefresh {
            menu.addItem(disabled("Updated \(DueFormatter.countdown(last, now: now))"))
        }
        let open = NSMenuItem(title: "Open Thuban Canvas", action: #selector(openApp(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Thuban Canvas", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func workItem(_ item: WorkItem, title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: "", action: #selector(openWorkItem(_:)), keyEquivalent: "")
        menuItem.attributedTitle = Self.attributed(title)
        menuItem.target = self
        menuItem.representedObject = item
        menuItem.toolTip = "\(item.title) — \(item.courseName)"
        return menuItem
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = Self.attributed(title)
        item.isEnabled = false
        return item
    }

    /// Menu-font title with tabular digits so times and percentages line up.
    private static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular),
        ])
    }

    private static func trim(_ text: String, to limit: Int = 44) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Upcoming items whose due date falls on the current local day.
    static func dueToday(_ items: [WorkItem], now: Date = Date(), calendar: Calendar = .current) -> [WorkItem] {
        items.filter { item in
            guard item.status == .upcoming, let due = item.dueAt else { return false }
            return calendar.isDate(due, inSameDayAs: now)
        }
    }

    // MARK: Actions

    @objc private func openWorkItem(_ sender: NSMenuItem) {
        guard let app, let item = sender.representedObject as? WorkItem, let courseId = item.courseId else { return }
        app.bringToFront()
        if let assignmentId = item.assignmentId {
            app.open(course: courseId, section: .assignments, route: .assignment(assignmentId))
        } else if let quizId = item.quizId {
            app.open(course: courseId, section: .assignments, route: .quiz(quizId))
        } else {
            app.open(course: courseId, section: .assignments)
        }
    }

    @objc private func openGrades(_ sender: NSMenuItem) {
        guard let app, let courseId = sender.representedObject as? CanvasID else { return }
        app.bringToFront()
        app.open(course: courseId, section: .grades)
    }

    @objc private func refresh(_ sender: NSMenuItem) {
        guard let app else { return }
        Task { await app.refreshAll() }
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        app?.bringToFront()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let app else { return }
        app.bringToFront()
        app.settingsRequest += 1
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
