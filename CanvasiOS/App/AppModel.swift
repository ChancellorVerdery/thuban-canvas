import Foundation
import Observation
import SwiftUI
import ThubanCanvasCore
import UIKit
import os

/// iOS root model. Mirrors the Mac `AppModel` surface that the shared `Resource`, `CourseSession` and
/// `CalendarModel` use (`settings`, `cache`, `client`, `courses`, `noteUnauthorized`), plus iPhone/iPad navigation.
///
/// READ-ONLY toward Canvas: the client's session runs every request through `ReadOnlyGuard`, and no screen offers a
/// write. Submitting, replying and marking things happen in Canvas itself (Safari).
@MainActor
@Observable
final class AppModel {
    static let logger = Logger(subsystem: "org.thuban.canvas.ios", category: "app")

    // MARK: Settings & connection

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            if settings.theme != oldValue.theme { recomputeTheme() }
            if settings.notifications != oldValue.notifications { Reminders.reschedule(app: self) }
        }
    }
    private(set) var credentials: CanvasCredentials?
    private(set) var client: CanvasClient?
    let cache: DiskCache
    private(set) var user: CanvasUser?
    private(set) var connectionError: String?
    private(set) var isConnecting = false
    private(set) var authenticationFailed = false
    private(set) var isLoaded = false
    /// The offline fixture account (smoke runs); never persisted.
    let demoMode: Bool

    var isConnected: Bool { client != nil && !authenticationFailed }
    var host: String { credentials?.host ?? "" }
    var hostLabel: String { URL(string: host)?.host ?? host }

    // MARK: Courses

    private(set) var courses: [Course] = []
    private(set) var sessions: [CanvasID: CourseSession] = [:]
    private(set) var coursesError: ThubanError?
    private(set) var isLoadingCourses = false
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private(set) var unreadInbox = 0

    let inbox = InboxStore()
    let calendar = CalendarModel()

    // MARK: Navigation

    var selectedTab: MainTab = .home
    var homePath: [Route] = []
    var coursesPath: [Route] = []
    var calendarPath: [Route] = []
    var inboxPath: [Route] = []
    var showingSettings = false
    /// Page to open when the Settings sheet appears (consumed by the sheet).
    var settingsPage: SettingsPage?
    var calendarMonthMode = false
    var sidebar: SidebarItem? = .home
    var ipadPath: [Route] = []
    /// Per-course section on iPad.
    var ipadSections: [CanvasID: HubSection] = [:]
    /// Assignment shown in the iPad Assignments split.
    var ipadAssignment: [CanvasID: CanvasID] = [:]
    var safariURL: IdentifiableURL?
    var quickLookURL: URL?
    var fileError: String?
    var downloadingFile: CanvasID?

    // MARK: Theme

    private(set) var systemIsDark = false
    private(set) var theme: ResolvedTheme

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(demo: Bool = false) {
        demoMode = demo
        if demo {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("thuban-canvas-demo", isDirectory: true)
            try? FileManager.default.removeItem(at: home)
            AppPaths.overrideHome = home
        }
        cache = DiskCache(directory: AppPaths.cacheDirectory)
        let loaded = demo ? AppSettings() : SettingsStore.load()
        settings = loaded
        let dark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        systemIsDark = dark
        theme = ThemeResolver.resolve(loaded.theme, systemIsDark: dark)
    }

    // MARK: Sessions

    var allOrderedSessions: [CourseSession] {
        // The user's order first, then Canvas's own favorites order (the dashboard order).
        let order = settings.courseOrder
        let canvasOrder = Dictionary(uniqueKeysWithValues: courses.enumerated().map { ($1.id, $0) })
        return courses
            .sorted { a, b in
                let ia = order.firstIndex(of: a.id) ?? Int.max
                let ib = order.firstIndex(of: b.id) ?? Int.max
                if ia != ib { return ia < ib }
                return (canvasOrder[a.id] ?? 0) < (canvasOrder[b.id] ?? 0)
            }
            .compactMap { sessions[$0.id] }
    }

    var orderedSessions: [CourseSession] { allOrderedSessions.filter { !$0.preferences.hidden } }
    var hiddenSessions: [CourseSession] { allOrderedSessions.filter { $0.preferences.hidden } }

    /// Course colour: the user's tint, else a theme colour by position (accent, signal, gain, loss, faint ink).
    func tint(for id: CanvasID?) -> Color {
        guard let id else { return theme.inkFaintColor }
        if let hex = settings.preferences(for: id).tint { return Color(hex: hex) }
        let palette = [theme.accentColor, theme.signalColor, theme.posColor, theme.negColor, theme.inkFaintColor]
        let index = allOrderedSessions.firstIndex { $0.id == id } ?? 0
        return palette[index % palette.count]
    }

    /// "MATH 2171" (or the nickname) for a course id; the Canvas context name as a fallback.
    func shortName(for id: CanvasID?, fallback: String? = nil) -> String {
        if let id, let session = sessions[id] { return session.shortTitle }
        return fallback.map { CourseNaming.shorten($0) ?? $0 } ?? ""
    }

    /// The current term's name ("Fall 2026").
    var termName: String? {
        orderedSessions.compactMap { $0.course.term?.name }.first { $0 != "Default Term" }
    }

    // MARK: Lifecycle

    func load() async {
        guard !isLoaded else { return }
        try? AppPaths.ensureDirectories()
        if demoMode {
            DemoTransport.demo = DemoCanvas()
            credentials = DemoCanvas.credentials
            client = try? DemoTransport.makeClient()
        } else {
            do {
                if let stored = try CredentialStore.load() {
                    credentials = stored
                    client = try makeClient(stored)
                }
            } catch {
                connectionError = error.localizedDescription
            }
        }
        isLoaded = true
        guard client != nil else { return }
        await loadCourses()
        await loadHomeResources()
        Reminders.reschedule(app: self)
    }

    private func makeClient(_ credentials: CanvasCredentials) throws -> CanvasClient {
        try CanvasClient(credentials: credentials, session: ReadOnlyGuard.makeSession())
    }

    /// Validates host + token with a read (`GET /users/self`), then stores them in the protected file.
    func connect(host rawHost: String, token rawToken: String) async {
        guard !demoMode else {
            connectionError = "The demo account is offline; restart without THUBAN_CANVAS_DEMO to connect."
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        connectionError = nil
        do {
            let host = try CanvasCredentials.normalizeHost(rawHost)
            let token = try CanvasCredentials.normalizeToken(rawToken)
            let candidate = CanvasCredentials(host: host, token: token)
            let probe = try makeClient(candidate)
            let me = try await probe.currentUser()
            try CredentialStore.save(candidate)
            credentials = candidate
            client = probe
            user = me
            authenticationFailed = false
            await cache.clear()
            await loadCourses(force: true)
            await loadHomeResources(force: true)
            Reminders.reschedule(app: self)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    /// Forgets the token, cached payloads and downloaded files.
    func disconnect() async {
        try? CredentialStore.clear()
        credentials = nil
        client = nil
        user = nil
        courses = []
        sessions = [:]
        homePath = []; coursesPath = []; calendarPath = []; inboxPath = []; ipadPath = []
        selectedTab = .home
        sidebar = .home
        authenticationFailed = false
        connectionError = nil
        showingSettings = false
        await cache.clear()
        try? FileManager.default.removeItem(at: AppPaths.downloadsDirectory)
        try? AppPaths.ensureDirectories()
        Reminders.clearAll()
    }

    func noteUnauthorized() {
        authenticationFailed = true
        connectionError = ThubanError.unauthorized.localizedDescription
    }

    // MARK: Loading

    private let coursesResource = Resource<[Course]>(key: "self/favorites", ttl: 600)
    private let userResource = Resource<CanvasUser>(key: "self/user", ttl: 86_400)

    func loadCourses(force: Bool = false) async {
        isLoadingCourses = true
        defer { isLoadingCourses = false }
        await userResource.load(app: self, force: force) { try await $0.currentUser() }
        if let me = userResource.value { user = me }
        await coursesResource.load(app: self, force: force) { try await $0.favoriteCourses() }
        coursesError = coursesResource.error
        let fetched = (coursesResource.value ?? []).filter { $0.workflowState != "deleted" }
        courses = fetched
        var next: [CanvasID: CourseSession] = [:]
        for course in fetched {
            if let existing = sessions[course.id] {
                existing.course = course
                next[course.id] = existing
            } else {
                next[course.id] = CourseSession(course: course, app: self)
            }
        }
        sessions = next
        if !fetched.isEmpty, coursesResource.error == nil, coursesResource.fromCache == false { lastRefresh = Date() }
        else if lastRefresh == nil, coursesResource.hasValue { lastRefresh = coursesResource.loadedAt }
    }

    /// Grades + due dates for every course, plus the inbox badge.
    func loadHomeResources(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for session in orderedSessions {
                group.addTask { await session.loadForHome(force: force) }
            }
            group.addTask { await self.refreshUnreadCount() }
        }
    }

    /// Pull to refresh / the refresh button.
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await loadCourses(force: true)
        await withTaskGroup(of: Void.self) { group in
            for session in orderedSessions { group.addTask { await session.refreshLoaded() } }
            group.addTask { await self.refreshUnreadCount() }
        }
        if coursesError == nil { lastRefresh = Date() }
        Reminders.reschedule(app: self)
    }

    func refreshUnreadCount() async {
        guard let client else { return }
        if let count = try? await client.unreadConversationCount() { unreadInbox = count }
    }

    /// Every work item across visible courses (deduplicated).
    var allWorkItems: [WorkItem] {
        var seen = Set<String>()
        return orderedSessions.flatMap(\.workItems).filter { seen.insert($0.id).inserted }
    }

    // MARK: Local-only state (never sent to Canvas)

    func dismissOverdue(_ item: WorkItem) { settings.dismissedOverdue.insert(item.dismissKey) }

    func restoreAllOverdue(_ keys: [String]) {
        for key in keys { settings.dismissedOverdue.remove(key) }
    }

    func updatePreferences(for course: CanvasID, _ change: (inout CoursePreferences) -> Void) {
        var preferences = settings.preferences(for: course)
        change(&preferences)
        settings.coursePreferences[course] = preferences
    }

    func setHidden(_ hidden: Bool, course: CanvasID) {
        updatePreferences(for: course) { $0.hidden = hidden }
    }

    func moveCourses(from offsets: IndexSet, to destination: Int) {
        var order = allOrderedSessions.map(\.id)
        order.move(fromOffsets: offsets, toOffset: destination)
        settings.courseOrder = order
    }

    // MARK: GPA

    var gpaCourses: [GPACourse] {
        orderedSessions.map { session in
            GPACourse(id: session.id, name: session.displayName, letter: session.gpaLetter,
                      credits: settings.credits(for: session.id), included: !session.preferences.excludeFromGPA)
        }
    }

    var gpa: GPAResult { GPACalculator.compute(courses: gpaCourses, past: settings.pastSemesters) }

    /// Cumulative GPA from past semesters alone (the "+0.03" comparison on Home).
    var pastCumulative: Double? { GPACalculator.compute(courses: [], past: settings.pastSemesters).cumulative }

    // MARK: Opening things

    /// Opens a link: Canvas assignment/page/file/discussion links in the app, everything else in Safari.
    func openLink(_ url: URL, from tab: MainTab? = nil) {
        if let link = CanvasHTML.classify(url, host: host) {
            switch link {
            case .assignment(let course, let id) where sessions[course] != nil: push(.assignment(course: course, id: id)); return
            case .page(let course, let slug) where sessions[course] != nil: push(.page(course: course, slug: slug)); return
            case .discussion(let course, let id) where sessions[course] != nil: push(.discussion(course: course, id: id)); return
            case .course(let id) where sessions[id] != nil: push(.course(id)); return
            case .file(let course, let id): Task { await openFile(course: course, id: id) }; return
            default: break
            }
        }
        openInSafari(url)
    }

    func openInSafari(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else {
            UIApplication.shared.open(url)
            return
        }
        safariURL = IdentifiableURL(url: url)
    }

    /// Pushes onto the visible stack (the selected tab on iPhone, the detail stack on iPad).
    func push(_ route: Route) {
        if UIDevice.current.userInterfaceIdiom == .pad, sidebar != nil {
            ipadPath.append(route)
            return
        }
        switch selectedTab {
        case .home: homePath.append(route)
        case .courses: coursesPath.append(route)
        case .calendar: calendarPath.append(route)
        case .inbox: inboxPath.append(route)
        }
    }

    /// Downloads a Canvas file (cached under the app's files folder) and shows it in Quick Look.
    func openFile(course: CanvasID?, id: CanvasID) async {
        guard let client else { return }
        downloadingFile = id
        defer { downloadingFile = nil }
        do {
            let file: CanvasFile
            if let course { file = try await client.courseFile(course: course, id: id) } else { file = try await client.file(id) }
            let local = Self.localURL(for: file)
            if !FileManager.default.fileExists(atPath: local.path) {
                guard let raw = file.url, let remote = URL(string: raw) else { throw ThubanError.unavailable("This file cannot be downloaded.") }
                try await client.download(remote, to: local)
            }
            quickLookURL = local
        } catch {
            fileError = error.localizedDescription
        }
    }

    static func localURL(for file: CanvasFile) -> URL {
        // One folder per file id so Quick Look shows the plain file name.
        let safe = file.displayName.replacingOccurrences(of: "/", with: "-")
        return AppPaths.downloadsDirectory.appendingPathComponent("\(file.id)", isDirectory: true).appendingPathComponent(safe)
    }

    static func isSavedOffline(fileId: CanvasID) -> Bool {
        let folder = AppPaths.downloadsDirectory.appendingPathComponent("\(fileId)", isDirectory: true)
        return !((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty
    }

    // MARK: Settings persistence

    private func persistSettings() {
        guard !demoMode else { return }
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do { try SettingsStore.save(snapshot) } catch { Self.logger.error("settings save failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Writes a pending debounced change now (app going to the background).
    func flushSettings() {
        guard let pending = saveTask, !demoMode else { return }
        pending.cancel()
        saveTask = nil
        try? SettingsStore.save(settings)
    }

    // MARK: Theme

    func setAppearanceMode(_ mode: AppearanceMode) {
        var selection = settings.theme
        selection.mode = mode
        settings.theme = selection
    }

    func selectScheme(id: String) {
        var selection = settings.theme
        selection.schemeId = id
        if id == ThubanScheme.customId, selection.custom == nil { selection.custom = SchemePresets.default.asCustom() }
        settings.theme = selection
    }

    func setCustomScheme(_ scheme: ThubanScheme) {
        var selection = settings.theme
        selection.custom = scheme.asCustom(label: "Custom")
        selection.schemeId = ThubanScheme.customId
        settings.theme = selection
    }

    /// Called by the root view when the system appearance changes (only meaningful in Automatic mode).
    func noteSystemAppearance(dark: Bool) {
        guard dark != systemIsDark else { return }
        systemIsDark = dark
        recomputeTheme()
    }

    private func recomputeTheme() {
        let resolved = ThemeResolver.resolve(settings.theme, systemIsDark: systemIsDark)
        if resolved != theme { theme = resolved }
        applyInterfaceStyle()
    }

    /// Light/Dark overrides go on every window so sheets, keyboards and Quick Look match; Automatic clears them.
    func applyInterfaceStyle() {
        let style: UIUserInterfaceStyle
        switch settings.theme.mode {
        case .auto: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
        }
    }

    /// Font multiplier for the environment.
    func fontScale(dynamicType: DynamicTypeSize) -> CGFloat {
        TypeScale.factor(for: dynamicType) * CGFloat(settings.textSize.scale)
    }
}

struct IdentifiableURL: Identifiable, Hashable {
    var url: URL
    var id: String { url.absoluteString }
}

extension CourseSession {
    /// "MATH 2171", the nickname, or a compact name.
    var shortTitle: String {
        if let nickname = preferences.nickname, !nickname.isEmpty { return nickname }
        let code = shortCode
        if !code.isEmpty, code != course.courseCode { return code }
        return compactTitle
    }

    /// "Section 002"
    var sectionLabel: String? { CourseCodeParser.section(from: course.courseCode).map { "Section \($0)" } }

    var teacherName: String? { course.teachers?.first?.displayName }
}
