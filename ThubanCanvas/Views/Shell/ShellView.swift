import SwiftUI
import ThubanCanvasCore

/// The main window: title bar (mark, Home + course tabs, utility buttons), then the selected tab's content, or
/// the connect screen when there are no credentials.
struct ShellView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var app = app
        let theme = app.theme
        VStack(spacing: 0) {
            TitleBar()
            if !app.isLoaded {
                Color.clear
            } else if app.client == nil {
                ConnectView()
            } else {
                ZStack {
                    // Inert while a panel covers it, so its Escape / ⌘Return / ⌘[ shortcuts cannot fire underneath.
                    content
                        .disabled(app.panel != nil)
                        .accessibilityHidden(app.panel != nil)
                    if let panel = app.panel {
                        UtilityPanelHost(panel: panel)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
        .environment(\.thubanTheme, theme)
        .environment(\.thubanTextScale, app.settings.textSize.scale)
        .ignoresSafeArea()
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onChange(of: app.settingsRequest) { _, _ in openWindow(id: "settings") }
    }

    @ViewBuilder
    private var content: some View {
        switch app.selectedTab {
        case .home:
            HomeView()
        case .course(let id):
            if let session = app.sessions[id] {
                CourseView(session: session)
                    .id(id)
            } else {
                HomeView()
            }
        }
    }
}

/// Calendar / Inbox slide over the current tab (they are not tabs: the tab strip is Home + classes only).
private struct UtilityPanelHost: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var panel: UtilityPanel

    var body: some View {
        VStack(spacing: 0) {
            switch panel {
            case .calendar: CalendarView()
            case .inbox: InboxView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
    }
}

// MARK: - Title bar

/// 52 pt: [traffic-light inset] mark + "Thuban Canvas" | Home + course tabs | Inbox · Calendar · Refresh · Settings.
struct TitleBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: ThubanMetrics.trafficLightInset - 16)
            HStack(spacing: 8) {
                ThubanMarkView(size: 20, color: theme.brassInkColor)
                Text("Thuban Canvas")
                    .font(ThubanFont.display(16))
                    .foregroundStyle(theme.inkColor)
            }
            .padding(.trailing, 12)

            if app.client != nil {
                TabStrip()
            }

            Spacer(minLength: 8)

            if app.client != nil {
                UtilityButton(symbol: "tray", label: "Inbox", badge: app.unreadInbox, active: app.panel == .inbox) {
                    app.panel = app.panel == .inbox ? nil : .inbox
                }
                UtilityButton(symbol: "calendar", label: "Calendar", active: app.panel == .calendar) {
                    app.panel = app.panel == .calendar ? nil : .calendar
                }
                RefreshButton()
            }
            ConnectionChip()
            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(GhostButtonStyle(height: 34, horizontalPadding: 0))
            .accessibilityLabel("Settings")
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 16)
        .frame(height: ThubanMetrics.titleBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.panelColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .gesture(WindowDragGesture())
    }
}

/// Icon button on the right of the title bar, with an optional unread badge and an "active" tint.
struct UtilityButton: View {
    @Environment(\.thubanTheme) private var theme
    var symbol: String
    var label: String
    var badge: Int = 0
    var active: Bool = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(active ? theme.brassInkColor : theme.inkDimColor)
                    .frame(width: 34, height: 34)
                if badge > 0 {
                    Text(badge > 99 ? "99+" : String(badge))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.onAccentColor)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(theme.accentColor, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
            .background(
                active ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear),
                in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(badge > 0 ? "\(label), \(badge) unread" : label)
        .help(label)
    }
}

private struct RefreshButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var hovering = false

    private var reduceMotion: Bool { systemReduceMotion || app.settings.reduceMotion }

    var body: some View {
        Button {
            Task { await app.refreshAll() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(app.isRefreshing && !reduceMotion ? 360 : 0))
                .animation(app.isRefreshing && !reduceMotion ? .linear(duration: 1).repeatForever(autoreverses: false) : nil, value: app.isRefreshing)
                // With motion reduced, a dimmed icon still shows that a refresh is in progress.
                .opacity(app.isRefreshing && reduceMotion ? 0.5 : 1)
                .background(hovering && !app.isRefreshing ? theme.panel2Color : .clear,
                            in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(app.isRefreshing)
        .accessibilityLabel("Refresh")
        .accessibilityValue(app.isRefreshing ? "Refreshing" : "")
        .help(app.lastRefresh.map { "Refreshed \(DueFormatter.countdown($0))" } ?? "Refresh")
    }
}

/// Connected / Signed out / Token rejected. Clicking opens Settings → Connection.
struct ConnectionChip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    private var state: (text: String, kind: ChipKind) {
        if app.authenticationFailed { return ("Token rejected", .neg) }
        if app.client != nil {
            // First name only: the title bar shares its width with one tab per starred course.
            let first = app.user?.shortName?.split(separator: " ").first.map(String.init)
            return (first ?? "Connected", .pos)
        }
        return ("Not connected", .neutral)
    }

    var body: some View {
        Button {
            openWindow(id: "settings")
        } label: {
            Chip(state.text, kind: state.kind, dot: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Canvas connection: \(state.text)")
        .accessibilityHint("Opens Settings")
    }
}

// MARK: - Tabs

/// Home, then one tab per starred course (drag to reorder; right-click for nickname / open in Canvas).
struct TabStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ShellTab(title: "Home", symbol: "house", isActive: app.selectedTab == .home && app.panel == nil, tint: nil) {
                app.select(.home)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    let sessions = app.orderedSessions
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        ShellTab(title: sessions.count > 4 ? session.compactTitle : session.tabTitle, symbol: nil,
                                 isActive: app.selectedTab == .course(session.id) && app.panel == nil,
                                 tint: session.preferences.tint.map { Color(hex: $0) },
                                 compact: sessions.count > 4,
                                 accessibilityLabel: "\(session.course.name), tab \(index + 1) of \(sessions.count)") {
                            app.select(.course(session.id))
                        }
                        .help("\(session.course.name) · \(session.shortCode)")
                        .contextMenu {
                            Button("Open in Canvas") {
                                if let url = URL(string: "\(app.host)/courses/\(session.id)") { NSWorkspace.shared.open(url) }
                            }
                            Button("Course settings…") { app.settingsRequest += 1 }
                        }
                        .draggable(String(session.id))
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let id = CanvasID(raw), id != session.id else { return false }
                            app.moveCourse(id, before: session.id)
                            return true
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One tab: 34 pt, radius 8. Active: `panel2` fill, `ink` text, 1 px `line2`.
struct ShellTab: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var symbol: String?
    var isActive: Bool
    var tint: Color?
    var compact: Bool = false
    /// Full name for VoiceOver when `title` is a compact course code.
    var accessibilityLabel: String? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? theme.brassInkColor : theme.inkDimColor)
                } else {
                    Circle().fill(tint ?? (isActive ? theme.accentColor : theme.line2Color)).frame(width: 8, height: 8)
                }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isActive ? theme.inkColor : theme.inkDimColor)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: 34)
            .background(
                isActive ? theme.panel2Color : (hovering ? theme.panel2Color.opacity(0.6) : .clear),
                in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(isActive ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
