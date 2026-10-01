import Foundation
import Observation
import ThubanCanvasCore

/// Everything one course tab holds: the course, its section, a navigation stack of detail routes, and the
/// cache-first resources every section reads. Section views call the `load…` helpers; nothing loads eagerly.
@MainActor
@Observable
final class CourseSession: Identifiable {
    let id: CanvasID
    var course: Course
    var section: CourseSection = .overview
    var path: [CourseRoute] = []

    let groups: Resource<[AssignmentGroup]>
    let modules: Resource<[Module]>
    let files: Resource<[CanvasFile]>
    let folders: Resource<[Folder]>
    let pages: Resource<[Page]>
    let announcements: Resource<[DiscussionTopic]>
    let discussions: Resource<[DiscussionTopic]>
    let quizzes: Resource<[Quiz]>
    let people: Resource<[CourseUser]>
    let gradingStandards: Resource<[GradingStandard]>

    @ObservationIgnored unowned let app: AppModel

    init(course: Course, app: AppModel) {
        id = course.id
        self.course = course
        self.app = app
        let prefix = "course/\(course.id)/"
        groups = Resource(key: prefix + "assignment_groups", ttl: 300)
        modules = Resource(key: prefix + "modules", ttl: 600)
        files = Resource(key: prefix + "files", ttl: 900)
        folders = Resource(key: prefix + "folders", ttl: 900)
        pages = Resource(key: prefix + "pages", ttl: 900)
        announcements = Resource(key: prefix + "announcements", ttl: 300)
        discussions = Resource(key: prefix + "discussions", ttl: 300)
        quizzes = Resource(key: prefix + "quizzes", ttl: 600)
        people = Resource(key: prefix + "people", ttl: 3600)
        gradingStandards = Resource(key: prefix + "grading_standards", ttl: 86_400)
    }

    // MARK: Names

    var preferences: CoursePreferences { app.settings.preferences(for: id) }

    /// The tab label: the nickname if set, else the course name.
    var displayName: String {
        if let nickname = preferences.nickname, !nickname.isEmpty { return nickname }
        return course.name
    }

    /// What the tab shows: the nickname, a short course name, or the code when the name is long.
    var tabTitle: String {
        if let nickname = preferences.nickname, !nickname.isEmpty { return nickname }
        let name = course.name.trimmingCharacters(in: .whitespaces)
        if name.count <= 24 { return name }
        let code = shortCode
        if !code.isEmpty, code != course.courseCode { return code }
        return String(name.prefix(22)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Compact title when many courses are starred: nickname, else the code ("MATH 2241"), else a short prefix.
    var compactTitle: String {
        if let nickname = preferences.nickname, !nickname.isEmpty { return nickname }
        let code = shortCode
        if !code.isEmpty, code != course.courseCode { return code }
        let name = course.name.trimmingCharacters(in: .whitespaces)
        if name.count <= 14 { return name }
        // "Training - MEES Pre-Registration …" → "Training"; otherwise the first 12 characters.
        if let first = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" }).first, first.count >= 4 {
            return String(first)
        }
        return String(name.prefix(12)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "MATH 2241" pulled out of codes like "202680-MATH-2241-003-10505".
    var shortCode: String { Self.shortCode(from: course.courseCode) }

    static func shortCode(from raw: String?) -> String {
        guard let raw else { return "" }
        let pattern = #"([A-Z]{2,5})[- ]?(\d{3,4}[A-Z]?)"#
        if let match = raw.range(of: pattern, options: .regularExpression) {
            let text = String(raw[match])
            let parts = text.replacingOccurrences(of: "-", with: " ").split(separator: " ")
            if parts.count == 2 { return parts.joined(separator: " ") }
            return text
        }
        return raw
    }

    // MARK: Loading

    func loadGroups(force: Bool = false) async {
        let courseId = id
        await groups.load(app: app, force: force) { try await $0.assignmentGroups(course: courseId) }
    }

    func loadModules(force: Bool = false) async {
        let courseId = id
        await modules.load(app: app, force: force) { try await $0.modules(course: courseId) }
    }

    func loadFiles(force: Bool = false) async {
        let courseId = id
        async let a: Void = files.load(app: app, force: force) { try await $0.files(course: courseId) }
        async let b: Void = folders.load(app: app, force: force) { try await $0.folders(course: courseId) }
        _ = await (a, b)
    }

    func loadPages(force: Bool = false) async {
        let courseId = id
        await pages.load(app: app, force: force) { try await $0.pages(course: courseId) }
    }

    func loadAnnouncements(force: Bool = false) async {
        let courseId = id
        await announcements.load(app: app, force: force) { try await $0.announcements(courses: [courseId]) }
    }

    func loadDiscussions(force: Bool = false) async {
        let courseId = id
        await discussions.load(app: app, force: force) { try await $0.discussions(course: courseId) }
    }

    func loadQuizzes(force: Bool = false) async {
        let courseId = id
        await quizzes.load(app: app, force: force) { try await $0.quizzes(course: courseId) }
    }

    func loadPeople(force: Bool = false) async {
        let courseId = id
        await people.load(app: app, force: force) { try await $0.people(course: courseId) }
    }

    func loadGradingStandards(force: Bool = false) async {
        let courseId = id
        await gradingStandards.load(app: app, force: force) { try await $0.gradingStandards(course: courseId) }
    }

    /// Everything the Home tab needs from this course (grades + due dates).
    func loadForHome(force: Bool = false) async {
        await loadGroups(force: force)
    }

    /// Refreshes whatever has already been loaded, plus assignment groups.
    func refreshLoaded() async {
        await loadGroups(force: true)
        if modules.hasValue { await loadModules(force: true) }
        if files.hasValue { await loadFiles(force: true) }
        if pages.hasValue { await loadPages(force: true) }
        if announcements.hasValue { await loadAnnouncements(force: true) }
        if discussions.hasValue { await loadDiscussions(force: true) }
        if people.hasValue { await loadPeople(force: true) }
    }

    // MARK: Derived

    /// Sections this course actually supports, in display order. Overview, Assignments and Grades always show;
    /// the rest follow the course's enabled tabs, and drop out once Canvas answers 403/404 for them.
    var availableSections: [CourseSection] {
        CourseSection.allCases.filter { section in
            switch section {
            case .overview, .assignments, .grades: return true
            case .modules: return course.hasTab("modules") && !modules.unavailable
            case .files: return (course.hasTab("files") && !files.unavailable) || hasModuleFiles
            case .announcements: return course.hasTab("announcements") && !announcements.unavailable
            case .discussions: return course.hasTab("discussions") && !discussions.unavailable
            case .pages: return course.hasTab("pages") && !pages.unavailable
            case .syllabus: return course.hasTab("syllabus") || !(course.syllabusBody ?? "").isEmpty
            case .people: return course.hasTab("people") && !people.unavailable
            }
        }
    }

    /// Modules link to files even when the Files tab is disabled (common in this account's courses).
    var hasModuleFiles: Bool {
        (modules.value ?? []).contains { ($0.items ?? []).contains { $0.type == "File" } }
    }

    /// All assignments across groups.
    var assignments: [Assignment] { (groups.value ?? []).flatMap { $0.assignments ?? [] } }

    func assignment(_ id: CanvasID) -> Assignment? { assignments.first { $0.id == id } }

    var workItems: [WorkItem] {
        WorkItemBuilder.items(for: id, courseName: displayName, groups: groups.value ?? [])
    }

    var whatIf: WhatIf {
        get { app.settings.whatIf[id] ?? .none }
        set { app.settings.whatIf[id] = newValue.isEmpty ? nil : newValue }
    }

    /// The course's letter scheme: the user's custom cutoffs, else the course grading standard, else the app scale.
    var gradingScheme: GradingScheme {
        if let custom = preferences.customCutoffs, let scheme = GradingScheme(parsing: custom) { return scheme }
        if let standardId = course.gradingStandardId, let standard = gradingStandards.value?.first(where: { $0.id == standardId }) {
            return GradingScheme(standard: standard)
        }
        return app.settings.letterScale.scheme
    }

    /// Whether the letter comes from the course's own scheme (vs. the app's fallback scale).
    var hasCourseScheme: Bool {
        if let custom = preferences.customCutoffs, GradingScheme(parsing: custom) != nil { return true }
        guard let standardId = course.gradingStandardId else { return false }
        return gradingStandards.value?.contains { $0.id == standardId } ?? false
    }

    /// Canvas's own current score (from the enrollment) — the number the Grades page shows unless what-if is on.
    var canvasScore: Double? { course.studentEnrollment?.computedCurrentScore }
    var canvasLetter: String? {
        let letter = course.studentEnrollment?.computedCurrentLetterGrade ?? course.studentEnrollment?.computedCurrentGrade
        return (letter?.isEmpty ?? true) ? nil : letter
    }

    /// The computed grade (real submissions + what-if).
    var computedGrade: CourseGrade? {
        guard let groups = groups.value else { return nil }
        return GradeCalculator.compute(groups: groups, weighted: course.applyAssignmentGroupWeights ?? false, whatIf: whatIf)
    }

    /// Score to display: computed when what-if is active or Canvas hides its score, else Canvas's number.
    var displayScore: Double? {
        if !whatIf.isEmpty { return computedGrade?.percent }
        return canvasScore ?? computedGrade?.percent
    }

    /// Letter to display for `displayScore`. Canvas's own letter wins whenever the shown score is still Canvas's
    /// number — including a what-if that merely re-types the real score — so the chip and GPA don't flip because
    /// the app's fallback scale disagrees with a course scheme it can't read.
    var displayLetter: String? {
        if let letter = canvasLetter, preferences.customCutoffs == nil, whatIf.isEmpty || matchesCanvasScore { return letter }
        guard let score = displayScore else { return nil }
        return gradingScheme.letter(for: score)
    }

    private var matchesCanvasScore: Bool {
        guard let canvas = canvasScore, let percent = computedGrade?.percent else { return false }
        return abs(percent - canvas) < 0.005
    }

    /// The letter used for GPA (Canvas's letter when it has one, else derived).
    var gpaLetter: String? { displayLetter }

    /// The letter from real grades only (no what-if) — what the daily GPA history records.
    var actualLetter: String? {
        if preferences.customCutoffs == nil, let letter = canvasLetter { return letter }
        guard let score = canvasScore ?? GradeCalculator.compute(groups: groups.value ?? [], weighted: course.applyAssignmentGroupWeights ?? false).percent else { return nil }
        return gradingScheme.letter(for: score)
    }
}
