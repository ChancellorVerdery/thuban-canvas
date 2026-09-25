import QuickLook
import SwiftUI
import ThubanCanvasCore

@main
struct ThubanCanvasiOSApp: App {
    @State private var app = AppModel(demo: SmokeHarness.isActive || ProcessInfo.processInfo.environment["THUBAN_CANVAS_DEMO"] == "1")
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task {
                    SmokeHarness.prepare(app: app)
                    await app.load()
                    await SmokeHarness.run(app: app)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { app.flushSettings() }
                    if phase == .active, app.isLoaded, app.isConnected, !SmokeHarness.isActive {
                        Task { await app.refreshUnreadCount() }
                    }
                }
        }
    }
}

/// Theme + font environment, first-run Connect, and the iPhone tabs or the iPad split view.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        @Bindable var app = app
        let theme = app.theme
        Group {
            if !app.isLoaded {
                theme.bgColor.ignoresSafeArea()
            } else if app.credentials == nil || SmokeHarness.showsConnect {
                ConnectScreen()
            } else if sizeClass == .regular {
                IPadRootView()
            } else {
                PhoneRootView()
            }
        }
        .environment(\.thubanTheme, theme)
        .environment(\.thubanFontScale, app.fontScale(dynamicType: dynamicType))
        .environment(\.thubanDyslexia, app.settings.dyslexiaFont)
        .environment(\.thubanTextScale, app.settings.textSize.scale)
        .tint(theme.brassInkColor)
        .transaction { if app.settings.reduceMotion || systemReduceMotion { $0.animation = nil } }
        .sheet(isPresented: $app.showingSettings) {
            SettingsSheet()
                .environment(\.thubanTheme, theme)
                .environment(\.thubanFontScale, app.fontScale(dynamicType: dynamicType))
                .environment(\.thubanDyslexia, app.settings.dyslexiaFont)
                .tint(theme.brassInkColor)
        }
        .sheet(item: $app.safariURL) { item in
            SafariView(url: item.url, tint: theme.brassInkColor).ignoresSafeArea()
        }
        .quickLookPreview($app.quickLookURL)
        .alert("Couldn’t open the file", isPresented: Binding(get: { app.fileError != nil }, set: { if !$0 { app.fileError = nil } })) {
            Button("OK", role: .cancel) { app.fileError = nil }
        } message: {
            Text(app.fileError ?? "")
        }
        .onAppear {
            if app.settings.theme.mode == .auto { app.noteSystemAppearance(dark: colorScheme == .dark) }
            app.applyInterfaceStyle()
        }
        .onChange(of: colorScheme) { _, scheme in
            if app.settings.theme.mode == .auto { app.noteSystemAppearance(dark: scheme == .dark) }
        }
    }
}

/// iPhone: the selected tab's navigation stack over the custom tab bar. The tab bar yields to the assignment
/// screen's own bottom bar ("Submit in Canvas").
struct PhoneRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        @Bindable var app = app
        ZStack {
            switch app.selectedTab {
            case .home:
                NavigationStack(path: $app.homePath) { HomeScreen().routeDestinations() }
            case .courses:
                NavigationStack(path: $app.coursesPath) { CoursesScreen().routeDestinations() }
            case .calendar:
                NavigationStack(path: $app.calendarPath) { CalendarScreen().routeDestinations() }
            case .inbox:
                NavigationStack(path: $app.inboxPath) { InboxScreen().routeDestinations() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsTabBar { ThubanTabBar() }
        }
        .background(theme.bgColor.ignoresSafeArea())
    }

    private var currentPath: [Route] {
        switch app.selectedTab {
        case .home: return app.homePath
        case .courses: return app.coursesPath
        case .calendar: return app.calendarPath
        case .inbox: return app.inboxPath
        }
    }

    private var showsTabBar: Bool {
        if case .assignment? = currentPath.last { return false }
        return true
    }
}

extension View {
    /// Every pushable screen.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in RouteScreen(route: route) }
    }
}

/// Resolves a route to its screen, with the back title of whatever sits below it.
struct RouteScreen: View {
    @Environment(AppModel.self) private var app
    var route: Route

    var body: some View {
        let back = backTitle
        switch route {
        case .course(let id): CourseHubScreen(courseId: id, back: back)
        case .modules(let id): ModulesScreen(courseId: id, back: back)
        case .assignments(let id): AssignmentsScreen(courseId: id, back: back)
        case .grades(let id): GradesScreen(courseId: id, back: back)
        case .announcements(let id): AnnouncementsScreen(courseId: id, back: back)
        case .discussions(let id): DiscussionsScreen(courseId: id, back: back)
        case .syllabus(let id): SyllabusScreen(courseId: id, back: back)
        case .people(let id): PeopleScreen(courseId: id, back: back)
        case .files(let id): FilesScreen(courseId: id, back: back)
        case .pages(let id): PagesScreen(courseId: id, back: back)
        case .assignment(let course, let id): AssignmentScreen(courseId: course, assignmentId: id, back: back)
        case .page(let course, let slug): PageScreen(courseId: course, slug: slug, back: back)
        case .announcement(let course, let id): TopicScreen(courseId: course, topicId: id, isAnnouncement: true, back: back)
        case .discussion(let course, let id): TopicScreen(courseId: course, topicId: id, isAnnouncement: false, back: back)
        case .event(let id): EventScreen(eventId: id, back: back)
        case .conversation(let id): ConversationScreen(conversationId: id, back: back)
        case .pastSemesters: PastSemestersScreen(back: back)
        }
    }

    private var backTitle: String {
        let path: [Route]
        let rootTitle: String
        if UIDevice.current.userInterfaceIdiom == .pad, app.sidebar != nil {
            path = app.ipadPath
            rootTitle = app.ipadRootTitle
        } else {
            switch app.selectedTab {
            case .home: path = app.homePath
            case .courses: path = app.coursesPath
            case .calendar: path = app.calendarPath
            case .inbox: path = app.inboxPath
            }
            rootTitle = app.selectedTab.title
        }
        guard let index = path.lastIndex(of: route) else { return rootTitle }
        return index == 0 ? rootTitle : path[index - 1].backTitle(app: app)
    }
}
