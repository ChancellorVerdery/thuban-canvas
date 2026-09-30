import SwiftUI
import ThubanCanvasCore

@main
struct ThubanCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appModel = AppModel.shared

    var body: some Scene {
        WindowGroup("Thuban Canvas") {
            ShellView()
                .environment(appModel)
                .frame(minWidth: 1100, minHeight: 700)
                .task { await appModel.load() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Button("Find…") { appModel.findRequest += 1 }
                    .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                SettingsCommandButton().environment(appModel)
            }
            CommandMenu("Canvas") {
                Button("Refresh") { Task { await appModel.refreshAll() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Home") { appModel.select(.home) }
                    .keyboardShortcut("1", modifiers: .command)
                ForEach(Array(appModel.orderedSessions.prefix(8).enumerated()), id: \.element.id) { index, session in
                    Button(session.displayName) { appModel.select(.course(session.id)) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 2))), modifiers: .command)
                }
                Divider()
                Button("Calendar") { appModel.panel = appModel.panel == .calendar ? nil : .calendar }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Inbox") { appModel.panel = appModel.panel == .inbox ? nil : .inbox }
                    .keyboardShortcut("i", modifiers: .command)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(appModel)
                .frame(minWidth: 780, minHeight: 580)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 660)
    }
}

/// "Settings… ⌘," — lives in the App menu; opens the Settings window scene.
private struct SettingsCommandButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") { openWindow(id: "settings") }
            .keyboardShortcut(",", modifiers: .command)
    }
}

/// Starts the model without waiting for a window (so the menu bar item works at login) and implements the
/// menu-bar-resident lifecycle in `MenuBarResidency`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { MenuBarResidency.shared.willFinishLaunching() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            MenuBarResidency.shared.didFinishLaunching()
            Task { await AppModel.shared.load() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening the app again while it lives in the menu bar: bring the Dock icon back; SwiftUI reopens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { MenuBarResidency.shared.showInDock() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { MenuBarResidency.shared.shouldTerminate() }
    }
}
