import Foundation
import XCTest
@testable import ThubanCanvasCore

final class ModelDecodingTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try CanvasClient.decoder.decode(T.self, from: fixture(name))
    }

    func testFavoritesDecode() throws {
        let courses = try decode([Course].self, "favorites")
        XCTAssertEqual(courses.count, 6)
        let calc = try XCTUnwrap(courses.first { $0.id == 266407 })
        XCTAssertEqual(calc.name, "Calculus III")
        XCTAssertEqual(calc.term?.name, "Fall 2026")
        XCTAssertEqual(calc.studentEnrollment?.computedCurrentScore, 98.88)
        XCTAssertEqual(calc.studentEnrollment?.computedCurrentGrade, "A")
        XCTAssertEqual(calc.teachers?.first?.displayName, "Mark Ellison")
        XCTAssertTrue(calc.hasTab("grades"))
        XCTAssertFalse(calc.hasTab("modules"))
        XCTAssertNotNil(calc.imageDownloadUrl)
    }

    func testAssignmentGroupsDecodeAndGradeMatchesCanvas() throws {
        let groups = try decode([AssignmentGroup].self, "assignment_groups_266407")
        XCTAssertEqual(groups.count, 6)
        let grade = GradeCalculator.compute(groups: groups, weighted: true)
        // Canvas reported computed_current_score 98.88 for this course.
        XCTAssertEqual(try XCTUnwrap(grade.percent), 98.88, accuracy: 0.01)
        let submission = try XCTUnwrap(groups[0].assignments?.first?.submission)
        XCTAssertEqual(submission.score, 10)
        XCTAssertTrue(submission.isGraded)
        XCTAssertEqual(groups[0].assignments?.first?.scoreStatistics?.mean, 9.2)
    }

    func testWhatIfChangesGrade() throws {
        let groups = try decode([AssignmentGroup].self, "assignment_groups_266407")
        let final = try XCTUnwrap(groups.first { $0.name == "Final Exam" }?.assignments?.first)
        let base = GradeCalculator.compute(groups: groups, weighted: true).percent ?? 0
        let perfect = GradeCalculator.compute(groups: groups, weighted: true, whatIf: WhatIf(scores: [final.id: .score(final.pointsPossible ?? 0)])).percent ?? 0
        XCTAssertGreaterThan(perfect, base)
        let zeros = GradeCalculator.compute(groups: groups, weighted: true, whatIf: WhatIf(ungradedAsZero: true)).percent ?? 0
        XCTAssertLessThan(zeros, base)
    }

    func testModulesDecode() throws {
        let modules = try decode([Module].self, "modules")
        XCTAssertEqual(modules.count, 6)
        let items = try XCTUnwrap(modules.first?.items)
        XCTAssertTrue(items.contains { $0.type == "Page" && $0.pageUrl != nil })
        XCTAssertTrue(items.contains { $0.type == "File" && $0.contentDetails?.displayName?.hasSuffix(".docx") == true })
        XCTAssertTrue(items.contains { $0.type == "Assignment" && $0.contentDetails?.dueAt != nil })
    }

    func testPlannerDecodeToleratesFalseSubmissions() throws {
        let items = try decode([PlannerItem].self, "planner")
        XCTAssertEqual(items.count, 20)
        XCTAssertTrue(items.contains { $0.submissions?.submitted == true })
    }

    func testTodoMissingConversationsFilesDecode() throws {
        XCTAssertEqual(try decode([TodoItem].self, "todo").count, 5)
        let missing = try decode([Assignment].self, "missing")
        XCTAssertEqual(missing.count, 5)
        let conversations = try decode([Conversation].self, "conversations")
        XCTAssertEqual(conversations.first?.workflowState, "unread")
        XCTAssertTrue(conversations[0].isUnread)
        let files = try decode([CanvasFile].self, "files")
        XCTAssertEqual(files.first?.mimeClass, "ppt")
        let file = try decode(CanvasFile.self, "file_meta")
        XCTAssertEqual(file.contentType, "application/pdf")
        XCTAssertEqual(file.size, 459551)
        let page = try decode(Page.self, "page")
        XCTAssertEqual(page.url, "welcome-to-the-course")
        XCTAssertEqual(try decode([CourseTab].self, "tabs").count, 12)
        XCTAssertEqual(try decode([CourseUser].self, "teachers").count, 2)
        let standards = try decode([GradingStandard].self, "grading_standards")
        XCTAssertEqual(GradingScheme(standard: standards[0]).letter(for: 89.995), "A")
        XCTAssertEqual(try decode([StreamItem].self, "stream").count, 10)
        let events = try decode([CalendarEvent].self, "upcoming")
        XCTAssertEqual(events.count, 10)
        XCTAssertTrue(events.contains { $0.assignment != nil })
    }

    func testWorkItems() throws {
        let groups = try decode([AssignmentGroup].self, "assignment_groups_266407")
        let now = try XCTUnwrap(CanvasClient.parseDate("2026-09-17T18:00:00Z"))
        let items = WorkItemBuilder.items(for: 266407, courseName: "Calc III", groups: groups, now: now)
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.contains { $0.status == .graded })
        let upcoming = WorkItemBuilder.upcoming(items, now: now)
        XCTAssertTrue(upcoming.allSatisfy { ($0.dueAt ?? now) > now })
        XCTAssertEqual(upcoming, upcoming.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) })
    }

    /// Decodes an inline Canvas-shaped JSON snippet with the package decoder.
    func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try CanvasClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testMissingGradedAssignmentIsOverdueNotSubmitted() throws {
        // Real shape: a late policy graded a missing assignment while the grade is unposted.
        let missing = try decodeJSON(Assignment.self, """
        {"id": 1, "name": "HW 3", "due_at": "2026-09-10T03:59:00Z", "points_possible": 10, "submission_types": ["online_upload"],
         "submission": {"workflow_state": "graded", "score": null, "submitted_at": null, "attempt": null, "missing": true}}
        """)
        let now = try XCTUnwrap(CanvasClient.parseDate("2026-09-17T18:00:00Z"))
        XCTAssertFalse(try XCTUnwrap(missing.submission).isSubmitted)
        XCTAssertEqual(WorkItem.status(for: missing, now: now), .overdue)

        let handedIn = try decodeJSON(Submission.self, """
        {"workflow_state": "graded", "score": null, "submitted_at": "2026-09-09T20:00:00Z", "attempt": 1}
        """)
        XCTAssertTrue(handedIn.isSubmitted)
    }

    func testWeightedGradeIsNotRescaledWhenWeightsExceed100() throws {
        func groups(_ weights: [Double]) throws -> [AssignmentGroup] {
            try weights.enumerated().map { index, weight in
                try decodeJSON(AssignmentGroup.self, """
                {"id": \(index + 1), "name": "G\(index + 1)", "position": \(index + 1), "group_weight": \(weight),
                 "assignments": [{"id": \(100 + index), "name": "A", "points_possible": 10,
                                  "submission": {"workflow_state": "graded", "score": 10}}]}
                """)
            }
        }
        // Canvas leaves Σ weight × percent alone when the active weights total 100 or more (extra-credit groups).
        XCTAssertEqual(try XCTUnwrap(GradeCalculator.compute(groups: try groups([60, 45]), weighted: true).percent), 105, accuracy: 1e-9)
        // … and only rescales when they total less than 100.
        XCTAssertEqual(try XCTUnwrap(GradeCalculator.compute(groups: try groups([60, 20]), weighted: true).percent), 100, accuracy: 1e-9)
    }

    func testZeroPointExtraCreditCountsTowardGrade() throws {
        let group = try decodeJSON(AssignmentGroup.self, """
        {"id": 1, "name": "Quizzes", "assignments": [
            {"id": 1, "name": "Quiz 1", "points_possible": 10, "submission": {"workflow_state": "graded", "score": 10}},
            {"id": 2, "name": "Extra credit quiz", "points_possible": 0, "submission": {"workflow_state": "graded", "score": 5}}
        ]}
        """)
        XCTAssertTrue(try XCTUnwrap(group.assignments?[1]).countsTowardGrade)
        XCTAssertEqual(try XCTUnwrap(GradeCalculator.compute(groups: [group], weighted: false).percent), 150, accuracy: 1e-9)
        let whatIf = GradeCalculator.compute(groups: [group], weighted: false, whatIf: WhatIf(scores: [2: .score(3)]))
        XCTAssertEqual(try XCTUnwrap(whatIf.percent), 130, accuracy: 1e-9)
    }

    func testLinkHeader() throws {
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://x.instructure.com/api/v1/courses")!, statusCode: 200, httpVersion: nil, headerFields: [
            "Link": "<https://x.instructure.com/api/v1/courses?page=2&per_page=10>; rel=\"next\",<https://x.instructure.com/api/v1/courses?page=1&per_page=10>; rel=\"first\"",
        ]))
        XCTAssertEqual(CanvasClient.nextLink(from: response)?.absoluteString, "https://x.instructure.com/api/v1/courses?page=2&per_page=10")
    }

    func testHostNormalization() throws {
        XCTAssertEqual(try CanvasCredentials.normalizeHost("instructure.charlotte.edu"), "https://instructure.charlotte.edu")
        XCTAssertEqual(try CanvasCredentials.normalizeHost(" https://School.Instructure.com/ "), "https://school.instructure.com")
        XCTAssertThrowsError(try CanvasCredentials.normalizeHost("http://school.instructure.com"))
        XCTAssertThrowsError(try CanvasCredentials.normalizeHost("school.instructure.com/courses/1"))
        XCTAssertThrowsError(try CanvasCredentials.normalizeHost("localhost"))
    }

    func testHTMLHelpers() {
        let host = "https://instructure.charlotte.edu"
        let html = "<script>alert(1)</script><p onclick=\"x()\">Hi <img src=\"/courses/1/files/2/preview\"> <a href=\"/courses/1/assignments/3\">A</a></p>"
        let cleaned = CanvasHTML.sanitize(html, host: host)
        XCTAssertFalse(cleaned.contains("<script"))
        XCTAssertFalse(cleaned.contains("onclick"))
        XCTAssertTrue(cleaned.contains("thubancanvas://instructure.charlotte.edu/courses/1/files/2/preview"))
        XCTAssertTrue(cleaned.contains("href=\"https://instructure.charlotte.edu/courses/1/assignments/3\""))
        XCTAssertEqual(CanvasHTML.plainText("<p>Hello&nbsp;<b>world</b></p>\n\n<p>x</p>", limit: 8), "Hello wo…")
        XCTAssertEqual(CanvasHTML.classify(URL(string: "https://instructure.charlotte.edu/courses/1/assignments/3")!, host: host), .assignment(course: 1, id: 3))
        XCTAssertEqual(CanvasHTML.classify(URL(string: "https://instructure.charlotte.edu/courses/1/modules/items/9")!, host: host), .moduleItem(course: 1, id: 9))
        XCTAssertNil(CanvasHTML.classify(URL(string: "https://example.com/courses/1/assignments/3")!, host: host))
    }

    func testGradingSchemeAndGPA() {
        XCTAssertEqual(GradingScheme.plusMinus.letter(for: 92.99), "A-")
        XCTAssertEqual(GradingScheme.plusMinus.letter(for: 92.996), "A")
        XCTAssertEqual(GradingScheme.plain.letter(for: 59.9), "F")
        let custom = GradingScheme(parsing: "A 85, B 72, C 60")
        XCTAssertEqual(custom?.letter(for: 80), "B")
        XCTAssertEqual(custom?.summary, "A 85, B 72, C 60")
        let result = GPACalculator.compute(courses: [
            GPACourse(id: 1, name: "A", letter: "A", credits: 3),
            GPACourse(id: 2, name: "B", letter: "B+", credits: 4),
            GPACourse(id: 3, name: "C", letter: nil, credits: 3),
        ], past: [PastSemester(name: "Spring", gpa: 3.5, credits: 15)])
        XCTAssertEqual(try XCTUnwrap(result.term), (4.0 * 3 + 3.3 * 4) / 7, accuracy: 1e-9)
        XCTAssertEqual(result.skipped, ["C"])
        XCTAssertEqual(result.cumulativeCredits, 22)
    }

    func testSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.coursePreferences[266407] = CoursePreferences(nickname: "Calc III", credits: 4)
        settings.dismissedOverdue.insert("1:2")
        settings.whatIf[266407] = WhatIf(scores: [5: .score(9.5), 6: .ungraded], ungradedAsZero: true)
        let data = try JSONFile.encoder.encode(settings)
        let decoded = try JSONFile.decoder.decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
        let sparse = try JSONFile.decoder.decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(sparse.defaultCredits, 3)
    }

    func testPastSemesterClassesAndLegacyDecoding() throws {
        let semester = PastSemester(name: "Spring 2026", classes: [
            PastClass(name: "Physics", credits: 4, letter: "A-"),
            PastClass(name: "Writing", credits: 3, letter: "B+"),
            PastClass(name: "Lab", credits: 1, letter: ""),
        ], scale: .plusMinus)
        XCTAssertEqual(semester.credits, 7)
        XCTAssertEqual(try XCTUnwrap(semester.gpa), (3.7 * 4 + 3.3 * 3) / 7, accuracy: 1e-9)
        XCTAssertEqual(semester.unlettered, 1)
        let legacy = try JSONFile.decoder.decode(PastSemester.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Fall 2025","gpa":3.5,"credits":15}"#.utf8))
        XCTAssertFalse(legacy.usesClasses)
        XCTAssertEqual(legacy.gpa, 3.5)
        XCTAssertEqual(legacy.credits, 15)
        let roundTrip = try JSONFile.decoder.decode(PastSemester.self, from: JSONFile.encoder.encode(semester))
        XCTAssertEqual(roundTrip, semester)
        let result = GPACalculator.compute(courses: [], past: [semester, legacy])
        XCTAssertEqual(result.cumulativeCredits, 22)
    }
}
