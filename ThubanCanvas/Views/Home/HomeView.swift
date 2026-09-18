import SwiftUI
import ThubanCanvasCore

/// The Home tab: term header with refresh, an inbox strip, the grade board, then Upcoming / Overdue on the left
/// and GPA / Recently graded / Announcements on the right. Everything renders from cached data first.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    private let gutter: CGFloat = 24
    private let gap: CGFloat = 16
    private let asideWidth: CGFloat = 400

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: gap) {
                HomeHeader()
                if app.orderedSessions.isEmpty {
                    noCourses
                } else {
                    let items = app.allWorkItems
                    if app.unreadInbox > 0 { HomeInboxStrip(count: app.unreadInbox) }
                    HomeGradeBoard()
                    HStack(alignment: .top, spacing: gap) {
                        VStack(spacing: gap) {
                            HomeUpcomingCard(items: items)
                            HomeOverdueCard(items: items)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: gap) {
                            HomeGPACard()
                            HomeRecentlyGradedCard(items: items)
                            HomeAnnouncementsCard()
                        }
                        .frame(width: asideWidth)
                    }
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bgColor)
        // Keyed on the course list: the first run can precede `loadCourses`, so it re-runs once the tabs exist.
        .task(id: app.courses.map(\.id)) {
            guard !app.courses.isEmpty else { return }
            await app.loadHomeResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .thubanDataRefreshed)) { _ in
            Task { await app.loadHomeResources() }
        }
    }

    @ViewBuilder
    private var noCourses: some View {
        if app.isLoadingCourses && app.courses.isEmpty {
            LoadingView(text: "Loading your courses…").frame(minHeight: 320)
        } else if let error = app.coursesError, app.courses.isEmpty {
            EmptyState(title: "Couldn’t load your courses", message: error.localizedDescription) {
                Button("Try again") { Task { await app.loadCourses(force: true) } }.buttonStyle(.thubanSecondary)
            }
            .frame(minHeight: 320)
        } else {
            EmptyState(title: "No starred courses", message: "Star the courses you want here in Canvas (Courses → All Courses → ★), then refresh.") {
                Button("Refresh") { Task { await app.refreshAll() } }.buttonStyle(.thubanSecondary)
            }
            .frame(minHeight: 320)
        }
    }
}

/// Term eyebrow + today's date on the left; "Updated 3 min ago" and a Refresh button on the right.
private struct HomeHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    /// Ticks once a minute so "Updated … ago" stays honest.
    @State private var now = Date()

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text((HomeSummary.termName(for: app.orderedSessions) ?? "Home").uppercased())
                    .font(ThubanFont.micro)
                    .kerning(0.5)
                    .foregroundStyle(theme.brassInkColor)
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(ThubanFont.display(28))
                    .foregroundStyle(theme.inkColor)
            }
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                if app.coursesError != nil, !app.courses.isEmpty {
                    Chip("Offline · saved data", kind: .warn, dot: true)
                        .help(app.coursesError?.localizedDescription ?? "")
                }
                Text(updatedText)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkFaintColor)
                    .monospacedDigit()
                Button {
                    Task { await app.refreshAll() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                        Text(app.isRefreshing ? "Refreshing…" : "Refresh")
                    }
                }
                .buttonStyle(GhostButtonStyle(height: 30, tinted: true))
                .disabled(app.isRefreshing)
                .accessibilityLabel(app.isRefreshing ? "Refreshing" : "Refresh everything")
                .help("Refresh courses, grades and messages (⌘R)")
            }
            .padding(.bottom, 2)
        }
        .padding(.bottom, 4)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                now = Date()
            }
        }
        .onChange(of: app.lastRefresh) { _, _ in now = Date() }
    }

    private var updatedText: String {
        guard let last = app.lastRefresh else { return app.isRefreshing ? "" : "Showing saved data" }
        let seconds = now.timeIntervalSince(last)
        if seconds < 60 { return "Updated just now" }
        return "Updated \(DueFormatter.countdown(last, now: now))"
    }
}

/// "30 unread messages" with a button that opens the Inbox panel. Hidden when the inbox is clear.
private struct HomeInboxStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.brassInkColor)
            Text(count == 1 ? "1 unread message" : "\(count) unread messages")
                .font(ThubanFont.body(14, weight: .semibold))
                .foregroundStyle(theme.inkColor)
            Text("in your Canvas inbox")
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkDimColor)
            Spacer(minLength: 8)
            Button {
                app.panel = .inbox
            } label: {
                HStack(spacing: 4) {
                    Text("Open Inbox")
                    Glyph(.chevronRight, size: 12)
                }
            }
            .buttonStyle(GhostButtonStyle(height: 28, tinted: true))
            .accessibilityLabel("Open Inbox, \(count) unread")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }
}
