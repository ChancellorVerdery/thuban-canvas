import Foundation

/// A self-contained fake Canvas account (five Fall 2026 UNC Charlotte courses) used by the iOS smoke run, previews
/// and tests. Every date is relative to `now`, so the screens always read "Tomorrow · 11:59 PM" etc. No network:
/// `DemoTransport` serves these payloads to a `CanvasClient`, and anything that is not a GET is refused.
public struct DemoCanvas: Sendable {
    public static let host = "https://instructure.charlotte.edu"
    /// Obviously fake; never valid against a real server.
    public static let token = "demo-token-thuban-canvas-offline-fixture"
    public static var credentials: CanvasCredentials { CanvasCredentials(host: host, token: token) }
    public static let userId: CanvasID = 7000

    public let now: Date
    public let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    // MARK: Routing

    public struct Response: Sendable {
        public var status: Int
        public var body: Data
        public var contentType: String
    }

    /// The response for one request. Non-GET methods get 405.
    public func response(method: String, url: URL) -> Response {
        guard method.uppercased() == "GET" || method.uppercased() == "HEAD" else {
            return json(["message": "Demo Canvas is read-only"], status: 405)
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // File downloads live outside /api/v1.
        if parts.count >= 3, parts[0] == "files", parts[2] == "download", let id = CanvasID(parts[1]), let file = files.first(where: { $0.id == id }) {
            return Response(status: 200, body: Self.pdf(title: file.name, lines: file.lines), contentType: "application/pdf")
        }
        guard parts.count >= 2, parts[0] == "api", parts[1] == "v1" else { return notFound }
        let path = Array(parts.dropFirst(2))
        if let value = route(path, query: query) { return json(value) }
        return notFound
    }

    private var notFound: Response { json(["message": "The specified resource does not exist."], status: 404) }

    private func json(_ value: Any, status: Int = 200) -> Response {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return Response(status: status, body: data, contentType: "application/json")
    }

    private func values(_ query: [URLQueryItem], _ name: String) -> [String] {
        query.filter { $0.name == name }.compactMap(\.value)
    }

    private func route(_ path: [String], query: [URLQueryItem]) -> Any? {
        switch path.count {
        case 1:
            switch path[0] {
            case "courses": return courses.map(courseJSON)
            case "announcements":
                let codes = Set(values(query, "context_codes[]"))
                return announcements.filter { codes.isEmpty || codes.contains("course_\($0.course)") }.map(announcementJSON)
            case "calendar_events": return calendarEvents(query: query)
            case "conversations": return conversations(scope: values(query, "scope").first).map { conversationJSON($0, withMessages: false) }
            default: return nil
            }
        case 2:
            if path == ["users", "self"] { return user }
            if path == ["conversations", "unread_count"] { return ["unread_count": String(conversationList.filter(\.unread).count)] }
            if path[0] == "courses", let id = CanvasID(path[1]), let course = courses.first(where: { $0.id == id }) { return courseJSON(course) }
            if path[0] == "files", let id = CanvasID(path[1]), let file = files.first(where: { $0.id == id }) { return fileJSON(file) }
            if path[0] == "conversations", let id = CanvasID(path[1]), let c = conversationList.first(where: { $0.id == id }) { return conversationJSON(c, withMessages: true) }
            if path == ["planner", "items"] { return [Any]() }
            return nil
        default:
            break
        }
        if path.first == "users", path.count >= 3, path[1] == "self" {
            switch path[2...].joined(separator: "/") {
            case "favorites/courses": return courses.map(courseJSON)
            case "todo": return [Any]()
            case "missing_submissions":
                return courses.flatMap { course in
                    course.groups.flatMap(\.assignments).filter { $0.state == .missing }.map { a -> [String: Any] in
                        var object = assignmentJSON(a, course: course)
                        object["course_id"] = course.id
                        return object
                    }
                }
            case "activity_stream": return [Any]()
            default: return nil
            }
        }
        guard path.first == "courses", path.count >= 3, let id = CanvasID(path[1]), let course = courses.first(where: { $0.id == id }) else { return nil }
        let rest = Array(path.dropFirst(2))
        switch rest[0] {
        case "assignment_groups":
            return course.groups.enumerated().map { groupJSON($1, course: course, position: $0 + 1) }
        case "assignments":
            guard rest.count >= 2, let aid = CanvasID(rest[1]), let a = course.groups.flatMap(\.assignments).first(where: { $0.id == aid }) else { return nil }
            if rest.count == 4, rest[2] == "submissions", rest[3] == "self" { return submissionJSON(a) }
            return rest.count == 2 ? assignmentJSON(a, course: course) : nil
        case "grading_standards": return [Any]()
        case "modules": return course.id == 101 ? modules.map(moduleJSON) : (course.hasTab("modules") ? [Any]() : nil)
        case "pages":
            if rest.count == 1 { return course.hasTab("pages") || course.id == 101 ? pages.filter { $0.course == course.id }.map { pageJSON($0, body: false) } : nil }
            return pages.first { $0.course == course.id && $0.slug == rest[1] }.map { pageJSON($0, body: true) }
        case "front_page": return nil
        case "files":
            if rest.count == 1 { return course.hasTab("files") ? files.filter { $0.course == course.id }.map(fileJSON) : nil }
            return CanvasID(rest[1]).flatMap { fid in files.first { $0.id == fid } }.map(fileJSON)
        case "folders": return course.hasTab("files") ? [["id": course.id * 10, "name": "course files", "full_name": "course files", "files_count": files.filter { $0.course == course.id }.count, "folders_count": 0]] : nil
        case "discussion_topics":
            let list = discussions.filter { $0.course == course.id }
            if rest.count == 1 { return list.map(discussionJSON) }
            guard let tid = CanvasID(rest[1]), let topic = list.first(where: { $0.id == tid }) else { return nil }
            if rest.count == 3, rest[2] == "view" { return discussionViewJSON(topic) }
            return discussionJSON(topic)
        case "quizzes": return [Any]()
        case "users": return course.id == 101 ? people : [Any]()
        default: return nil
        }
    }

    // MARK: Dates

    /// Local wall-clock time `days` from today.
    func at(_ days: Int, _ hour: Int = 23, _ minute: Int = 59) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func stamp(_ date: Date?) -> Any { date.map { Self.iso.string(from: $0) } ?? NSNull() }

    // MARK: Data model

    struct DemoCourse {
        var id: CanvasID
        var code: String
        var name: String
        var teacher: String
        var score: Double
        var letter: String
        var weighted: Bool
        var tabs: [String]
        var syllabus: String
        var groups: [DemoGroup]

        func hasTab(_ tab: String) -> Bool { tabs.contains(tab) }
    }

    struct DemoGroup {
        var id: CanvasID
        var name: String
        var weight: Double
        var dropLowest: Int = 0
        var assignments: [DemoAssignment]
    }

    enum State { case unsubmitted, submitted, graded, missing }

    struct DemoAssignment {
        var id: CanvasID
        var name: String
        var points: Double
        var due: Date?
        var types: [String]
        var state: State = .unsubmitted
        var score: Double? = nil
        var gradedAt: Date? = nil
        var submittedAt: Date? = nil
        var unlockAt: Date? = nil
        var locked = false
        var quizId: CanvasID? = nil
        var extensions: [String]? = nil
        var attempts: Int = -1
        var description: String? = nil
        var stats: [String: Double]? = nil
    }

    var user: [String: Any] {
        ["id": Self.userId, "name": "Alex Morgan", "short_name": "Alex", "sortable_name": "Morgan, Alex"]
    }

    var courses: [DemoCourse] {
        let standardTabs = ["home", "announcements", "assignments", "discussions", "grades", "people", "syllabus"]
        return [
            DemoCourse(id: 101, code: "202680-MATH-2171-002-10501", name: "Differential Equations", teacher: "Dr. Lena Brennan",
                       score: 90.54, letter: "A", weighted: true, tabs: standardTabs + ["modules"],
                       syllabus: "<h2>MATH 2171 · Differential Equations</h2><p>Lectures MWF 11:15 AM in Fretwell 100. Office hours Tuesday and Thursday 2:00–3:30 PM in Fretwell 311.</p><h3>Grading</h3><table><tr><th>Homework</th><td>25%</td></tr><tr><th>Quizzes (lowest dropped)</th><td>15%</td></tr><tr><th>Exams</th><td>45%</td></tr><tr><th>Participation</th><td>15%</td></tr></table><p>Late homework loses 10% per day, up to three days.</p>",
                       groups: math2171Groups),
            DemoCourse(id: 102, code: "202680-MATH-2241-003-10505", name: "Calculus III", teacher: "Mark Ellison",
                       score: 86.2, letter: "B", weighted: false, tabs: standardTabs + ["files"],
                       syllabus: "<p>Multivariable calculus: vectors, partial derivatives, multiple integrals and vector fields. Homework is on WebAssign.</p>",
                       groups: [
                           DemoGroup(id: 10210, name: "WebAssign", weight: 0, assignments: [
                               DemoAssignment(id: 10211, name: "WebAssign 15.1 · Double integrals", points: 10, due: at(-6), types: ["external_tool"], state: .graded, score: 10, gradedAt: at(-5, 9, 0)),
                               DemoAssignment(id: 10212, name: "WebAssign 15.2 · Iterated integrals", points: 10, due: at(-1), types: ["external_tool"], state: .graded, score: 9, gradedAt: at(0, 7, 30)),
                               DemoAssignment(id: 10213, name: "WebAssign 15.3 · Polar integrals", points: 10, due: at(2), types: ["external_tool"]),
                           ]),
                           DemoGroup(id: 10220, name: "Exams", weight: 0, assignments: [
                               DemoAssignment(id: 10221, name: "Exam 1", points: 100, due: at(-10, 9, 30), types: ["on_paper"], state: .graded, score: 84, gradedAt: at(-4, 16, 0)),
                               DemoAssignment(id: 10222, name: "Exam 2", points: 100, due: at(24, 9, 30), types: ["on_paper"]),
                           ]),
                       ]),
            DemoCourse(id: 103, code: "202680-PHYS-2102-001-11020", name: "Physics for Science & Engineering II", teacher: "Dr. Helen Okafor",
                       score: 88.9, letter: "B", weighted: false, tabs: standardTabs + ["files", "pages"],
                       syllabus: "<p>Electricity and magnetism with laboratory. Pre-labs close at 11:59 PM the night before your section meets.</p>",
                       groups: [
                           DemoGroup(id: 10310, name: "Pre-labs", weight: 0, assignments: [
                               DemoAssignment(id: 10311, name: "Pre-lab 4 · Capacitors", points: 10, due: at(-9), types: ["online_upload"], state: .graded, score: 9, gradedAt: at(-6, 12, 0), submittedAt: at(-9, 20, 0)),
                               DemoAssignment(id: 10312, name: "Pre-lab 5 · RC circuits", points: 10, due: at(-2), types: ["online_upload"], state: .missing),
                           ]),
                           DemoGroup(id: 10320, name: "Quizzes", weight: 0, assignments: [
                               DemoAssignment(id: 10321, name: "Quiz 2 · Electric fields", points: 10, due: at(-7, 12, 30), types: ["online_quiz"], state: .graded, score: 8.5, gradedAt: at(-7, 13, 0)),
                               DemoAssignment(id: 10322, name: "Quiz 3 · Gauss’s law", points: 10, due: at(4, 12, 30), types: ["online_quiz"], quizId: 3322),
                           ]),
                           DemoGroup(id: 10330, name: "Exams", weight: 0, assignments: [
                               DemoAssignment(id: 10331, name: "Exam 1", points: 100, due: at(12, 12, 30), types: ["on_paper"]),
                           ]),
                       ]),
            DemoCourse(id: 104, code: "202680-ECGR-2161-003-12011", name: "Basic Electrical Engineering II", teacher: "Priya Natarajan",
                       score: 94.0, letter: "A", weighted: false, tabs: standardTabs + ["files"],
                       syllabus: "<p>AC circuit analysis, phasors, Thévenin and Norton equivalents, and operational amplifiers. Lab reports are due at 8:00 AM on lab day.</p>",
                       groups: [
                           DemoGroup(id: 10410, name: "Labs", weight: 0, assignments: [
                               DemoAssignment(id: 10414, name: "Lab 2 report · Superposition", points: 50, due: at(-9, 8, 0), types: ["online_upload"], state: .graded, score: 47, gradedAt: at(-5, 15, 0), submittedAt: at(-10, 22, 0)),
                               DemoAssignment(id: 10411, name: "Lab 3 report · Kirchhoff", points: 50, due: at(-2, 8, 0), types: ["online_upload"], state: .submitted, submittedAt: at(-3, 21, 40)),
                               DemoAssignment(id: 10412, name: "Lab 4 report · Thévenin", points: 50, due: at(3, 8, 0), types: ["online_upload"], extensions: ["pdf"]),
                           ]),
                           DemoGroup(id: 10420, name: "Homework", weight: 0, assignments: [
                               DemoAssignment(id: 10413, name: "Homework 3", points: 20, due: at(-8), types: ["online_upload"], state: .graded, score: 19, gradedAt: at(-4, 10, 0), submittedAt: at(-8, 19, 0)),
                           ]),
                       ]),
            DemoCourse(id: 105, code: "202680-ENGL-2116-004-13302", name: "Technical Communication", teacher: "Dr. Marcus Hale",
                       score: 97.5, letter: "A", weighted: false, tabs: standardTabs,
                       syllabus: "<p>Writing for engineering audiences: memos, résumés, proposals and a team report. Peer review happens in class on Thursdays.</p>",
                       groups: [
                           DemoGroup(id: 10510, name: "Assignments", weight: 0, assignments: [
                               DemoAssignment(id: 10514, name: "Résumé", points: 50, due: at(-12), types: ["online_upload"], state: .graded, score: 48.5, gradedAt: at(-6, 11, 0), submittedAt: at(-12, 18, 0)),
                               DemoAssignment(id: 10511, name: "Reading response 3", points: 5, due: at(-5), types: ["online_text_entry"], state: .graded, score: 5, gradedAt: at(-3, 9, 0), submittedAt: at(-5, 21, 0)),
                               DemoAssignment(id: 10512, name: "Reading response 4", points: 5, due: at(2), types: ["online_text_entry"]),
                               DemoAssignment(id: 10513, name: "Memo draft", points: 25, due: at(6), types: ["online_upload"], extensions: ["docx", "pdf"]),
                           ]),
                       ]),
        ]
    }

    var math2171Groups: [DemoGroup] {
        let ps5 = """
        <p>Complete these problems from the text. Show every step; answers without work get no credit.</p>
        <p><strong>6.1</strong> #3, 7, 12, 19 &nbsp;&nbsp; <strong>6.2</strong> #5, 9, 18 &nbsp;&nbsp; <strong>6.3</strong> #4, 11</p>
        <p>Scan everything into a single PDF, in problem order.</p>
        <p><a class="instructure_file_link" title="PS5.pdf" href="\(Self.host)/courses/101/files/9001?verifier=demo&amp;wrap=1" data-api-endpoint="\(Self.host)/api/v1/courses/101/files/9001" data-api-returntype="File">PS5.pdf</a></p>
        """
        return [
            DemoGroup(id: 10110, name: "Homework", weight: 25, assignments: [
                DemoAssignment(id: 10111, name: "Problem Set 1", points: 20, due: at(-26), types: ["online_upload"], state: .graded, score: 19, gradedAt: at(-23, 10, 0), submittedAt: at(-26, 22, 10)),
                DemoAssignment(id: 10112, name: "Problem Set 2", points: 20, due: at(-19), types: ["online_upload"], state: .graded, score: 19, gradedAt: at(-16, 10, 0), submittedAt: at(-19, 21, 0)),
                DemoAssignment(id: 10113, name: "Problem Set 3", points: 20, due: at(-12), types: ["online_upload"], state: .graded, score: 18.5, gradedAt: at(-9, 10, 0), submittedAt: at(-12, 23, 30)),
                DemoAssignment(id: 10114, name: "Problem Set 4", points: 20, due: at(-5), types: ["online_upload"], state: .graded, score: 19, gradedAt: at(-3, 10, 0), submittedAt: at(-5, 20, 45)),
                DemoAssignment(id: 10115, name: "Problem Set 5", points: 20, due: at(1), types: ["online_upload"], extensions: ["pdf"], description: ps5),
                DemoAssignment(id: 10116, name: "Problem Set 6", points: 20, due: at(8), types: ["online_upload"], extensions: ["pdf"]),
            ]),
            DemoGroup(id: 10120, name: "Quizzes", weight: 15, dropLowest: 1, assignments: [
                DemoAssignment(id: 10121, name: "Quiz 1", points: 10, due: at(-22, 12, 0), types: ["online_quiz"], state: .graded, score: 9, gradedAt: at(-22, 12, 5), quizId: 3101),
                DemoAssignment(id: 10122, name: "Quiz 2", points: 10, due: at(-15, 12, 0), types: ["online_quiz"], state: .graded, score: 5, gradedAt: at(-15, 12, 5), quizId: 3102),
                DemoAssignment(id: 10123, name: "Quiz 3", points: 10, due: at(-8, 12, 0), types: ["online_quiz"], state: .graded, score: 8.5, gradedAt: at(-8, 12, 5), quizId: 3103),
                DemoAssignment(id: 10124, name: "Quiz 4", points: 10, due: at(-3, 12, 0), types: ["online_quiz"], state: .graded, score: 9, gradedAt: at(-2, 9, 0), quizId: 3104),
                DemoAssignment(id: 10125, name: "Quiz 5", points: 10, due: at(5), types: ["online_quiz"], unlockAt: at(3, 8, 0), locked: true, quizId: 3105),
            ]),
            DemoGroup(id: 10130, name: "Exams", weight: 45, assignments: [
                DemoAssignment(id: 10131, name: "Exam 1", points: 100, due: at(-9, 11, 15), types: ["on_paper"], state: .graded, score: 86, gradedAt: at(-7, 17, 0),
                               stats: ["min": 52, "max": 98, "mean": 78.4, "median": 79, "lower_q": 71, "upper_q": 88]),
                DemoAssignment(id: 10132, name: "Exam 2", points: 100, due: at(19, 11, 15), types: ["on_paper"]),
            ]),
            DemoGroup(id: 10140, name: "Participation", weight: 15, assignments: [
                DemoAssignment(id: 10141, name: "Participation (to date)", points: 15, due: nil, types: ["none"], state: .graded, score: 15, gradedAt: at(-6, 9, 0)),
            ]),
        ]
    }

    // MARK: Modules, pages, files

    struct DemoFile { var id: CanvasID; var course: CanvasID; var name: String; var size: Int; var updated: Int; var lines: [String] }

    var files: [DemoFile] {
        [
            DemoFile(id: 9001, course: 101, name: "PS5.pdf", size: 96_000, updated: -6, lines: ["MATH 2171 · Problem Set 5", "Laplace transforms", "6.1 #3, 7, 12, 19", "6.2 #5, 9, 18", "6.3 #4, 11"]),
            DemoFile(id: 9002, course: 101, name: "Laplace transform table.pdf", size: 184_000, updated: -6, lines: ["Table of Laplace transforms", "L{1} = 1/s", "L{t^n} = n!/s^(n+1)", "L{e^(at)} = 1/(s - a)", "L{sin bt} = b/(s^2 + b^2)", "L{cos bt} = s/(s^2 + b^2)"]),
            DemoFile(id: 9003, course: 101, name: "PS4 solutions.pdf", size: 412_000, updated: -2, lines: ["MATH 2171 · Problem Set 4 solutions"]),
            DemoFile(id: 9101, course: 104, name: "Lab 4 bench assignments.pdf", size: 58_000, updated: -1, lines: ["ECGR 2161 · Lab 4 bench assignments"]),
            DemoFile(id: 9102, course: 104, name: "Thévenin worked example.pdf", size: 231_000, updated: -4, lines: ["Thevenin equivalent: worked example"]),
            DemoFile(id: 9103, course: 104, name: "Lab 4 handout.pdf", size: 144_000, updated: -6, lines: ["ECGR 2161 · Lab 4 handout"]),
            DemoFile(id: 9201, course: 103, name: "Pre-lab 5 handout.pdf", size: 120_000, updated: -8, lines: ["PHYS 2102 · Pre-lab 5 · RC circuits"]),
            DemoFile(id: 9202, course: 102, name: "Exam 1 formula sheet.pdf", size: 88_000, updated: -12, lines: ["MATH 2241 · Exam 1 formula sheet"]),
        ]
    }

    struct DemoPage { var course: CanvasID; var slug: String; var title: String; var body: String }

    var pages: [DemoPage] {
        [
            DemoPage(course: 101, slug: "lecture-notes-6-1-6-2", title: "Lecture notes 6.1–6.2",
                     body: "<h2>6.1 Definition of the Laplace transform</h2><p>For a function f(t) defined for t ≥ 0, the Laplace transform is F(s) = ∫₀^∞ e^(−st) f(t) dt, whenever the integral converges.</p><h2>6.2 Solving initial value problems</h2><p>Transform both sides, solve the algebraic equation for Y(s), then invert using the table.</p>"),
            DemoPage(course: 101, slug: "lecture-notes-4-1-4-3", title: "Lecture notes 4.1–4.3",
                     body: "<p>Second-order linear equations with constant coefficients: characteristic equation, repeated roots, complex roots.</p>"),
            DemoPage(course: 103, slug: "lab-safety", title: "Lab safety", body: "<p>Closed-toe shoes in the lab at all times. Report damaged equipment to your TA.</p>"),
        ]
    }

    struct DemoItem { var id: CanvasID; var type: String; var title: String; var content: CanvasID?; var page: String? = nil; var external: String? = nil; var requirement: String?; var minScore: Double? = nil; var done: Bool; var due: Date? = nil; var points: Double? = nil; var locked: Bool = false; var unlock: Date? = nil }
    struct DemoModule { var id: CanvasID; var position: Int; var name: String; var state: String; var unlock: Date?; var items: [DemoItem] }

    var modules: [DemoModule] {
        let names = ["First-order equations", "Separable and exact equations", "Applications and modeling", "Second-order linear equations",
                     "Laplace transforms", "Systems of equations", "Eigenvalue methods", "Exam 2 review", "Nonhomogeneous systems",
                     "Series solutions", "Fourier series", "Boundary value problems", "The heat equation", "The wave equation", "Final review"]
        return names.enumerated().map { index, name in
            let week = index + 1
            let id: CanvasID = 4000 + week
            let items: [DemoItem]
            switch week {
            case 4:
                items = [
                    DemoItem(id: 40401, type: "Page", title: "Lecture notes 4.1–4.3", content: nil, page: "lecture-notes-4-1-4-3", requirement: "must_view", done: true),
                    DemoItem(id: 40402, type: "Assignment", title: "Problem Set 4", content: 10114, requirement: "must_submit", done: true, due: at(-5), points: 20),
                    DemoItem(id: 40403, type: "File", title: "PS4 solutions.pdf", content: 9003, requirement: "must_view", done: true),
                    DemoItem(id: 40404, type: "Quiz", title: "Quiz 4", content: 3104, requirement: "min_score", minScore: 8, done: true, due: at(-3, 12, 0), points: 10),
                    DemoItem(id: 40405, type: "Page", title: "Worked examples: undetermined coefficients", content: nil, page: "lecture-notes-4-1-4-3", requirement: "must_view", done: true),
                    DemoItem(id: 40406, type: "ExternalUrl", title: "Paul’s Notes: Second-order equations", content: nil, external: "https://tutorial.math.lamar.edu/Classes/DE/IntroSecondOrder.aspx", requirement: "must_view", done: true),
                ]
            case 5:
                items = [
                    DemoItem(id: 40501, type: "Page", title: "Lecture notes 6.1–6.2", content: nil, page: "lecture-notes-6-1-6-2", requirement: "must_view", done: true),
                    DemoItem(id: 40502, type: "File", title: "Laplace transform table.pdf", content: 9002, requirement: "must_view", done: true),
                    DemoItem(id: 40503, type: "Assignment", title: "Problem Set 5", content: 10115, requirement: "must_submit", done: false, due: at(1), points: 20),
                    DemoItem(id: 40504, type: "Quiz", title: "Quiz 5", content: 3105, requirement: "min_score", minScore: 8, done: false, due: at(5), points: 10, locked: true, unlock: at(3, 8, 0)),
                    DemoItem(id: 40505, type: "ExternalUrl", title: "Paul’s Notes: Laplace transforms", content: nil, external: "https://tutorial.math.lamar.edu/Classes/DE/LaplaceIntro.aspx", requirement: "must_view", done: false),
                ]
            case 6:
                items = [
                    DemoItem(id: 40601, type: "SubHeader", title: "Read before Monday", content: nil, requirement: nil, done: false),
                    DemoItem(id: 40602, type: "Assignment", title: "Problem Set 6", content: 10116, requirement: "must_submit", done: false, due: at(8), points: 20, locked: true, unlock: at(10, 8, 0)),
                ]
            default:
                items = week < 4
                    ? [DemoItem(id: CanvasID(40000 + week * 100 + 1), type: "Page", title: "Lecture notes, week \(week)", content: nil, page: "lecture-notes-4-1-4-3", requirement: "must_view", done: true),
                       DemoItem(id: CanvasID(40000 + week * 100 + 2), type: "Assignment", title: "Problem Set \(week)", content: CanvasID(10110 + week), requirement: "must_submit", done: true, due: at(-26 + (week - 1) * 7), points: 20)]
                    : []
            }
            let state = week < 5 ? "completed" : (week == 5 ? "started" : "locked")
            let unlock: Date? = week > 5 ? at(10 + (week - 6) * 7, 8, 0) : nil
            return DemoModule(id: id, position: week, name: "Week \(week): \(name)", state: state, unlock: unlock, items: items)
        }
    }

    // MARK: Announcements, discussions, people, events, inbox

    struct DemoAnnouncement { var id: CanvasID; var course: CanvasID; var title: String; var author: String; var posted: Date; var unread: Bool; var message: String }

    var announcements: [DemoAnnouncement] {
        [
            DemoAnnouncement(id: 70101, course: 101, title: "Exam 2 moves to Wednesday, October 14", author: "Dr. Lena Brennan", posted: at(-1, 15, 20), unread: true,
                             message: "<p>Exam 2 will be in class on <strong>Wednesday, October 14</strong>. It covers Laplace transforms and systems (6.1–7.3). A review sheet is posted under Modules › Week 8.</p>"),
            DemoAnnouncement(id: 70102, course: 101, title: "Office hours move to Fretwell 311 this week", author: "Dr. Lena Brennan", posted: at(-5, 9, 0), unread: false,
                             message: "<p>Tuesday and Thursday office hours are in Fretwell 311 this week only.</p>"),
            DemoAnnouncement(id: 70201, course: 102, title: "WebAssign 15.2 extended to Friday", author: "Mark Ellison", posted: at(-3, 18, 5), unread: false,
                             message: "<p>Because of the server outage Tuesday night, 15.2 is due Friday at 11:59 PM.</p>"),
            DemoAnnouncement(id: 70301, course: 103, title: "Exam 1 review session today at 4 PM", author: "Dr. Helen Okafor", posted: at(-2, 11, 0), unread: true,
                             message: "<p>Review session in Grigg 132 from 4:00 to 5:30 PM. Bring questions from chapters 21–24.</p>"),
            DemoAnnouncement(id: 70401, course: 104, title: "Lab 4 bench assignments posted", author: "Priya Natarajan", posted: at(-1, 13, 0), unread: false,
                             message: "<p>Bench numbers for Monday are posted in Files › Lab 4.</p>"),
        ]
    }

    struct DemoTopic { var id: CanvasID; var course: CanvasID; var title: String; var author: String; var posted: Date; var lastReply: Date; var replies: Int; var unread: Int; var message: String }

    var discussions: [DemoTopic] {
        [
            DemoTopic(id: 71101, course: 101, title: "Week 5: Laplace transform questions", author: "Dr. Lena Brennan", posted: at(-3, 9, 0), lastReply: at(0, 8, 40), replies: 6, unread: 2,
                      message: "<p>Post questions about 6.1–6.3 here. Please include the problem number.</p>"),
            DemoTopic(id: 71102, course: 101, title: "Study groups for Exam 2", author: "Dr. Lena Brennan", posted: at(-2, 12, 0), lastReply: at(-1, 21, 0), replies: 11, unread: 0,
                      message: "<p>Reply with your availability if you want to join or start a study group.</p>"),
            DemoTopic(id: 71103, course: 101, title: "Introduce yourself", author: "Dr. Lena Brennan", posted: at(-30, 9, 0), lastReply: at(-20, 16, 0), replies: 38, unread: 0,
                      message: "<p>Tell us your major and one thing you hope to get out of this course.</p>"),
            DemoTopic(id: 71301, course: 103, title: "Lab partner swaps", author: "Dr. Helen Okafor", posted: at(-9, 9, 0), lastReply: at(-6, 10, 0), replies: 4, unread: 0,
                      message: "<p>If you need to change lab partners, post here by Friday.</p>"),
        ]
    }

    var people: [[String: Any]] {
        let first = ["Aiden", "Bianca", "Caleb", "Dana", "Elijah", "Fatima", "Gavin", "Hana", "Isaac", "Jasmine", "Kofi", "Lauren", "Mateo",
                     "Nadia", "Owen", "Priya", "Quinn", "Rosa", "Samir", "Tessa", "Uriel", "Vera", "Wes", "Ximena", "Yusuf", "Zoe",
                     "Andre", "Brooke", "Chen", "Delia", "Ethan", "Grace", "Hector", "Ivy", "Jonah", "Kira", "Liam", "Maya"]
        let last = ["Adams", "Bose", "Carter", "Diaz", "Evans", "Farah", "Greene", "Hughes", "Ito", "Jackson", "Kim", "Lopez", "Mensah",
                    "Nguyen", "Ortiz", "Patel", "Quintero", "Reyes", "Shah", "Tran", "Underwood", "Vance", "Walker", "Xu", "Young", "Zimmer"]
        var list: [[String: Any]] = [
            ["id": 7101, "name": "Lena Brennan", "sortable_name": "Brennan, Lena", "short_name": "Dr. Brennan", "pronouns": "she/her", "enrollments": [["type": "TeacherEnrollment"]]],
            ["id": 7102, "name": "Marco Diaz", "sortable_name": "Diaz, Marco", "short_name": "Marco Diaz", "enrollments": [["type": "TaEnrollment"]]],
            ["id": Self.userId, "name": "Alex Morgan", "sortable_name": "Morgan, Alex", "short_name": "Alex", "enrollments": [["type": "StudentEnrollment"]]],
        ]
        for index in 0..<38 {
            let name = "\(first[index % first.count]) \(last[(index * 7) % last.count])"
            let parts = name.split(separator: " ")
            list.append(["id": 7200 + index, "name": name, "sortable_name": "\(parts[1]), \(parts[0])", "short_name": name, "enrollments": [["type": "StudentEnrollment"]]])
        }
        return list.sorted { ($0["sortable_name"] as? String ?? "") < ($1["sortable_name"] as? String ?? "") }
    }

    func calendarEvents(query: [URLQueryItem]) -> [[String: Any]] {
        let codes = Set(values(query, "context_codes[]"))
        let start = values(query, "start_date").first.flatMap { CanvasClient.parseDate($0) } ?? .distantPast
        let end = values(query, "end_date").first.flatMap { CanvasClient.parseDate($0) } ?? .distantFuture
        let events: [(CanvasID, CanvasID, String, Date, Date, String)] = [
            (80001, 103, "Exam 1 review session", at(0, 16, 0), at(0, 17, 30), "Grigg 132"),
            (80002, 104, "Lab 4 office hours", at(0, 17, 30), at(0, 19, 0), "EPIC 1228"),
            (80003, 101, "Office hours · Dr. Brennan", at(4, 14, 0), at(4, 15, 30), "Fretwell 311"),
            (80004, 105, "Peer review workshop", at(6, 9, 30), at(6, 10, 45), "Colvard 2078"),
            (80005, 101, "Exam 2 (in class)", at(19, 11, 15), at(19, 12, 30), "Fretwell 100"),
            (80006, 104, "Lab 3", at(-2, 8, 0), at(-2, 10, 45), "EPIC 1228"),
        ]
        return events.filter { (codes.isEmpty || codes.contains("course_\($0.1)")) && $0.3 >= start && $0.3 < end }.map { event in
            let course = courses.first { $0.id == event.1 }
            return ["id": event.0, "title": event.2, "start_at": stamp(event.3), "end_at": stamp(event.4), "location_name": event.5,
                    "context_code": "course_\(event.1)", "context_name": course?.name ?? "", "all_day": false, "workflow_state": "active",
                    "type": "event", "html_url": "\(Self.host)/calendar?event_id=\(event.0)",
                    "description": "<p>\(event.2) in \(event.5).</p>"] as [String: Any]
        }
    }

    struct DemoConversation { var id: CanvasID; var subject: String; var course: CanvasID; var from: [(CanvasID, String)]; var at: Date; var unread: Bool; var starred: Bool; var sent: Bool; var messages: [(CanvasID, Date, String)] }

    var conversationList: [DemoConversation] {
        let me = Self.userId
        return [
            DemoConversation(id: 501, subject: "Re: Exam 1 regrade request", course: 102, from: [(7301, "Mark Ellison")], at: at(0, 10, 42), unread: true, starred: false, sent: false, messages: [
                (7301, at(0, 10, 42), "I took another look at problem 4. You are right that the bounds on theta were fine; I have added the 3 points back."),
                (me, at(-3, 21, 5), "Could you take another look at problem 4? I think my bounds were correct."),
            ]),
            DemoConversation(id: 502, subject: "Lab 4 bench assignments", course: 104, from: [(7401, "Priya Natarajan")], at: at(-1, 16, 20), unread: true, starred: false, sent: false, messages: [
                (7401, at(-1, 16, 20), "Bench numbers for Monday are posted in Files > Lab 4. Bring your own breadboard jumpers if you have them."),
            ]),
            DemoConversation(id: 503, subject: "Peer review pairs", course: 105, from: [(7501, "Ana Ruiz"), (7502, "Ben Pokroy")], at: at(-2, 19, 0), unread: false, starred: true, sent: false, messages: [
                (7502, at(-2, 19, 0), "Ben: I can swap drafts Sunday night if that works for both of you."),
                (7501, at(-2, 17, 30), "We are paired for the memo peer review. Can we trade drafts this weekend?"),
            ]),
            DemoConversation(id: 504, subject: "Pre-lab 5 due date", course: 103, from: [(7601, "Dr. Helen Okafor")], at: at(-3, 8, 15), unread: false, starred: false, sent: false, messages: [
                (7601, at(-3, 8, 15), "Reminder that pre-labs close at 11:59 PM the night before your section meets. No late pre-labs this term."),
            ]),
            DemoConversation(id: 505, subject: "Problem Set 4 solutions", course: 101, from: [(7101, "Dr. Lena Brennan")], at: at(-7, 14, 0), unread: false, starred: false, sent: false, messages: [
                (7101, at(-7, 14, 0), "Solutions are posted under Modules > Week 4. Office hours move to Fretwell 311 this week."),
            ]),
            DemoConversation(id: 506, subject: "Exam 1 regrade request", course: 102, from: [(7301, "Mark Ellison")], at: at(-3, 21, 5), unread: false, starred: false, sent: true, messages: [
                (me, at(-3, 21, 5), "Could you take another look at problem 4? I think my bounds were correct."),
            ]),
        ]
    }

    func conversations(scope: String?) -> [DemoConversation] {
        switch scope {
        case "unread": return conversationList.filter { $0.unread }
        case "starred": return conversationList.filter { $0.starred }
        case "sent": return conversationList.filter { $0.sent }
        case "archived": return []
        default: return conversationList.filter { !$0.sent }
        }
    }

    // MARK: JSON builders

    func courseJSON(_ course: DemoCourse) -> [String: Any] {
        let tabLabels = ["home": "Home", "announcements": "Announcements", "assignments": "Assignments", "discussions": "Discussions",
                         "grades": "Grades", "people": "People", "syllabus": "Syllabus", "modules": "Modules", "files": "Files", "pages": "Pages"]
        return [
            "id": course.id, "name": course.name, "course_code": course.code, "workflow_state": "available", "enrollment_term_id": 1,
            "term": ["id": 1, "name": "Fall 2026", "start_at": "2026-08-17T04:00:00Z", "end_at": "2026-12-12T05:00:00Z"],
            "enrollments": [["type": "student", "role": "StudentEnrollment", "enrollment_state": "active",
                             "computed_current_score": course.score, "computed_current_grade": course.letter,
                             "computed_current_letter_grade": course.letter]],
            "teachers": [["id": 7100 + course.id - 100, "display_name": course.teacher]],
            "tabs": course.tabs.enumerated().map { index, tab in ["id": tab, "label": tabLabels[tab] ?? tab, "type": "internal", "position": index + 1] },
            "syllabus_body": course.syllabus, "apply_assignment_group_weights": course.weighted, "is_favorite": true,
            "default_view": course.hasTab("modules") ? "modules" : "syllabus", "time_zone": "America/New_York",
        ]
    }

    func groupJSON(_ group: DemoGroup, course: DemoCourse, position: Int) -> [String: Any] {
        var object: [String: Any] = ["id": group.id, "name": group.name, "position": position, "group_weight": group.weight,
                                     "assignments": group.assignments.map { assignmentJSON($0, course: course, group: group.id) }]
        object["rules"] = group.dropLowest > 0 ? ["drop_lowest": group.dropLowest] : [String: Any]()
        return object
    }

    func assignmentJSON(_ a: DemoAssignment, course: DemoCourse, group: CanvasID? = nil) -> [String: Any] {
        var object: [String: Any] = [
            "id": a.id, "course_id": course.id, "name": a.name, "due_at": stamp(a.due), "points_possible": a.points, "grading_type": "points",
            "assignment_group_id": group ?? course.groups.first { $0.assignments.contains { $0.id == a.id } }?.id ?? 0,
            "submission_types": a.types, "allowed_attempts": a.attempts, "html_url": "\(Self.host)/courses/\(course.id)/assignments/\(a.id)",
            "published": true, "locked_for_user": a.locked, "unlock_at": stamp(a.unlockAt), "submission": submissionJSON(a),
        ]
        if let description = a.description { object["description"] = description }
        if let extensions = a.extensions { object["allowed_extensions"] = extensions }
        if let quizId = a.quizId { object["quiz_id"] = quizId; object["is_quiz_assignment"] = true }
        if a.locked, let unlock = a.unlockAt { object["lock_explanation"] = "This assignment is locked until \(DueFormatter.full(unlock, calendar: calendar))." }
        if let stats = a.stats { object["score_statistics"] = stats }
        return object
    }

    func submissionJSON(_ a: DemoAssignment) -> [String: Any] {
        var object: [String: Any] = ["assignment_id": a.id, "user_id": Self.userId, "late": false, "missing": false, "excused": false]
        switch a.state {
        case .unsubmitted:
            object["workflow_state"] = "unsubmitted"; object["attempt"] = NSNull(); object["score"] = NSNull()
        case .missing:
            object["workflow_state"] = "unsubmitted"; object["missing"] = true; object["attempt"] = NSNull(); object["score"] = NSNull()
        case .submitted:
            object["workflow_state"] = "submitted"; object["attempt"] = 1; object["submitted_at"] = stamp(a.submittedAt); object["submission_type"] = a.types.first ?? "online_upload"
        case .graded:
            object["workflow_state"] = "graded"; object["score"] = a.score ?? 0; object["grade"] = DueFormatter.points(a.score)
            object["graded_at"] = stamp(a.gradedAt); object["posted_at"] = stamp(a.gradedAt)
            if let submitted = a.submittedAt { object["submitted_at"] = stamp(submitted); object["attempt"] = 1 }
        }
        return object
    }

    func moduleJSON(_ module: DemoModule) -> [String: Any] {
        [
            "id": module.id, "name": module.name, "position": module.position, "state": module.state, "unlock_at": stamp(module.unlock),
            "items_count": module.items.count, "completed_at": module.state == "completed" ? stamp(at(-26 + module.position * 7, 20, 0)) : NSNull(),
            "items": module.items.enumerated().map { index, item in
                var object: [String: Any] = ["id": item.id, "module_id": module.id, "position": index + 1, "title": item.title, "type": item.type,
                                             "indent": 0, "published": true,
                                             "html_url": "\(Self.host)/courses/101/modules/items/\(item.id)"]
                if let content = item.content { object["content_id"] = content }
                if let page = item.page { object["page_url"] = page }
                if let external = item.external { object["external_url"] = external; object["new_tab"] = true }
                if let requirement = item.requirement {
                    var req: [String: Any] = ["type": requirement, "completed": item.done]
                    if let min = item.minScore { req["min_score"] = min }
                    object["completion_requirement"] = req
                }
                var details: [String: Any] = ["locked_for_user": item.locked]
                if let due = item.due { details["due_at"] = stamp(due) }
                if let points = item.points { details["points_possible"] = points }
                if let unlock = item.unlock { details["unlock_at"] = stamp(unlock) }
                object["content_details"] = details
                return object
            } as [[String: Any]],
        ]
    }

    func fileJSON(_ file: DemoFile) -> [String: Any] {
        [
            "id": file.id, "folder_id": file.course * 10, "display_name": file.name, "filename": file.name.replacingOccurrences(of: " ", with: "+"),
            "content-type": "application/pdf", "size": file.size, "mime_class": "pdf",
            "url": "\(Self.host)/files/\(file.id)/download?download_frd=1&verifier=demo",
            "created_at": stamp(at(file.updated, 9, 0)), "updated_at": stamp(at(file.updated, 9, 0)), "locked": false, "hidden": false, "locked_for_user": false,
        ]
    }

    func pageJSON(_ page: DemoPage, body: Bool) -> [String: Any] {
        var object: [String: Any] = ["page_id": page.slug.unicodeScalars.reduce(page.course * 1_000) { $0 + Int($1.value) }, "url": page.slug, "title": page.title, "published": true,
                                     "updated_at": stamp(at(-6, 9, 0)), "html_url": "\(Self.host)/courses/\(page.course)/pages/\(page.slug)"]
        if body { object["body"] = page.body }
        return object
    }

    func announcementJSON(_ a: DemoAnnouncement) -> [String: Any] {
        ["id": a.id, "title": a.title, "message": a.message, "posted_at": stamp(a.posted), "context_code": "course_\(a.course)",
         "author": ["display_name": a.author], "user_name": a.author, "read_state": a.unread ? "unread" : "read", "unread_count": 0,
         "is_announcement": true, "html_url": "\(Self.host)/courses/\(a.course)/discussion_topics/\(a.id)", "discussion_subentry_count": 0]
    }

    func discussionJSON(_ t: DemoTopic) -> [String: Any] {
        ["id": t.id, "title": t.title, "message": t.message, "posted_at": stamp(t.posted), "last_reply_at": stamp(t.lastReply),
         "context_code": "course_\(t.course)", "author": ["display_name": t.author], "user_name": t.author,
         "discussion_subentry_count": t.replies, "unread_count": t.unread, "read_state": "read", "is_announcement": false,
         "html_url": "\(Self.host)/courses/\(t.course)/discussion_topics/\(t.id)", "discussion_type": "threaded"]
    }

    func discussionViewJSON(_ t: DemoTopic) -> [String: Any] {
        let replies: [(CanvasID, String)] = [
            (7205, "For 6.2 #9, do we need partial fractions before inverting?"),
            (7101, "Yes. Split Y(s) into partial fractions first, then use the table term by term."),
            (7212, "Is the table from class the one we can use on the exam?"),
            (7101, "Yes, the same table will be printed on the exam."),
        ]
        return [
            "participants": [["id": 7101, "display_name": "Dr. Lena Brennan"], ["id": 7205, "display_name": "Elijah Greene"], ["id": 7212, "display_name": "Mateo Reyes"]],
            "view": replies.enumerated().map { index, reply in
                ["id": t.id * 10 + index, "user_id": reply.0, "message": "<p>\(reply.1)</p>", "created_at": stamp(at(-2 + index / 2, 10 + index, 0))] as [String: Any]
            },
            "unread_entries": [t.id * 10 + 2, t.id * 10 + 3],
        ]
    }

    func conversationJSON(_ c: DemoConversation, withMessages: Bool) -> [String: Any] {
        let course = courses.first { $0.id == c.course }
        var participants: [[String: Any]] = [["id": Self.userId, "name": "Alex Morgan"]]
        participants += c.from.map { ["id": $0.0, "name": $0.1] }
        var object: [String: Any] = [
            "id": c.id, "subject": c.subject, "workflow_state": c.unread ? "unread" : "read", "last_message": c.messages.first?.2 ?? "",
            "last_message_at": stamp(c.at), "message_count": c.messages.count, "starred": c.starred, "subscribed": true,
            "context_name": course?.name ?? "", "context_code": "course_\(c.course)", "participants": participants,
            "audience": c.from.map(\.0), "properties": c.sent ? ["last_author"] : [String](),
        ]
        if withMessages {
            object["messages"] = c.messages.enumerated().map { index, message in
                ["id": c.id * 10 + index, "author_id": message.0, "created_at": stamp(message.1), "body": message.2, "generated": false] as [String: Any]
            }
        }
        return object
    }

    // MARK: PDF

    /// A one-page PDF with a title and a few lines (Helvetica), for Quick Look in the demo.
    public static func pdf(title: String, lines: [String]) -> Data {
        func escape(_ text: String) -> String {
            let ascii = text.map { character -> String in
                switch character {
                case "·": return "-"
                case "’", "‘": return "'"
                case "–", "—": return "-"
                case "é": return "e"
                default: return character.isASCII ? String(character) : "?"
                }
            }.joined()
            return ascii.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        }
        var content = "BT /F1 22 Tf 72 700 Td (\(escape(title))) Tj ET\n"
        for (index, line) in lines.enumerated() {
            content += "BT /F1 13 Tf 72 \(660 - index * 22) Td (\(escape(line))) Tj ET\n"
        }
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        var output = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(output.utf8.count)
            output += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = output.utf8.count
        output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { output += String(format: "%010d 00000 n \n", offset) }
        output += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(output.utf8)
    }
}

/// Serves `DemoCanvas` to a `URLSession`: every request is answered locally (nothing reaches the network), and
/// non-GET requests get 405 and are counted so tests and the smoke run can assert that nothing tried to write.
public final class DemoTransport: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _blockedWrites = 0
    nonisolated(unsafe) private static var _demo = DemoCanvas()

    /// How many write requests were refused since launch.
    public static var blockedWrites: Int { lock.lock(); defer { lock.unlock() }; return _blockedWrites }

    /// The account served; set `now` for deterministic tests.
    public static var demo: DemoCanvas {
        get { lock.lock(); defer { lock.unlock() }; return _demo }
        set { lock.lock(); _demo = newValue; lock.unlock() }
    }

    override public class func canInit(with request: URLRequest) -> Bool { true }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let method = request.httpMethod ?? "GET"
        if method.uppercased() != "GET" && method.uppercased() != "HEAD" {
            Self.lock.lock(); Self._blockedWrites += 1; Self.lock.unlock()
        }
        let response = Self.demo.response(method: method, url: url)
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": response.contentType, "Content-Length": String(response.body.count)])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}

    /// A session that only ever talks to the demo account.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoTransport.self]
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }

    /// A `CanvasClient` wired to the demo account.
    public static func makeClient() throws -> CanvasClient {
        try CanvasClient(credentials: DemoCanvas.credentials, session: makeSession())
    }
}
