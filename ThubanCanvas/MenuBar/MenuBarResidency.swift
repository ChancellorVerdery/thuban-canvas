import AppKit
import ThubanCanvasCore

/// Keeps Thuban Canvas alive as a menu bar item when its windows are closed.
///
/// - Closing the last window, or ⌘Q, hides the Dock icon and leaves the menu bar mark running (when
///   `settings.keepInMenuBar` and the menu bar item are on). "Quit Thuban Canvas" in the menu bar item really quits;
///   so do logout, restart and shutdown.
/// - Launched with `--background`, it starts with no window and no Dock icon, just the mark.
/// - Opening the app again (Finder, Spotlight, the menu bar's "Open") brings the Dock icon and window back.
@MainActor
final class MenuBarResidency {
    static let shared = MenuBarResidency()

    /// Set by "Quit Thuban Canvas" so `shouldTerminate` lets the quit through.
    private var quittingForReal = false
    private var launchedInBackground = false
    private var closeObserver: NSObjectProtocol?

    private var app: AppModel { AppModel.shared }

    /// Staying resident only makes sense while the menu bar item exists.
    var isResident: Bool { app.settings.menuBarEnabled && app.settings.keepInMenuBar && !SmokeHarness.isEnabled }

    // MARK: Launch

    func willFinishLaunching() {
        launchedInBackground = CommandLine.arguments.contains("--background")
        NSApplication.shared.setActivationPolicy(launchedInBackground ? .accessory : .regular)
    }

    func didFinishLaunching() {
        // A copy started directly (not through LaunchServices) hands over to one that is already running.
        let me = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: "com.thuban.canvas").first(where: { $0 != me }) {
            if !launchedInBackground { other.activate() }
            exit(0)
        }
        if launchedInBackground {
            // SwiftUI opens the main window on launch; a login start should show only the menu bar mark.
            DispatchQueue.main.async { self.closeMainWindows() }
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let closing = note.object as? NSWindow
            // After the close finishes, drop the Dock icon if nothing is left on screen.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.hideDockIfNoWindows(ignoring: closing) } }
        }
    }

    // MARK: Quit

    func shouldTerminate() -> NSApplication.TerminateReply {
        if quittingForReal || !isResident || Self.isSessionEnding { return .terminateNow }
        // ⌘Q: close the windows and keep the menu bar mark.
        closeMainWindows(includingSettings: true)
        hideFromDock()
        return .terminateCancel
    }

    func quitCompletely() {
        quittingForReal = true
        NSApplication.shared.terminate(nil)
    }

    /// Logout / restart / shutdown send a quit Apple event carrying a reason; those must always quit.
    private static var isSessionEnding: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEQuitApplication else { return false }
        return event.attributeDescriptor(forKeyword: kAEQuitReason) != nil
    }

    // MARK: Dock

    func showInDock() {
        if NSApplication.shared.activationPolicy() != .regular {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    private func hideFromDock() {
        guard isResident else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func hideDockIfNoWindows(ignoring closing: NSWindow?) {
        guard isResident, !quittingForReal else { return }
        let visible = NSApplication.shared.windows.filter { window in
            window !== closing && window.isVisible && window.canBecomeMain && !(window is NSPanel)
        }
        if visible.isEmpty { hideFromDock() }
    }

    private func closeMainWindows(includingSettings: Bool = false) {
        for window in NSApplication.shared.windows where window.canBecomeMain && !(window is NSPanel) {
            if !includingSettings && window.title == "Settings" { continue }
            window.close()
        }
    }
}
