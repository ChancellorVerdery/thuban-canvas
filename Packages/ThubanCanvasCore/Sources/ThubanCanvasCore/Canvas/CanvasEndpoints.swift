import Foundation

private func q(_ name: String, _ value: String) -> URLQueryItem { URLQueryItem(name: name, value: value) }
private func includes(_ names: [String]) -> [URLQueryItem] { names.map { q("include[]", $0) } }

// MARK: - Reads

public extension CanvasClient {
    func currentUser() async throws -> CanvasUser {
        try await get("users/self")
    }

    /// Starred courses with grades, term, teachers, tabs, image and syllabus in one call.
    func favoriteCourses() async throws -> [Course] {
        try await getAll("users/self/favorites/courses", query: includes([
            "total_scores", "term", "course_image", "syllabus_body", "tabs", "teachers", "favorites", "current_grading_period_scores",
        ]))
    }

    /// Every active course (for the "starred only" explanation and future term pickers).
    func activeCourses() async throws -> [Course] {
        try await getAll("courses", query: [q("enrollment_state", "active")] + includes(["total_scores", "term", "favorites"]))
    }

    func course(_ id: CanvasID) async throws -> Course {
        try await get("courses/\(id)", query: includes(["total_scores", "term", "course_image", "syllabus_body", "tabs", "teachers"]))
    }

    /// Assignment groups with their assignments, the student's submission and class score statistics.
    func assignmentGroups(course: CanvasID) async throws -> [AssignmentGroup] {
        try await getAll("courses/\(course)/assignment_groups", query: includes(["assignments", "submission", "score_statistics"]) + [q("override_assignment_dates", "true")])
    }

    func assignment(course: CanvasID, id: CanvasID) async throws -> Assignment {
        try await get("courses/\(course)/assignments/\(id)", query: includes(["submission", "score_statistics"]))
    }

    /// The student's own submission with comments and attachments.
    func submission(course: CanvasID, assignment: CanvasID) async throws -> Submission {
        try await get("courses/\(course)/assignments/\(assignment)/submissions/self", query: includes(["submission_comments"]))
    }

    /// Course-level grading standards (account-level ones are not readable by students).
    func gradingStandards(course: CanvasID) async throws -> [GradingStandard] {
        try await getAll("courses/\(course)/grading_standards")
    }

    func modules(course: CanvasID) async throws -> [Module] {
        try await getAll("courses/\(course)/modules", query: includes(["items", "content_details"]))
    }

    func moduleItems(course: CanvasID, module: CanvasID) async throws -> [ModuleItem] {
        try await getAll("courses/\(course)/modules/\(module)/items", query: includes(["content_details"]))
    }

    func page(course: CanvasID, url: String) async throws -> Page {
        try await get("courses/\(course)/pages/\(url)")
    }

    func pages(course: CanvasID) async throws -> [Page] {
        try await getAll("courses/\(course)/pages", query: [q("sort", "title")])
    }

    func frontPage(course: CanvasID) async throws -> Page {
        try await get("courses/\(course)/front_page")
    }

    func files(course: CanvasID) async throws -> [CanvasFile] {
        try await getAll("courses/\(course)/files", query: [q("sort", "updated_at"), q("order", "desc")])
    }

    func folders(course: CanvasID) async throws -> [Folder] {
        try await getAll("courses/\(course)/folders")
    }

    func file(_ id: CanvasID) async throws -> CanvasFile {
        try await get("files/\(id)")
    }

    func courseFile(course: CanvasID, id: CanvasID) async throws -> CanvasFile {
        try await get("courses/\(course)/files/\(id)")
    }

    func announcements(courses: [CanvasID], since: Date? = nil) async throws -> [DiscussionTopic] {
        guard !courses.isEmpty else { return [] }
        var query = courses.map { q("context_codes[]", "course_\($0)") }
        let start = since ?? Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        query.append(q("start_date", ISO8601DateFormatter().string(from: start)))
        query.append(q("end_date", ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400 * 30))))
        return try await getAll("announcements", query: query)
    }

    func discussions(course: CanvasID) async throws -> [DiscussionTopic] {
        try await getAll("courses/\(course)/discussion_topics", query: [q("order_by", "recent_activity")])
    }

    func discussion(course: CanvasID, id: CanvasID) async throws -> DiscussionTopic {
        try await get("courses/\(course)/discussion_topics/\(id)")
    }

    func discussionView(course: CanvasID, topic: CanvasID) async throws -> DiscussionView {
        try await get("courses/\(course)/discussion_topics/\(topic)/view")
    }

    func quizzes(course: CanvasID) async throws -> [Quiz] {
        try await getAll("courses/\(course)/quizzes")
    }

    func todo() async throws -> [TodoItem] {
        try await getAll("users/self/todo", query: includes(["ungraded_quizzes"]))
    }

    func missingSubmissions() async throws -> [Assignment] {
        try await getAll("users/self/missing_submissions", query: includes(["planner_overrides", "course"]) + [q("filter[]", "submittable")])
    }

    func plannerItems(from start: Date, to end: Date) async throws -> [PlannerItem] {
        let formatter = ISO8601DateFormatter()
        return try await getAll("planner/items", query: [q("start_date", formatter.string(from: start)), q("end_date", formatter.string(from: end))])
    }

    func calendarEvents(courses: [CanvasID], from start: Date, to end: Date, type: String) async throws -> [CalendarEvent] {
        guard !courses.isEmpty else { return [] }
        let formatter = ISO8601DateFormatter()
        var query = courses.map { q("context_codes[]", "course_\($0)") }
        query += [q("type", type), q("start_date", formatter.string(from: start)), q("end_date", formatter.string(from: end)), q("include[]", "assignment")]
        return try await getAll("calendar_events", query: query)
    }

    func conversations(scope: String? = nil) async throws -> [Conversation] {
        var query: [URLQueryItem] = []
        if let scope { query.append(q("scope", scope)) }
        return try await getAll("conversations", query: query)
    }

    /// Canvas marks a conversation read on GET by default (`auto_mark_as_read`); viewing must not be a silent write,
    /// so opt out here and let the confirmed `markConversation` path do it.
    func conversation(_ id: CanvasID) async throws -> Conversation {
        try await get("conversations/\(id)", query: [q("auto_mark_as_read", "false")])
    }

    func unreadConversationCount() async throws -> Int {
        struct Count: Decodable { var unreadCount: String }
        let count: Count = try await get("conversations/unread_count")
        return Int(count.unreadCount) ?? 0
    }

    func people(course: CanvasID) async throws -> [CourseUser] {
        try await getAll("courses/\(course)/users", query: includes(["enrollments", "avatar_url"]) + [q("sort", "sortable_name")])
    }

    func activityStream() async throws -> [StreamItem] {
        try await getAll("users/self/activity_stream", query: [q("only_active_courses", "true")])
    }
}

// MARK: - Writes
//
// Every write is confirmed in the UI first. None of these were exercised against a live account during development;
// they follow the documented Canvas API shapes.

public struct UploadedFile: Codable, Sendable {
    public var id: CanvasID
    public var displayName: String?
    public var size: Int?
}

public extension CanvasClient {
    /// Marks a to-do item ignored (`ignore` = until it changes, `ignore_permanently` = forever).
    func ignoreTodo(_ item: TodoItem, permanently: Bool) async throws {
        guard let raw = permanently ? item.ignorePermanently : item.ignore,
              let components = URLComponents(string: raw) else {
            throw ThubanError.unavailable("This item cannot be ignored")
        }
        // Canvas gives an absolute URL like https://host/api/v1/users/self/todo/<asset>/<purpose>?permanent=1;
        // strip the /api/v1/ prefix because makeURL re-adds it.
        var path = components.path
        if let range = path.range(of: "/api/v1/") { path = String(path[range.upperBound...]) }
        try await sendIgnoringResponse(.delete, path, query: components.queryItems ?? [], body: nil)
    }

    /// Text-entry submission.
    func submitText(course: CanvasID, assignment: CanvasID, body: String, comment: String? = nil) async throws -> Submission {
        var pairs = [("submission[submission_type]", "online_text_entry"), ("submission[body]", body)]
        if let comment, !comment.isEmpty { pairs.append(("comment[text_comment]", comment)) }
        return try await send(.post, "courses/\(course)/assignments/\(assignment)/submissions", body: .form(pairs))
    }

    /// URL submission.
    func submitURL(course: CanvasID, assignment: CanvasID, url: String, comment: String? = nil) async throws -> Submission {
        var pairs = [("submission[submission_type]", "online_url"), ("submission[url]", url)]
        if let comment, !comment.isEmpty { pairs.append(("comment[text_comment]", comment)) }
        return try await send(.post, "courses/\(course)/assignments/\(assignment)/submissions", body: .form(pairs))
    }

    /// File-upload submission: uploads each file with the 3-step flow, then submits the file ids.
    func submitFiles(course: CanvasID, assignment: CanvasID, files: [URL], comment: String? = nil) async throws -> Submission {
        var ids: [CanvasID] = []
        for file in files {
            let uploaded = try await uploadSubmissionFile(course: course, assignment: assignment, file: file)
            ids.append(uploaded.id)
        }
        var pairs = [("submission[submission_type]", "online_upload")] + ids.map { ("submission[file_ids][]", String($0)) }
        if let comment, !comment.isEmpty { pairs.append(("comment[text_comment]", comment)) }
        return try await send(.post, "courses/\(course)/assignments/\(assignment)/submissions", body: .form(pairs))
    }

    /// Canvas 3-step upload: request an upload slot, POST the bytes to the returned URL, then confirm.
    func uploadSubmissionFile(course: CanvasID, assignment: CanvasID, file: URL) async throws -> UploadedFile {
        struct Slot: Decodable {
            var uploadUrl: String
            var uploadParams: [String: JSONScalar]
        }
        let data = try Data(contentsOf: file)
        let slot: Slot = try await send(.post, "courses/\(course)/assignments/\(assignment)/submissions/self/files", body: .form([
            ("name", file.lastPathComponent), ("size", String(data.count)), ("content_type", Self.mimeType(for: file)), ("on_duplicate", "rename"),
        ]))
        guard let uploadURL = URL(string: slot.uploadUrl) else { throw ThubanError.network("Bad upload URL") }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let boundary = "thuban-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        for (key, value) in slot.uploadParams {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value.stringValue)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: \(Self.mimeType(for: file))\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ThubanError.network("No response from upload") }
        if (300..<400).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location"), let confirm = URL(string: location) {
            // Step 3: confirm (GET/POST the Location with the token).
            var confirmRequest = URLRequest(url: confirm)
            confirmRequest.httpMethod = "POST"
            confirmRequest.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            confirmRequest.setValue("0", forHTTPHeaderField: "Content-Length")
            let (confirmData, _) = try await URLSession.shared.data(for: confirmRequest)
            return try Self.decoder.decode(UploadedFile.self, from: confirmData)
        }
        guard (200..<300).contains(http.statusCode) else { throw ThubanError.http(status: http.statusCode, message: "Upload failed") }
        return try Self.decoder.decode(UploadedFile.self, from: responseData)
    }

    /// Adds a message to an existing conversation.
    func replyToConversation(_ id: CanvasID, body: String) async throws -> Conversation {
        try await send(.post, "conversations/\(id)/add_message", body: .form([("body", body)]))
    }

    /// Starts a conversation with users (ids) inside a course context.
    func createConversation(recipients: [CanvasID], subject: String, body: String, course: CanvasID?) async throws {
        var pairs = recipients.map { ("recipients[]", String($0)) } + [("subject", subject), ("body", body), ("group_conversation", "false")]
        if let course { pairs.append(("context_code", "course_\(course)")) }
        try await sendIgnoringResponse(.post, "conversations", body: .form(pairs))
    }

    func markConversation(_ id: CanvasID, read: Bool) async throws {
        try await sendIgnoringResponse(.put, "conversations/\(id)", body: .form([("conversation[workflow_state]", read ? "read" : "unread")]))
    }

    func starConversation(_ id: CanvasID, starred: Bool) async throws {
        try await sendIgnoringResponse(.put, "conversations/\(id)", body: .form([("conversation[starred]", starred ? "true" : "false")]))
    }

    /// Top-level reply on a discussion topic.
    func postDiscussionEntry(course: CanvasID, topic: CanvasID, message: String) async throws -> DiscussionEntry {
        try await send(.post, "courses/\(course)/discussion_topics/\(topic)/entries", body: .form([("message", message)]))
    }

    /// Reply to an entry.
    func replyToDiscussionEntry(course: CanvasID, topic: CanvasID, entry: CanvasID, message: String) async throws -> DiscussionEntry {
        try await send(.post, "courses/\(course)/discussion_topics/\(topic)/entries/\(entry)/replies", body: .form([("message", message)]))
    }

    func markDiscussionRead(course: CanvasID, topic: CanvasID) async throws {
        try await sendIgnoringResponse(.put, "courses/\(course)/discussion_topics/\(topic)/read_all", body: nil)
    }

    /// Planner "mark as done" override.
    func setPlannerComplete(type: String, id: CanvasID, complete: Bool, existing: PlannerItem.PlannerOverride?) async throws {
        if let existing {
            try await sendIgnoringResponse(.put, "planner/overrides/\(existing.id)", body: .form([("marked_complete", complete ? "true" : "false")]))
        } else {
            try await sendIgnoringResponse(.post, "planner/overrides", body: .form([("plannable_type", type), ("plannable_id", String(id)), ("marked_complete", complete ? "true" : "false")]))
        }
    }

    /// Star / unstar a course in Canvas (this changes which tabs the app shows).
    func setFavorite(course: CanvasID, starred: Bool) async throws {
        if starred {
            try await sendIgnoringResponse(.post, "users/self/favorites/courses/\(course)", body: nil)
        } else {
            try await sendIgnoringResponse(.delete, "users/self/favorites/courses/\(course)", body: nil)
        }
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "txt": return "text/plain"
        case "zip": return "application/zip"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        default: return "application/octet-stream"
        }
    }
}

/// A JSON string/number/bool leaf (upload params are strings, occasionally numbers).
public enum JSONScalar: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else { self = .string(try container.decode(String.self)) }
    }

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        }
    }
}
