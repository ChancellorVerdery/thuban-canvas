import SwiftUI
import ThubanCanvasCore
import UIKit
import UserNotifications

enum SettingsPage: Hashable {
    case connection, reminders, grades, cache, customScheme, pastSemesters
}

/// Settings, presented as a sheet from Home's gear: appearance (mode + the eight Atlas schemes + custom), text,
/// and the Canvas group (connection, reminders, grades & GPA, offline cache).
struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var path: [SettingsPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsRoot()
                .navigationDestination(for: SettingsPage.self) { page in
                    switch page {
                    case .connection: ConnectionSettings()
                    case .reminders: ReminderSettings()
                    case .grades: GradesSettings(path: $path)
                    case .cache: CacheSettings()
                    case .customScheme: CustomSchemeEditor()
                    case .pastSemesters: PastSemestersScreen(back: "Grades & GPA")
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bgColor)
        .presentationCornerRadius(12)
        .onAppear {
            if let page = app.settingsPage {
                path = page == .pastSemesters ? [.grades, .pastSemesters] : [page]
                app.settingsPage = nil
            }
        }
    }
}

private struct SettingsRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSMetrics.sectionGap) {
                AppearanceCard()
                textCard
                canvasGroup
                Text(footer).tFont(.footnote).foregroundStyle(theme.inkFaintColor).padding(.horizontal, 16)
            }
            .gutter()
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Settings").tFont(.bodyStrong).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    BarTextButton("Done") { app.showingSettings = false }
                }
                .padding(.trailing, 6)
            }
            .frame(height: 50)
            .padding(.top, 8)
            .background(theme.bgColor)
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var footer: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return "Thuban Canvas \(version) · Reads Canvas only; submitting and replying open Canvas in Safari. Settings stay on this device."
    }

    private var textCard: some View {
        @Bindable var app = app
        return Card {
            HStack(spacing: 12) {
                Text("Text size").tFont(.body).foregroundStyle(theme.inkColor)
                Spacer()
                sizeButton("A", size: 13, label: "Smaller text") { stepText(-1) }
                Text("\(Int((app.settings.textSize.scale * 100).rounded()))%").tFont(.mono(15)).foregroundStyle(theme.inkColor).frame(width: 48)
                    .accessibilityLabel("Text size \(app.settings.textSize.label)")
                sizeButton("A", size: 19, label: "Larger text") { stepText(1) }
            }
            .padding(.leading, 16).padding(.trailing, 14)
            .frame(minHeight: IOSMetrics.rowHeight)
            RowDivider()
            toggleRow("Dyslexia-friendly font", isOn: $app.settings.dyslexiaFont)
            RowDivider()
            toggleRow("Reduce motion", isOn: $app.settings.reduceMotion)
        }
    }

    private func stepText(_ direction: Int) {
        let all = TextSize.allCases
        guard let index = all.firstIndex(of: app.settings.textSize) else { return }
        let next = min(max(0, index + direction), all.count - 1)
        app.settings.textSize = all[next]
    }

    private func sizeButton(_ text: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: size, weight: .semibold)).foregroundStyle(theme.inkColor)
                .frame(width: 36, height: 36)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
        .accessibilityLabel(label)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).tFont(.body).foregroundStyle(theme.inkColor)
            Spacer()
            ThubanSwitch(isOn: isOn, label: title)
        }
        .padding(.leading, 16).padding(.trailing, 14)
        .frame(minHeight: IOSMetrics.rowHeight)
    }

    private var canvasGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Canvas")
            Card {
                NavigationLink(value: SettingsPage.connection) {
                    row("Connection", value: app.demoMode ? "Demo account" : app.hostLabel, dot: app.isConnected ? theme.signalColor : theme.negColor)
                }
                RowDivider()
                NavigationLink(value: SettingsPage.reminders) {
                    row("Due-date reminders", value: app.settings.notifications.enabled ? DueFormatter.leadTimes(app.settings.notifications.leadHours) : "Off")
                }
                RowDivider()
                NavigationLink(value: SettingsPage.grades) {
                    row("Grades & GPA", value: "\(PointsText.short(app.gpa.termCredits)) credits")
                }
                RowDivider()
                NavigationLink(value: SettingsPage.cache) {
                    row("Offline cache", value: CacheSettings.sizeText)
                }
            }
            .buttonStyle(RowPressStyle())
        }
    }

    private func row(_ title: String, value: String, dot: Color? = nil) -> some View {
        HStack(spacing: 12) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(title).tFont(.body).foregroundStyle(theme.inkColor)
            Spacer(minLength: 8)
            Text(value).tFont(.secondary).foregroundStyle(theme.inkDimColor).lineLimit(1)
            RowChevron()
        }
        .padding(.leading, 16).padding(.trailing, 14)
        .frame(minHeight: IOSMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

/// Mode segmented control, the eight Atlas presets + Custom, and a live preview strip.
struct AppearanceCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Appearance")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Segmented(options: [(AppearanceMode.auto, "Automatic"), (.light, "Light"), (.dark, "Dark")],
                              selection: Binding(get: { app.settings.theme.mode }, set: { app.setAppearanceMode($0) }), stretch: true)
                        .accessibilityLabel("Mode")
                    HStack(alignment: .firstTextBaseline) {
                        Text("Color scheme").tFont(.text(15, .semibold)).foregroundStyle(theme.inkColor)
                        Spacer()
                        Text("Atlas presets").tFont(.footnote).foregroundStyle(theme.inkDimColor)
                    }
                    .padding(.horizontal, 2).padding(.top, 14).padding(.bottom, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(SchemePresets.all) { scheme in tile(scheme) }
                        customTile
                    }
                    preview.padding(.top, 12)
                }
                .padding(12)
            }
        }
    }

    private func tile(_ scheme: ThubanScheme) -> some View {
        let selected = app.settings.theme.schemeId == scheme.id
        return Button { app.selectScheme(id: scheme.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                SchemeSwatch(scheme: scheme, dark: theme.isDark)
                Text(scheme.label).tFont(.text(13, .semibold)).foregroundStyle(theme.inkColor).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? theme.accentColor : theme.lineColor, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
        .accessibilityLabel("\(scheme.label) color scheme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var customTile: some View {
        let selected = app.settings.theme.usesCustom
        NavigationLink(value: SettingsPage.customScheme) {
            Group {
                if selected, let custom = app.settings.theme.custom {
                    VStack(alignment: .leading, spacing: 6) {
                        SchemeSwatch(scheme: custom, dark: theme.isDark)
                        Text("Custom").tFont(.text(13, .semibold)).foregroundStyle(theme.inkColor)
                    }
                    .padding(8)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                        Text("Custom").tFont(.text(13, .semibold))
                    }
                    .foregroundStyle(theme.inkDimColor)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: selected ? .leading : .center)
            .background(selected ? theme.panelColor : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? theme.accentColor : theme.line2Color, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
        .accessibilityLabel(selected ? "Custom color scheme, edit" : "Make a custom scheme")
    }

    private var preview: some View {
        HStack(spacing: 10) {
            Text("Due tomorrow").tFont(.text(12.5, .semibold)).foregroundStyle(theme.brassInkColor)
                .padding(.horizontal, 8).frame(minHeight: 22)
                .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Circle().fill(theme.signalColor).frame(width: 8, height: 8)
            Spacer()
            Text("Primary").tFont(.text(14, .semibold)).foregroundStyle(theme.onAccentColor)
                .padding(.horizontal, 12).frame(height: 32)
                .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Ground, surface, accent bar and signal dot of a scheme.
struct SchemeSwatch: View {
    var scheme: ThubanScheme
    var dark: Bool

    var body: some View {
        let safe = scheme.sanitized()
        let bg = Color(hex: dark ? safe.darkBg : safe.lightBg)
        let panel = Color(hex: dark ? safe.darkPanel : safe.lightPanel)
        let line = Color(hex: dark ? "#2a2e36" : "#e6dfcf")
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(bg)
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(panel)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(line, lineWidth: 1))
                .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 18))
            Capsule().fill(Color(hex: safe.accent)).frame(width: 30, height: 6).offset(x: 11, y: 12)
            HStack { Spacer(); Circle().fill(Color(hex: safe.signal)).frame(width: 8, height: 8) }.padding(.trailing, 6).offset(y: 14)
        }
        .frame(height: 38)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - Pages

/// A settings sub-page with the house header.
struct SettingsPageScaffold<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var back = "Settings"
    @ViewBuilder var content: Content

    var body: some View {
        PushedScreen(title, back: back) {
            VStack(alignment: .leading, spacing: IOSMetrics.sectionGap) { content }
                .gutter()
                .padding(.top, 8)
        }
    }
}

struct ConnectionSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var confirmDisconnect = false
    @State private var replacing = false
    @State private var token = ""

    var body: some View {
        SettingsPageScaffold(title: "Connection") {
            Card {
                infoRow("Canvas", app.demoMode ? "Demo account (offline)" : app.hostLabel)
                RowDivider()
                infoRow("Signed in as", app.user?.name ?? "—")
                RowDivider()
                infoRow("Status", app.authenticationFailed ? "Token rejected" : (app.isConnected ? "Connected · read-only" : "Offline"))
            }
            if app.authenticationFailed || replacing {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading("New access token")
                    Card {
                        SecureField("", text: $token, prompt: Text("Paste a Canvas access token").foregroundStyle(theme.inkFaintColor))
                            .tFont(.body).foregroundStyle(theme.inkColor)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.horizontal, 16).frame(minHeight: IOSMetrics.rowHeight)
                            .accessibilityLabel("Access token")
                    }
                    if let error = app.connectionError {
                        Text(error).tFont(.footnote).foregroundStyle(theme.negTextColor).padding(.top, 8).padding(.horizontal, 16)
                    }
                    PrimaryButton(title: "Save & test", busy: app.isConnecting) {
                        Task { await app.connect(host: app.host, token: token); if app.connectionError == nil { replacing = false; token = "" } }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || app.isConnecting)
                    .padding(.top, 12)
                }
            } else if !app.demoMode {
                SecondaryButton(title: "Replace access token", systemImage: "key") { replacing = true }
            }
            Text("The token is stored in a private file inside the app on this device (not the Keychain), protected while the device is locked. Thuban Canvas only reads from your account.")
                .tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16)
            if !app.demoMode {
                SecondaryButton(title: "Disconnect", systemImage: "rectangle.portrait.and.arrow.right", tint: theme.negTextColor) { confirmDisconnect = true }
                    .confirmationDialog("Disconnect from Canvas?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                        Button("Disconnect", role: .destructive) { Task { await app.disconnect() } }
                    } message: {
                        Text("Removes the token, saved data and downloaded files from this device. Nothing changes in Canvas.")
                    }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).tFont(.body).foregroundStyle(theme.inkColor)
            Spacer()
            Text(value).tFont(.secondary).foregroundStyle(theme.inkDimColor).lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: IOSMetrics.rowHeight)
        .accessibilityElement(children: .combine)
    }
}

struct ReminderSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var status: UNAuthorizationStatus = .notDetermined
    private let options: [(Int, String)] = [(168, "1 week"), (48, "2 days"), (24, "1 day"), (6, "6 hours"), (2, "2 hours"), (1, "1 hour")]

    var body: some View {
        SettingsPageScaffold(title: "Due-date reminders") {
            Card {
                HStack {
                    Text("Remind me").tFont(.body).foregroundStyle(theme.inkColor)
                    Spacer()
                    ThubanSwitch(isOn: Binding(get: { app.settings.notifications.enabled }, set: { value in
                        app.settings.notifications.enabled = value
                        if value { Task { _ = await Reminders.requestAuthorization(); await refreshStatus(); Reminders.reschedule(app: app) } }
                    }), label: "Due-date reminders")
                }
                .padding(.leading, 16).padding(.trailing, 14)
                .frame(minHeight: IOSMetrics.rowHeight)
            }
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Before each due date")
                Card {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        if index > 0 { RowDivider() }
                        let on = app.settings.notifications.leadHours.contains(option.0)
                        Button {
                            var hours = Set(app.settings.notifications.leadHours)
                            if on { hours.remove(option.0) } else { hours.insert(option.0) }
                            app.settings.notifications.leadHours = hours.sorted(by: >)
                        } label: {
                            HStack {
                                Text(option.1).tFont(.body).foregroundStyle(theme.inkColor)
                                Spacer()
                                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.brassInkColor) }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: IOSMetrics.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .disabled(!app.settings.notifications.enabled)
                    }
                }
            }
            if status == .denied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are off for Thuban Canvas in iOS Settings.").tFont(.footnote).foregroundStyle(theme.negTextColor)
                    SecondaryButton(title: "Open iOS Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            Text("Local notifications, scheduled on this device from your assignments. Nothing is sent to Canvas.")
                .tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16)
        }
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

struct GradesSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Binding var path: [SettingsPage]

    var body: some View {
        SettingsPageScaffold(title: "Grades & GPA") {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Letter scale")
                Segmented(options: LetterScale.allCases.map { ($0, $0.label) },
                          selection: Binding(get: { app.settings.letterScale }, set: { app.settings.letterScale = $0 }), stretch: true)
                Text("Used when a course has no grading scheme of its own: \(app.settings.letterScale.scheme.summary).")
                    .tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16).padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Credits this term")
                Card {
                    ForEach(Array(app.orderedSessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 10) {
                            CourseDot(color: app.tint(for: session.id))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.shortTitle).tFont(.text(16, .semibold)).foregroundStyle(session.preferences.excludeFromGPA ? theme.inkFaintColor : theme.inkColor)
                                Text(session.preferences.excludeFromGPA ? "Not counted" : (session.gpaLetter.map { "Letter \($0)" } ?? "No letter yet"))
                                    .tFont(.footnote).foregroundStyle(theme.inkDimColor)
                            }
                            Spacer()
                            stepper(session)
                        }
                        .padding(.leading, 16).padding(.trailing, 8)
                        .frame(minHeight: 60)
                        .contextMenu {
                            Button(session.preferences.excludeFromGPA ? "Count toward GPA" : "Leave out of GPA") {
                                app.updatePreferences(for: session.id) { $0.excludeFromGPA.toggle() }
                            }
                        }
                    }
                }
                Text("Long-press a course to leave it out of the GPA.").tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16).padding(.top, 8)
            }
            Card {
                Button { path.append(.pastSemesters) } label: {
                    HStack {
                        Text("Past semesters").tFont(.body).foregroundStyle(theme.inkColor)
                        Spacer()
                        Text("\(app.settings.pastSemesters.count)").tFont(.secondary).foregroundStyle(theme.inkDimColor)
                        RowChevron()
                    }
                    .padding(.leading, 16).padding(.trailing, 14)
                    .frame(minHeight: IOSMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }

    private func stepper(_ session: CourseSession) -> some View {
        let credits = app.settings.credits(for: session.id)
        return HStack(spacing: 0) {
            IconButton(systemName: "minus", label: "Fewer credits for \(session.shortTitle)", size: 14) {
                app.updatePreferences(for: session.id) { $0.credits = max(0, credits - 1) }
            }
            Text(PointsText.short(credits)).tFont(.mono(15, .semibold)).foregroundStyle(theme.inkColor).frame(minWidth: 24)
                .accessibilityLabel("\(PointsText.short(credits)) credits")
            IconButton(systemName: "plus", label: "More credits for \(session.shortTitle)", size: 14) {
                app.updatePreferences(for: session.id) { $0.credits = min(12, credits + 1) }
            }
        }
    }
}

struct CacheSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var confirm = false
    @State private var size = CacheSettings.sizeText

    var body: some View {
        SettingsPageScaffold(title: "Offline cache") {
            Card {
                HStack {
                    Text("Saved on this device").tFont(.body).foregroundStyle(theme.inkColor)
                    Spacer()
                    Text(size).tFont(.mono(15)).foregroundStyle(theme.inkDimColor)
                }
                .padding(.horizontal, 16).frame(minHeight: IOSMetrics.rowHeight)
            }
            Text("Courses, grades, messages and opened files are kept so the app opens instantly and works offline.")
                .tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16)
            SecondaryButton(title: "Clear saved data", systemImage: "trash", tint: theme.negTextColor) { confirm = true }
                .confirmationDialog("Clear saved data?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Clear", role: .destructive) {
                        Task {
                            await app.cache.clear()
                            try? FileManager.default.removeItem(at: AppPaths.downloadsDirectory)
                            try? AppPaths.ensureDirectories()
                            size = CacheSettings.sizeText
                        }
                    }
                } message: {
                    Text("Everything downloads again next time. Nothing changes in Canvas.")
                }
        }
    }

    /// Cache + downloaded files, e.g. "38.2 MB".
    static var sizeText: String {
        func folderSize(_ url: URL) -> Int {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var total = 0
            for case let file as URL in enumerator {
                total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
            return total
        }
        let total = folderSize(AppPaths.cacheDirectory) + folderSize(AppPaths.downloadsDirectory)
        return total == 0 ? "Empty" : DueFormatter.bytes(total)
    }
}

/// Edit the eight slots of a custom scheme with the system colour picker; starts from any preset.
struct CustomSchemeEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let scheme = app.settings.theme.custom ?? app.settings.theme.effectiveScheme.asCustom()
        SettingsPageScaffold(title: "Custom scheme") {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Start from")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SchemePresets.all) { preset in
                            Button { app.setCustomScheme(preset) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    SchemeSwatch(scheme: preset, dark: theme.isDark).frame(width: 72)
                                    Text(preset.label).tFont(.text(12, .semibold)).foregroundStyle(theme.inkDimColor)
                                }
                            }
                            .buttonStyle(PressFadeStyle())
                            .accessibilityLabel("Start from \(preset.label)")
                        }
                    }
                }
            }
            Card {
                ForEach(Array(ThubanScheme.Slot.allCases.enumerated()), id: \.element) { index, slot in
                    if index > 0 { RowDivider() }
                    ColorPicker(selection: Binding(get: { Color(hex: scheme[slot]) }, set: { color in
                        var edited = scheme
                        edited[slot] = color.hexString
                        app.setCustomScheme(edited)
                    }), supportsOpacity: false) {
                        HStack {
                            Text(slot.label).tFont(.body).foregroundStyle(theme.inkColor)
                            Spacer()
                            Text(scheme[slot].uppercased()).tFont(.mono(13)).foregroundStyle(theme.inkDimColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: IOSMetrics.rowHeight)
                }
            }
            Text("Text colours are adjusted automatically so everything stays readable.").tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16)
        }
        .onAppear { if !app.settings.theme.usesCustom { app.setCustomScheme(scheme) } }
    }
}

extension Color {
    /// `#rrggbb` in sRGB.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(red), channel(green), channel(blue))
    }
}
