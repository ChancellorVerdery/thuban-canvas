import SwiftUI
import ThubanCanvasCore

/// Host + token, connection status, and how starred courses map to tabs.
struct ConnectionSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var host = ""
    @State private var token = ""
    @State private var confirmDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Status") {
                HStack(spacing: 10) {
                    ConnectionChip()
                    if let user = app.user {
                        Text("\(user.name) · \(app.host.replacingOccurrences(of: "https://", with: ""))")
                            .font(ThubanFont.body(14))
                            .foregroundStyle(theme.inkDimColor)
                    } else if !app.host.isEmpty {
                        Text(app.host).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
                    }
                    Spacer()
                    if app.client != nil {
                        Button("Disconnect…") { confirmDisconnect = true }.buttonStyle(.thubanSecondary)
                    }
                }
                .padding(14)
                .thubanPanel(padding: 0)
                if let error = app.connectionError { SettingsNote(text: error, tone: .negative) }
            }

            SettingsGroup("Sending", caption: "When off, submit, reply, message, star and mark-read controls are hidden. Every send still asks first.") {
                HStack(spacing: 10) {
                    Text("Allow sending to Canvas").font(ThubanFont.body(14)).foregroundStyle(theme.inkColor)
                    Spacer()
                    ThubanToggle(isOn: Binding(get: { app.settings.writesEnabled }, set: { app.settings.writesEnabled = $0 }), label: "Allow sending to Canvas")
                }
                .padding(14)
                .thubanPanel(padding: 0)
            }

            SettingsGroup(app.client == nil ? "Connect" : "Replace token", caption: "Canvas → Account → Settings → + New Access Token. Tokens can expire; paste a new one here when the chip turns red.") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(label: "Canvas address", placeholder: "school.instructure.com", text: $host)
                    LabeledField(label: "Access token", placeholder: "1234~…", text: $token, secure: true)
                    HStack {
                        Button(app.isConnecting ? "Checking…" : "Save & test") { Task { await app.connect(host: host, token: token) } }
                            .buttonStyle(.thubanPrimary)
                            .disabled(app.isConnecting || host.isEmpty || token.isEmpty)
                        Spacer()
                    }
                    SettingsNote(text: "Stored in \(AppPaths.credentialsFile.path) with owner-only permissions. Not the Keychain, so launching never prompts.")
                }
                .padding(14)
                .thubanPanel(padding: 0)
            }

            SettingsGroup("Tabs", caption: "Only courses you star in Canvas (Courses → All Courses → ★) get a tab. Refresh after starring.") {
                VStack(alignment: .leading, spacing: 8) {
                    if app.orderedSessions.isEmpty {
                        SettingsNote(text: app.client == nil ? "Connect to see your starred courses." : "No starred courses yet.")
                    }
                    ForEach(app.orderedSessions) { session in
                        HStack(spacing: 10) {
                            CourseDot(tint: session.preferences.tint)
                            Text(session.displayName).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                            Text(session.shortCode).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                            Spacer()
                            Text(session.course.term?.name ?? "").font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .thubanPanel(padding: 0)
                    }
                    Button("Refresh courses") { Task { await app.loadCourses(force: true) } }
                        .buttonStyle(.thubanSecondary)
                        .disabled(app.client == nil)
                }
            }
        }
        .onAppear { host = app.host }
        .alert("Disconnect from Canvas?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { Task { await app.disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The token file and every cached page are deleted from this Mac. Nothing changes in Canvas.")
        }
    }
}
