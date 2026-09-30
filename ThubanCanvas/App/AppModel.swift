import AppKit
import Foundation
import Observation
import ThubanCanvasCore
import os

/// Root model: credentials + client, settings, theme, the starred courses (one `CourseSession` each), the
/// cross-course resources the Home tab / Calendar / Inbox read, and the refresh loop.
@MainActor
@Observable
final class AppModel {
    static let logger = Logger(subsystem: "com.thuban.canvas", category: "app")

    // MARK: Settings & connection

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            if settings.theme != oldValue.theme {
                recomputeTheme()
                SharedTheme.publish(settings.theme)
            }
            if settings.refreshMinutes != oldValue.refreshMinutes, isLoaded { startRefreshTimer() }
        }
    }
    private(set) var credentials: CanvasCredentials?
    private(set) var client: CanvasClient?
    let cache = DiskCache()
    private(set) var user: CanvasUser?
    /// Last connection failure (bad token, offline …) for the connect screen and the chip.
    private(set) var connectionError: String?
    private(set) var isConnecting = false
    private(set) var authenticationFailed = false

    var isConnected: Bool { client != nil && !authenticationFailed }
    var host: String { credentials?.host ?? "" }

    // MARK: Courses & tabs

    private(set) var isLoaded = false
    private(set) var courses: [Course] = []
    private(set) var sessions: [CanvasID: CourseSession] = [:]
    private(set) var coursesError: ThubanError?
    private(set) var isLoadingCourses = false
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    var selectedTab: AppTab = .home {
        didSet { settings.lastSelectedTab = selectedTab.storageKey }
    }
    var panel: UtilityPanel?
    var isPresentingSettings = false
    var settingsRequest = 0
    /// Pane to show when Settings opens next (a `SettingsPane` raw value); consumed by `SettingsView`.
    var settingsPane: String?
    /// A `SettingsAnchor` id to scroll to once the pane is shown; consumed by `SettingsView`.
    var settingsScrollAnchor: String?
    /// ⌘F: bumps once per press. A visible `CanvasHTMLView` opens its find bar; otherwise the screen's `SearchField` takes focus.
    var findRequest = 0
    /// How many `CanvasHTMLView`s are currently on screen (they claim ⌘F over list search fields).
    var visibleWebViews = 0

    /// Opens the Settings window on a pane.
    func openSettings(pane: String? = nil) {
        settingsPane = pane
        settingsRequest += 1
    }

    /// Every starred course in the user's order, hidden ones included (Settings lists these).
    var allOrderedSessions: [CourseSession] {
        let order = settings.courseOrder
        return courses
            .sorted { a, b in
                let ia = order.firstIndex(of: a.id) ?? Int.max
                let ib = order.firstIndex(of: b.id) ?? Int.max
                if ia != ib { return ia < ib }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            .compactMap { sessions[$0.id] }
    }

    /// Starred courses the user has not hidden, in their order — one tab each; the only list Home, Calendar,
    /// reminders and the menu bar read.
    var orderedSessions: [CourseSession] {
        allOrderedSessions.filter { !$0.preferences.hidden }
    }

    var hiddenSessions: [CourseSession] { allOrderedSessions.filter { $0.preferences.hidden } }

    /// Hides or shows a course locally (its star in Canvas is untouched).
    func setHidden(_ hidden: Bool, course: CanvasID) {
        updatePreferences(for: course) { $0.hidden = hidden }
        if hidden, selectedTab == .course(course) { selectedTab = .home }
    }

    var selectedSession: CourseSession? {
        if case .course(let id) = selectedTab { return sessions[id] }
        return nil
    }

    // MARK: Cross-course resources (Home, Calendar, Inbox, menu bar)

    let todo = Resource<[TodoItem]>(key: "self/todo", ttl: 300)
    let missing = Resource<[Assignment]>(key: "self/missing", ttl: 300)
    let planner = Resource<[PlannerItem]>(key: "self/planner", ttl: 300)
    let announcements = Resource<[DiscussionTopic]>(key: "self/announcements", ttl: 300)
    let conversations = Resource<[Conversation]>(key: "self/conversations", ttl: 180)
    let stream = Resource<[StreamItem]>(key: "self/stream", ttl: 300)
    private(set) var unreadInbox = 0

    // MARK: Theme

    private(set) var systemIsDark = false
    private(set) var theme: ResolvedTheme = ThemeResolver.resolve(.default, systemIsDark: false)
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    var themeSelection: ThemeSelection { settings.theme }

    /// The one model: the App scene, the menu bar item and the delegate all use it, so the menu bar works with no window.
    static let shared = AppModel()

    init() {
        settings = SettingsStore.load()
        if let shared = SharedTheme.load() { settings.theme = shared }
        systemIsDark = Self.currentSystemIsDark()
        theme = ThemeResolver.resolve(settings.theme, systemIsDark: systemIsDark)
        // The debounced settings write would be lost on ⌘Q within 300 ms; flush it at quit.
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSettings() }
        }
    }

    // MARK: Lifecycle

    /// Called once from the main window's `.task`: restores credentials and the last tab, loads courses.
    func load() async {
        guard !isLoaded else { return }
        if appearanceObservation == nil { observeAppearance() }
        observeSharedTheme()
        // First Thuban app to run with sharing seeds the file with its own scheme.
        if SharedTheme.load() == nil { SharedTheme.publish(settings.theme) }
        recomputeTheme()
        try? AppPaths.ensureDirectories()
        if let key = settings.lastSelectedTab, let tab = AppTab(storageKey: key) { selectedTab = tab }
        do {
            if let stored = try CredentialStore.load() {
                credentials = stored
                client = try CanvasClient(credentials: stored)
            }
        } catch {
            connectionError = error.localizedDescription
        }
        isLoaded = true
        await loadCourses()
        startRefreshTimer()
        MenuBarController.shared.configure(app: self)
        NotificationScheduler.configure(app: self)
        SmokeHarness.startIfEnabled(app: self)
    }

    /// Validates host + token against `/users/self`, then stores them (file, mode 0600) and loads courses.
    func connect(host rawHost: String, token rawToken: String) async {
        isConnecting = true
        defer { isConnecting = false }
        connectionError = nil
        do {
            let host = try CanvasCredentials.normalizeHost(rawHost)
            let token = try CanvasCredentials.normalizeToken(rawToken)
            let candidate = CanvasCredentials(host: host, token: token)
            let probe = try CanvasClient(credentials: candidate)
            let me = try await probe.currentUser()
            try CredentialStore.save(candidate)
            credentials = candidate
            client = probe
            user = me
            authenticationFailed = false
            await cache.clear()
            await loadCourses(force: true)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    /// Forgets the token, every cached payload and every downloaded course file.
    func disconnect() async {
        try? CredentialStore.clear()
        credentials = nil
        client = nil
        user = nil
        courses = []
        sessions = [:]
        selectedTab = .home
        authenticationFailed = false
        connectionError = nil
        await cache.clear()
        try? FileManager.default.removeItem(at: AppPaths.downloadsDirectory)
        try? AppPaths.ensureDirectories()
    }

    func noteUnauthorized() {
        authenticationFailed = true
        connectionError = ThubanError.unauthorized.localizedDescription
    }

    // MARK: Courses

    private let coursesResource = Resource<[Course]>(key: "self/favorites", ttl: 600)
    private let userResource = Resource<CanvasUser>(key: "self/user", ttl: 86_400)

    /// Loads the starred courses (cache first) and builds/updates one session per course.
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
        if case .course(let id) = selectedTab, sessions[id] == nil || settings.preferences(for: id).hidden { selectedTab = .home }
        if !fetched.isEmpty, coursesResource.error == nil, coursesResource.fromCache == false { lastRefresh = Date() }
    }

    /// Refreshes courses, every session's assignment groups and the cross-course resources.
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await loadCourses(force: true)
        await withTaskGroup(of: Void.self) { group in
            for session in orderedSessions { group.addTask { await session.refreshLoaded() } }
            group.addTask { await self.loadHomeResources(force: true) }
        }
        // A failed refresh keeps the previous stamp so saved data is not labelled "Updated just now".
        if coursesError == nil { lastRefresh = Date() }
        NotificationCenter.default.post(name: .thubanDataRefreshed, object: nil)
    }

    /// Everything Home shows: each course's grades/assignments plus to-do, missing, planner, announcements, inbox count.
    func loadHomeResources(force: Bool = false) async {
        let ids = courses.map(\.id)
        let horizonStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let horizonEnd = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()
        await withTaskGroup(of: Void.self) { group in
            for session in orderedSessions { group.addTask { await session.loadForHome(force: force) } }
            group.addTask { await self.todo.load(app: self, force: force) { try await $0.todo() } }
            group.addTask { await self.missing.load(app: self, force: force) { try await $0.missingSubmissions() } }
            group.addTask { await self.planner.load(app: self, force: force) { try await $0.plannerItems(from: horizonStart, to: horizonEnd) } }
            if !ids.isEmpty {
                group.addTask { await self.announcements.load(app: self, force: force) { try await $0.announcements(courses: ids) } }
            }
            group.addTask { await self.refreshUnreadCount() }
        }
    }

    /// Nudges the unread badge immediately after a local read-state change (the next refresh corrects it).
    func adjustUnreadCount(by delta: Int) {
        unreadInbox = max(0, unreadInbox + delta)
    }

    func refreshUnreadCount() async {
        guard let client else { return }
        if let count = try? await client.unreadConversationCount() { unreadInbox = count }
    }

    /// Every work item across the starred courses (deduplicated by assignment).
    var allWorkItems: [WorkItem] {
        var seen = Set<String>()
        return orderedSessions.flatMap(\.workItems).filter { seen.insert($0.id).inserted }
    }

    // MARK: Tabs

    func select(_ tab: AppTab) {
        selectedTab = tab
        panel = nil
    }

    func moveCourse(_ id: CanvasID, before target: CanvasID) {
        var order = orderedSessions.map(\.id)
        guard let from = order.firstIndex(of: id), let to = order.firstIndex(of: target), from != to else { return }
        order.remove(at: from)
        let insertAt = order.firstIndex(of: target) ?? order.count
        order.insert(id, at: insertAt)
        settings.courseOrder = order
    }

    /// Opens a course tab at a section, optionally pushing a detail route.
    func open(course: CanvasID, section: CourseSection? = nil, route: CourseRoute? = nil) {
        guard let session = sessions[course] else { return }
        if session.preferences.hidden { setHidden(false, course: course) }
        if let section { session.section = section }
        if let route { session.path = [route] } else if section != nil { session.path = [] }
        select(.course(course))
    }

    /// Opens whatever a Canvas link points at inside the app; falls back to the browser.
    func openLink(_ url: URL) {
        if let link = CanvasHTML.classify(url, host: host) {
            switch link {
            case .assignment(let course, let id): open(course: course, section: .assignments, route: .assignment(id)); return
            case .page(let course, let slug): open(course: course, section: .pages, route: .page(slug: slug)); return
            case .file(let course, let id): if let course, sessions[course] != nil { open(course: course, section: .files, route: .file(id)); return }
            case .discussion(let course, let id): open(course: course, section: .discussions, route: .discussion(id)); return
            case .quiz(let course, let id): open(course: course, section: .assignments, route: .quiz(id)); return
            case .moduleItem(let course, let id): open(course: course, section: .modules, route: .module(id)); return
            case .course(let id): if sessions[id] != nil { open(course: id); return }
            }
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: Settings persistence

    private func persistSettings() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do { try SettingsStore.save(snapshot) } catch { Self.logger.error("settings save failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Writes any pending debounced settings change synchronously (called at quit).
    func flushSettings() {
        guard let pending = saveTask else { return }
        pending.cancel()
        saveTask = nil
        do { try SettingsStore.save(settings) } catch { Self.logger.error("settings flush failed: \(error.localizedDescription, privacy: .public)") }
    }

    func dismissOverdue(_ item: WorkItem) { settings.dismissedOverdue.insert(item.dismissKey) }
    func restoreOverdue(_ key: String) { settings.dismissedOverdue.remove(key) }

    func updatePreferences(for course: CanvasID, _ change: (inout CoursePreferences) -> Void) {
        var preferences = settings.preferences(for: course)
        change(&preferences)
        settings.coursePreferences[course] = preferences
    }

    // MARK: GPA

    var gpaCourses: [GPACourse] {
        orderedSessions.map { session in
            GPACourse(id: session.id, name: session.displayName, letter: session.gpaLetter,
                      credits: settings.credits(for: session.id), included: !session.preferences.excludeFromGPA)
        }
    }

    var gpa: GPAResult { GPACalculator.compute(courses: gpaCourses, past: settings.pastSemesters) }

    // MARK: Refresh timer

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let minutes = max(5, settings.refreshMinutes)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    // MARK: Theme

    func setThemeSelection(_ selection: ThemeSelection) {
        settings.theme = selection
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        var selection = themeSelection
        selection.mode = mode
        setThemeSelection(selection)
    }

    func selectScheme(id: String) {
        var selection = themeSelection
        selection.schemeId = id
        if id == ThubanScheme.customId, selection.custom == nil {
            selection.custom = SchemePresets.default.asCustom()
        }
        setThemeSelection(selection)
    }

    func setCustomScheme(_ scheme: ThubanScheme) {
        var selection = themeSelection
        selection.custom = scheme.asCustom(label: scheme.label)
        selection.schemeId = ThubanScheme.customId
        setThemeSelection(selection)
    }

    @ObservationIgnored private var sharedThemeObserver: NSObjectProtocol?

    /// Another Thuban app changed the scheme: adopt it (publishing again is a no-op once the file matches).
    private func observeSharedTheme() {
        guard sharedThemeObserver == nil else { return }
        sharedThemeObserver = SharedTheme.observe { [weak self] selection in
            guard let self, self.settings.theme != selection else { return }
            self.settings.theme = selection
        }
    }

    private func observeAppearance() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let dark = Self.currentSystemIsDark()
                if dark != self.systemIsDark {
                    self.systemIsDark = dark
                    self.recomputeTheme()
                }
            }
        }
    }

    /// True when macOS itself is dark (independent of any override we apply to `NSApp.appearance`).
    static func currentSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    private func recomputeTheme() {
        let resolved = ThemeResolver.resolve(themeSelection, systemIsDark: systemIsDark)
        if resolved != theme { theme = resolved }
        let application = NSApplication.shared
        switch themeSelection.mode {
        case .auto: application.appearance = nil
        case .light: application.appearance = NSAppearance(named: .aqua)
        case .dark: application.appearance = NSAppearance(named: .darkAqua)
        }
        AppIconRenderer.apply(theme: resolved)
    }
}

extension Notification.Name {
    /// Posted after `refreshAll` completes (menu bar + notifications listen).
    static let thubanDataRefreshed = Notification.Name("com.thuban.canvas.refreshed")
}
