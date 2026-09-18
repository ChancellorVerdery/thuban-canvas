import SwiftUI
import ThubanCanvasCore

/// Settings window: nav on the left, pane on the right. Panes live in their own files.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var pane: SettingsPane = .connection

    var body: some View {
        let theme = app.theme
        HStack(spacing: 0) {
            SettingsNav(selection: $pane)
            SettingsContent(pane: pane)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
        .environment(\.thubanTheme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onAppear(perform: consumeRequestedPane)
        .onChange(of: app.settingsRequest) { _, _ in consumeRequestedPane() }
    }

    private func consumeRequestedPane() {
        if let raw = app.settingsPane, let requested = SettingsPane(rawValue: raw) {
            pane = requested
            app.settingsPane = nil
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case connection = "Connection"
    case appearance = "Appearance"
    case grades = "Grades & GPA"
    case notifications = "Notifications"
    case storage = "Data"
    case about = "About"

    var id: String { rawValue }

    var caption: String {
        switch self {
        case .connection: return "Your Canvas address and access token. Starred courses in Canvas become tabs here."
        case .appearance: return "Mode, color scheme and text size. Colors follow the scheme on every screen."
        case .grades: return "Credit hours, letter scale, per-course cutoffs and past semesters for the GPA."
        case .notifications: return "Due-date reminders and the menu bar item."
        case .storage: return "Everything is cached on this Mac so the app opens instantly and works offline."
        case .about: return "Thuban Canvas and how it treats your account."
        }
    }

    var symbol: String {
        switch self {
        case .connection: return "link"
        case .appearance: return "paintpalette"
        case .grades: return "chart.bar"
        case .notifications: return "bell"
        case .storage: return "internaldrive"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsNav: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(ThubanFont.display(20))
                .foregroundStyle(theme.inkColor)
                .padding(.horizontal, 12)
                .padding(.top, 22)
                .padding(.bottom, 14)
            ForEach(SettingsPane.allCases) { pane in
                SettingsNavRow(pane: pane, isSelected: pane == selection) { selection = pane }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
    }
}

private struct SettingsNavRow: View {
    @Environment(\.thubanTheme) private var theme
    var pane: SettingsPane
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? theme.brassInkColor : theme.inkDimColor)
                Text(pane.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.inkColor : theme.inkDimColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear),
                in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Scroll anchors other screens can request (`AppModel.settingsScrollAnchor`).
enum SettingsAnchor {
    static let pastSemesters = "settings.pastSemesters"
}

private struct SettingsContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var pane: SettingsPane

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pane.rawValue)
                        .font(ThubanFont.display(24))
                        .foregroundStyle(theme.inkColor)
                    Text(pane.caption)
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch pane {
                case .connection: ConnectionSettings()
                case .appearance: AppearanceSettings()
                case .grades: GradesSettings()
                case .notifications: NotificationSettings()
                case .storage: DataSettings()
                case .about: AboutSettings()
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: app.settingsScrollAnchor) { _, anchor in
            guard let anchor else { return }
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
            app.settingsScrollAnchor = nil
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared settings chrome

struct SettingsGroup<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var caption: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(ThubanFont.display(18))
                    .foregroundStyle(theme.inkColor)
                if let caption {
                    Text(caption)
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label on the left, control on the right, inside a panel row.
struct SettingsRow<Control: View>: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                if let detail {
                    Text(detail).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .thubanPanel(padding: 0)
    }
}

struct SettingsNote: View {
    @Environment(\.thubanTheme) private var theme
    enum Tone { case neutral, positive, negative }
    var text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(ThubanFont.small)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch tone {
        case .neutral: return theme.inkDimColor
        case .positive: return theme.posTextColor
        case .negative: return theme.negTextColor
        }
    }
}

/// A toggle drawn in the Thuban style (accent when on).
struct ThubanToggle: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(theme.accentColor)
            .accessibilityLabel(label)
    }
}

// MARK: - Fields

struct ThubanFieldStyle: ViewModifier {
    @Environment(\.thubanTheme) private var theme
    var invalid: Bool = false
    var mono: Bool = false
    var height: CGFloat = ThubanMetrics.buttonHeight

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? ThubanFont.mono(13) : ThubanFont.body(14))
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(invalid ? theme.negColor : theme.line2Color, lineWidth: invalid ? 1.5 : ThubanMetrics.hairline)
            )
    }
}

extension View {
    func thubanField(invalid: Bool = false, mono: Bool = false, height: CGFloat = ThubanMetrics.buttonHeight) -> some View {
        modifier(ThubanFieldStyle(invalid: invalid, mono: mono, height: height))
    }
}
