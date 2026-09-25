import Foundation
import XCTest
@testable import ThubanCanvasCore

/// Core pieces added for the iOS app: the offline demo account + fake transport, the read-only guard, compact
/// formatting and small parsers. Nothing here touches the network.
final class IOSSupportTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Friday, September 25, 2026, 2:32 PM Eastern.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 14, minute: 32))!
    }

    override func setUp() {
        super.setUp()
        DemoTransport.demo = DemoCanvas(now: now, calendar: calendar)
    }

    // MARK: Demo account

    func testDemoAccountServesEveryReadTheAppMakes() async throws {
        let client = try DemoTransport.makeClient()
        let me = try await client.currentUser()
        XCTAssertEqual(me.name, "Alex Morgan")

        let courses = try await client.favoriteCourses()
        XCTAssertEqual(courses.map(\.id), [101, 102, 103, 104, 105])
        let math = try XCTUnwrap(courses.first)
        XCTAssertEqual(math.term?.name, "Fall 2026")
        XCTAssertEqual(math.studentEnrollment?.computedCurrentScore, 90.54)
        XCTAssertTrue(math.hasTab("modules"))
        XCTAssertFalse(math.hasTab("files"))

        let groups = try await client.assignmentGroups(course: 101)
        XCTAssertEqual(groups.map(\.name), ["Homework", "Quizzes", "Exams", "Participation"])
        let grade = GradeCalculator.compute(groups: groups, weighted: true)
        XCTAssertEqual(try XCTUnwrap(grade.percent), 90.54, accuracy: 0.01, "demo scores agree with the Canvas number")

        let modules = try await client.modules(course: 101)
        XCTAssertEqual(modules.count, 15)
        XCTAssertEqual(modules[4].state, "started")
        XCTAssertEqual(modules[4].items?.count, 5)
        XCTAssertEqual(modules[4].items?[3].completionRequirement?.minScore, 8)

        let inbox = try await client.conversations()
        XCTAssertEqual(inbox.count, 5)
        let sent = try await client.conversations(scope: "sent")
        XCTAssertEqual(sent.map(\.id), [506])
        let unread = try await client.unreadConversationCount()
        XCTAssertEqual(unread, 2)
        let thread = try await client.conversation(501)
        XCTAssertEqual(thread.messages?.count, 2)

        let start = calendar.startOfDay(for: now)
        let events = try await client.calendarEvents(courses: [103, 104], from: start, to: start.addingTimeInterval(86_400), type: "event")
        XCTAssertEqual(events.map(\.title), ["Exam 1 review session", "Lab 4 office hours"])

        let missing = try await client.missingSubmissions()
        XCTAssertEqual(missing.map(\.name), ["Pre-lab 5 · RC circuits"])

        let file = try await client.courseFile(course: 101, id: 9001)
        XCTAssertEqual(file.size, 96_000)
        let (bytes, _) = try await client.data(for: try XCTUnwrap(URL(string: try XCTUnwrap(file.url))))
        XCTAssertTrue(String(decoding: bytes.prefix(8), as: UTF8.self).hasPrefix("%PDF-1.4"))

        let people = try await client.people(course: 101)
        XCTAssertEqual(people.count, 41)
        let announcements = try await client.announcements(courses: [101])
        XCTAssertEqual(announcements.count, 2)
    }

    func testDemoWorkItemsMatchTheDesignedHome() async throws {
        let client = try DemoTransport.makeClient()
        var items: [WorkItem] = []
        for course in try await client.favoriteCourses() {
            let groups = try await client.assignmentGroups(course: course.id)
            items += WorkItemBuilder.items(for: course.id, courseName: course.name, groups: groups, now: now)
        }
        let overdue = WorkItemBuilder.overdue(items, dismissed: [])
        XCTAssertEqual(overdue.map(\.title), ["Pre-lab 5 · RC circuits"])
        let week = WorkItemBuilder.upcoming(items, now: now, within: 7)
        XCTAssertEqual(week.first?.title, "Problem Set 5")
        XCTAssertEqual(DueFormatter.compact(try XCTUnwrap(week.first?.dueAt), now: now, calendar: calendar), "Tomorrow · 11:59 PM")
        XCTAssertTrue(week.contains { $0.title == "Lab 4 report · Thévenin" })
    }

    func testDemoRefusesWritesAndCountsThem() async throws {
        let client = try DemoTransport.makeClient()
        let before = DemoTransport.blockedWrites
        do {
            _ = try await client.submitText(course: 101, assignment: 10115, body: "should never be sent")
            XCTFail("a write succeeded against the demo account")
        } catch {}
        XCTAssertEqual(DemoTransport.blockedWrites, before + 1)
    }

    func testWhatIfOnDemoCourse() async throws {
        let client = try DemoTransport.makeClient()
        let groups = try await client.assignmentGroups(course: 101)
        let whatIf = WhatIf(scores: [10132: .score(90), 10115: .score(18)])
        let grade = GradeCalculator.compute(groups: groups, weighted: true, whatIf: whatIf)
        // Homework (75.5 + 18) / 100, quizzes 26.5 / 30 after the drop, exams (86 + 90) / 200, participation 100 %.
        let expected = 0.25 * 93.5 + 0.15 * (26.5 / 30 * 100) + 0.45 * 88 + 0.15 * 100
        XCTAssertEqual(try XCTUnwrap(grade.percent), expected, accuracy: 0.001)
        XCTAssertEqual(grade.groups.first { $0.name == "Quizzes" }?.dropped, [10122])
    }

    // MARK: Read-only guard

    func testReadOnlyGuardLetsOnlyReadsThrough() async {
        var get = URLRequest(url: URL(string: "https://instructure.charlotte.edu/api/v1/users/self")!)
        get.httpMethod = "GET"
        XCTAssertFalse(ReadOnlyGuard.canInit(with: get))
        var head = get
        head.httpMethod = "HEAD"
        XCTAssertFalse(ReadOnlyGuard.canInit(with: head))
        for method in ["POST", "PUT", "DELETE", "PATCH"] {
            var write = get
            write.httpMethod = method
            XCTAssertTrue(ReadOnlyGuard.canInit(with: write), method)
        }

        // A write through a guarded session fails locally (the .invalid host would not resolve anyway).
        var post = URLRequest(url: URL(string: "https://canvas.example.invalid/api/v1/conversations")!)
        post.httpMethod = "POST"
        do {
            _ = try await ReadOnlyGuard.makeSession().data(for: post)
            XCTFail("POST went through the guard")
        } catch let error as NSError {
            XCTAssertEqual(error.code, ReadOnlyGuard.blockedCode)
        }
    }

    // MARK: Formatting

    func testCompactDates() {
        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
        }
        XCTAssertEqual(DueFormatter.compact(date(25, 16, 0), now: now, calendar: calendar), "Today · 4:00 PM")
        XCTAssertEqual(DueFormatter.compact(date(26, 23, 59), now: now, calendar: calendar), "Tomorrow · 11:59 PM")
        XCTAssertEqual(DueFormatter.compact(date(27, 23, 59), now: now, calendar: calendar), "Sun · 11:59 PM")
        XCTAssertEqual(DueFormatter.compact(date(28, 8, 0), now: now, calendar: calendar), "Mon · 8:00 AM")
        XCTAssertEqual(DueFormatter.compact(date(24, 9, 0), now: now, calendar: calendar), "Yesterday · 9:00 AM")
        XCTAssertEqual(DueFormatter.compact(date(18, 9, 0), now: now, calendar: calendar), "Sep 18")
        let october1 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 23, minute: 59))!
        XCTAssertEqual(DueFormatter.compact(october1, now: now, calendar: calendar), "Thu · 11:59 PM")
        let october5 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
        XCTAssertEqual(DueFormatter.compactDay(october5, now: now, calendar: calendar), "Mon Oct 5")
        XCTAssertEqual(DueFormatter.full(date(26, 23, 59), calendar: calendar), "Sat Sep 26 · 11:59 PM")
    }

    func testCountdownsAndLateness() {
        let due = now.addingTimeInterval(86_400 + 9 * 3_600 + 27 * 60)
        XCTAssertEqual(DueFormatter.preciseCountdown(due, now: now), "in 1d 9h 27m")
        XCTAssertEqual(DueFormatter.preciseCountdown(now.addingTimeInterval(3 * 3_600 + 5 * 60), now: now), "in 3h 5m")
        XCTAssertEqual(DueFormatter.preciseCountdown(now.addingTimeInterval(12 * 60 + 5), now: now), "in 12m")
        XCTAssertEqual(DueFormatter.preciseCountdown(now.addingTimeInterval(-(2 * 86_400 + 3 * 3_600)), now: now), "2d 3h 0m ago")
        XCTAssertEqual(DueFormatter.friendlyCountdown(due, now: now), "in 1 day 9 hr")
        XCTAssertEqual(DueFormatter.friendlyCountdown(now.addingTimeInterval(12 * 86_400), now: now), "in 12 days")
        XCTAssertEqual(DueFormatter.lateness(now.addingTimeInterval(-2.4 * 86_400), now: now), "2 days late")
        XCTAssertEqual(DueFormatter.lateness(now.addingTimeInterval(-5 * 3_600), now: now), "5 hr late")
        XCTAssertEqual(DueFormatter.dueEyebrow(due, now: now, calendar: calendar), "Due tomorrow")
        XCTAssertEqual(DueFormatter.dueEyebrow(now.addingTimeInterval(2 * 86_400), now: now, calendar: calendar), "Due Sunday")
        XCTAssertEqual(DueFormatter.dueEyebrow(now.addingTimeInterval(-2 * 86_400), now: now, calendar: calendar), "Was due 2 days ago")
        XCTAssertEqual(DueFormatter.refreshed(now.addingTimeInterval(-4 * 60), now: now), "Refreshed 4 min ago")
        XCTAssertEqual(DueFormatter.refreshed(now.addingTimeInterval(-20), now: now), "Refreshed just now")
        XCTAssertEqual(DueFormatter.leadTimes([1, 24]), "1 day, 1 hour")
        XCTAssertEqual(DueFormatter.leadTimes([48, 2]), "2 days, 2 hours")
        XCTAssertEqual(DueFormatter.leadTimes([]), "Off")
        XCTAssertEqual(DueFormatter.bytes(96_000), "96 KB")
        XCTAssertEqual(DueFormatter.bytes(38_200_000), "38.2 MB")
    }

    // MARK: Parsers

    func testModuleNameSplit() {
        XCTAssertEqual(ModuleName.split("Week 5: Laplace transforms").eyebrow, "Week 5")
        XCTAssertEqual(ModuleName.split("Week 5: Laplace transforms").title, "Laplace transforms")
        XCTAssertEqual(ModuleName.split("Module 3 - Vectors").eyebrow, "Module 3")
        XCTAssertNil(ModuleName.split("Course resources").eyebrow)
        XCTAssertNil(ModuleName.split("Start here: read this first").eyebrow, "no number in the head")
        XCTAssertEqual(ModuleName.split("Course resources").title, "Course resources")
    }

    func testCourseSection() {
        XCTAssertEqual(CourseCodeParser.section(from: "202680-MATH-2171-005-10500"), "005")
        XCTAssertEqual(CourseCodeParser.section(from: "202680-MATH-2241-003-10505"), "003")
        XCTAssertEqual(CourseCodeParser.section(from: "202680-MEGR-3111-004-14239"), "004")
        XCTAssertNil(CourseCodeParser.section(from: "202680-ENGR-1301-005:ENGR-1301-006:ENGR-1301-007"))
        XCTAssertNil(CourseCodeParser.section(from: "Training - MEES Pre-Registration Academic Advising"))
        XCTAssertNil(CourseCodeParser.section(from: nil))
    }

    func testFileLinksInDescriptions() {
        let host = "https://instructure.charlotte.edu"
        let html = """
        <p>See <a class="instructure_file_link" title="HW 3.pdf" href="https://instructure.charlotte.edu/courses/272933/files/34325465?verifier=x&amp;wrap=1">HW 3.pdf</a>
        and <a href="/courses/272933/files/34325466/download">Link</a>, again <a href="https://instructure.charlotte.edu/courses/272933/files/34325465">HW 3.pdf</a>,
        plus <a href="https://example.com/files/1">elsewhere</a> and <a href="https://instructure.charlotte.edu/courses/272933/pages/intro">a page</a>.</p>
        """
        let links = CanvasHTML.fileLinks(html, host: host)
        XCTAssertEqual(links, [
            CanvasHTML.FileLink(id: 34325465, course: 272933, name: "HW 3.pdf"),
            CanvasHTML.FileLink(id: 34325466, course: 272933, name: "File 34325466"),
        ])
        XCTAssertEqual(CanvasHTML.fileLinks(nil, host: host), [])
    }

    // MARK: Storage

    func testProtectedCredentialWriteRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thuban-ios-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        AppPaths.overrideHome = directory
        defer { AppPaths.overrideHome = nil }
        XCTAssertEqual(AppPaths.credentialsFile.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        try CredentialStore.save(CanvasCredentials(host: "https://instructure.charlotte.edu", token: "0123456789abcdefghij"))
        XCTAssertEqual(try CredentialStore.load()?.token, "0123456789abcdefghij")
        let mode = try FileManager.default.attributesOfItem(atPath: AppPaths.credentialsFile.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        try CredentialStore.clear()
        XCTAssertNil(try CredentialStore.load())
    }
}
