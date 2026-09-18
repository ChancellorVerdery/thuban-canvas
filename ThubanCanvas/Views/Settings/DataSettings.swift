import SwiftUI
import ThubanCanvasCore

struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var cacheBytes = 0
    @State private var refreshMinutes = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Offline cache", caption: "Every page you open is kept so the app starts instantly and still reads without a network.") {
                SettingsRow("Cached data", detail: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)) {
                    Button("Clear cache") { Task { await app.cache.clear(); cacheBytes = await app.cache.byteCount() } }
                        .buttonStyle(.thubanSecondary)
                }
                SettingsRow("Background refresh", detail: "How often grades and due dates are re-fetched while the app runs.") {
                    Picker("", selection: Binding(get: { app.settings.refreshMinutes }, set: { app.settings.refreshMinutes = $0 })) {
                        Text("5 min").tag(5); Text("15 min").tag(15); Text("30 min").tag(30); Text("60 min").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
            SettingsGroup("Location") {
                SettingsRow("App data", detail: AppPaths.home.path) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.home]) }
                        .buttonStyle(.thubanSecondary)
                }
            }
        }
        .task { cacheBytes = await app.cache.byteCount() }
    }
}
