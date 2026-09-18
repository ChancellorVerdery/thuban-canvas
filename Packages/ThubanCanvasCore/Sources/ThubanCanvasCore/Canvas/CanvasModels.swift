import Foundation

// Canvas REST payloads (https://canvas.instructure.com/doc/api/). Decoded with `.convertFromSnakeCase`, so
// property names are the camel-cased JSON keys. Everything optional that Canvas ever omits or nulls.

public typealias CanvasID = Int

public struct CanvasUser: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var shortName: String?
    public var sortableName: String?
    public var avatarUrl: String?
    public var pronouns: String?
    public var primaryEmail: String?
    public var loginId: String?
}

public struct Term: Codable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var startAt: Date?
    public var endAt: Date?
}

public struct CourseEnrollment: Codable, Equatable, Sendable {
    public var type: String
    public var role: String?
    public var enrollmentState: String?
    public var computedCurrentScore: Double?
    public var computedCurrentGrade: String?
    public var computedCurrentLetterGrade: String?
    public var computedFinalScore: Double?
    public var computedFinalGrade: String?
    public var currentPeriodComputedCurrentScore: Double?
    public var currentPeriodComputedCurrentGrade: String?
    public var hasGradingPeriods: Bool?
}

public struct CourseTab: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var type: String?
    public var hidden: Bool?
    public var position: Int?
    public var visibility: String?
    public var htmlUrl: String?
}

public struct Teacher: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var displayName: String
    public var avatarImageUrl: String?
    public var pronouns: String?
}

public struct Course: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var courseCode: String?
    public var originalName: String?
    public var friendlyName: String?
    public var workflowState: String?
    public var startAt: Date?
    public var endAt: Date?
    public var enrollmentTermId: CanvasID?
    public var term: Term?
    public var enrollments: [CourseEnrollment]?
    public var teachers: [Teacher]?
    public var tabs: [CourseTab]?
    public var syllabusBody: String?
    public var imageDownloadUrl: String?
    public var courseColor: String?
    public var defaultView: String?
    public var gradingStandardId: CanvasID?
    public var applyAssignmentGroupWeights: Bool?
    public var hideFinalGrades: Bool?
    public var timeZone: String?
    public var isFavorite: Bool?
    public var restrictQuantitativeData: Bool?

    /// The student enrollment, if any.
    public var studentEnrollment: CourseEnrollment? {
        enrollments?.first { $0.type == "student" || $0.role == "StudentEnrollment" } ?? enrollments?.first
    }

    /// Whether Canvas exposes a course tab (Modules, Files, Pages …). Tabs the instructor disabled are absent.
    public func hasTab(_ id: String) -> Bool {
        guard let tabs else { return true }
        return tabs.contains { $0.id == id && $0.hidden != true }
    }
}

public struct ScoreStatistics: Codable, Equatable, Sendable {
    public var min: Double?
    public var max: Double?
    public var mean: Double?
    public var median: Double?
    public var upperQ: Double?
    public var lowerQ: Double?
}

public struct Submission: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID?
    public var assignmentId: CanvasID?
    public var userId: CanvasID?
    public var score: Double?
    public var grade: String?
    public var enteredScore: Double?
    public var excused: Bool?
    public var attempt: Int?
    public var submissionType: String?
    public var submittedAt: Date?
    public var gradedAt: Date?
    public var postedAt: Date?
    public var workflowState: String?
    public var late: Bool?
    public var missing: Bool?
    public var latePolicyStatus: String?
    public var pointsDeducted: Double?
    public var secondsLate: Int?
    public var body: String?
    public var url: String?
    public var previewUrl: String?
    public var cachedDueDate: Date?
    public var gradeMatchesCurrentSubmission: Bool?
    public var submissionComments: [SubmissionComment]?
    public var attachments: [CanvasFile]?

    /// Graded and the score is visible to the student.
    public var isGraded: Bool { workflowState == "graded" && score != nil && excused != true }
    public var isSubmitted: Bool { submittedAt != nil || (workflowState != nil && workflowState != "unsubmitted") }
}

public struct SubmissionComment: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var authorName: String?
    public var comment: String
    public var createdAt: Date?
}

public struct Assignment: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var courseId: CanvasID?
    public var name: String
    public var description: String?
    public var dueAt: Date?
    public var unlockAt: Date?
    public var lockAt: Date?
    public var pointsPossible: Double?
    public var gradingType: String?
    public var assignmentGroupId: CanvasID?
    public var position: Int?
    public var submissionTypes: [String]?
    public var allowedExtensions: [String]?
    public var allowedAttempts: Int?
    public var htmlUrl: String?
    public var published: Bool?
    public var lockedForUser: Bool?
    public var lockExplanation: String?
    public var omitFromFinalGrade: Bool?
    public var hideInGradebook: Bool?
    public var hasSubmittedSubmissions: Bool?
    public var isQuizAssignment: Bool?
    public var quizId: CanvasID?
    public var discussionTopic: DiscussionTopic?
    public var submission: Submission?
    public var scoreStatistics: ScoreStatistics?
    public var externalToolTagAttributes: ExternalToolTag?
    public var muted: Bool?
    public var updatedAt: Date?

    public struct ExternalToolTag: Codable, Equatable, Sendable {
        public var url: String?
        public var newTab: Bool?
    }

    /// True when the student can hand something in through Canvas itself.
    public var acceptsOnlineSubmission: Bool {
        guard let types = submissionTypes else { return false }
        return types.contains { ["online_upload", "online_text_entry", "online_url"].contains($0) }
    }
    public var isOnPaperOrNone: Bool {
        guard let types = submissionTypes else { return false }
        return types.allSatisfy { $0 == "none" || $0 == "on_paper" || $0 == "not_graded" }
    }
    public var countsTowardGrade: Bool { omitFromFinalGrade != true && gradingType != "not_graded" && (pointsPossible ?? 0) > 0 }
}

public struct AssignmentGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var position: Int?
    public var groupWeight: Double?
    public var rules: Rules?
    public var assignments: [Assignment]?

    public struct Rules: Codable, Equatable, Sendable {
        public var dropLowest: Int?
        public var dropHighest: Int?
        public var neverDrop: [CanvasID]?
    }
}

public struct GradingStandard: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var title: String
    public var gradingScheme: [Cutoff]

    public struct Cutoff: Codable, Equatable, Sendable {
        public var name: String
        /// Lower bound as a fraction (0.9 = 90 %).
        public var value: Double
    }
}

public struct Module: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var position: Int?
    public var unlockAt: Date?
    public var requireSequentialProgress: Bool?
    public var state: String?
    public var completedAt: Date?
    public var itemsCount: Int?
    public var items: [ModuleItem]?
}

public struct ModuleItem: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var moduleId: CanvasID?
    public var position: Int?
    public var title: String
    public var indent: Int?
    /// File, Page, Discussion, Assignment, Quiz, SubHeader, ExternalUrl, ExternalTool
    public var type: String
    public var contentId: CanvasID?
    public var htmlUrl: String?
    public var url: String?
    public var pageUrl: String?
    public var externalUrl: String?
    public var newTab: Bool?
    public var published: Bool?
    public var completionRequirement: CompletionRequirement?
    public var contentDetails: ContentDetails?

    public struct CompletionRequirement: Codable, Equatable, Sendable {
        public var type: String
        public var minScore: Double?
        public var completed: Bool?
    }

    public struct ContentDetails: Codable, Equatable, Sendable {
        public var pointsPossible: Double?
        public var dueAt: Date?
        public var unlockAt: Date?
        public var lockAt: Date?
        public var lockedForUser: Bool?
        public var lockExplanation: String?
        public var displayName: String?
        public var thumbnailUrl: String?
    }
}

public struct CanvasFile: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var folderId: CanvasID?
    public var displayName: String
    public var filename: String?
    public var contentType: String?
    public var size: Int?
    public var url: String?
    public var mimeClass: String?
    public var thumbnailUrl: String?
    public var previewUrl: String?
    public var lockedForUser: Bool?
    public var lockExplanation: String?
    public var hidden: Bool?
    public var locked: Bool?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var modifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, folderId, displayName, filename, size, url, mimeClass, thumbnailUrl, previewUrl, lockedForUser,
             lockExplanation, hidden, locked, createdAt, updatedAt, modifiedAt
        case contentType = "content-type"
    }
}

public struct Folder: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var fullName: String?
    public var parentFolderId: CanvasID?
    public var filesCount: Int?
    public var foldersCount: Int?
    public var hidden: Bool?
    public var locked: Bool?
    public var lockedForUser: Bool?
    public var position: Int?
}

public struct Page: Codable, Identifiable, Equatable, Sendable {
    public var pageId: CanvasID
    public var url: String
    public var title: String
    public var body: String?
    public var frontPage: Bool?
    public var published: Bool?
    public var lockedForUser: Bool?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var htmlUrl: String?
    public var id: CanvasID { pageId }
}

public struct DiscussionTopic: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var title: String
    public var message: String?
    public var htmlUrl: String?
    public var postedAt: Date?
    public var delayedPostUntil: Date?
    public var lastReplyAt: Date?
    public var contextCode: String?
    public var userName: String?
    public var author: Author?
    public var discussionSubentryCount: Int?
    public var readState: String?
    public var unreadCount: Int?
    public var isAnnouncement: Bool?
    public var locked: Bool?
    public var lockedForUser: Bool?
    public var published: Bool?
    public var pinned: Bool?
    public var assignmentId: CanvasID?
    public var attachments: [CanvasFile]?
    public var discussionType: String?
    public var canReply: Bool?
    public var subscribed: Bool?

    public struct Author: Codable, Equatable, Sendable {
        public var id: CanvasID?
        public var displayName: String?
        public var avatarImageUrl: String?
        public var pronouns: String?
    }

    /// `course_266407` → 266407
    public var courseId: CanvasID? {
        guard let code = contextCode, code.hasPrefix("course_") else { return nil }
        return CanvasID(code.dropFirst("course_".count))
    }
}

/// `GET /discussion_topics/:id/view` — the full thread.
public struct DiscussionView: Codable, Equatable, Sendable {
    public var participants: [Participant]?
    public var view: [DiscussionEntry]?
    public var unreadEntries: [CanvasID]?

    public struct Participant: Codable, Identifiable, Equatable, Sendable {
        public var id: CanvasID
        public var displayName: String?
        public var avatarImageUrl: String?
        public var pronouns: String?
    }
}

public struct DiscussionEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var userId: CanvasID?
    public var parentId: CanvasID?
    public var message: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var deleted: Bool?
    public var replies: [DiscussionEntry]?
    public var attachments: [CanvasFile]?
}

public struct Quiz: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var title: String
    public var description: String?
    public var htmlUrl: String?
    public var quizType: String?
    public var dueAt: Date?
    public var lockAt: Date?
    public var unlockAt: Date?
    public var pointsPossible: Double?
    public var questionCount: Int?
    public var timeLimit: Int?
    public var allowedAttempts: Int?
    public var published: Bool?
    public var lockedForUser: Bool?
    public var assignmentId: CanvasID?
}

/// `GET /users/self/todo`
public struct TodoItem: Codable, Equatable, Sendable {
    public var type: String
    public var contextType: String?
    public var contextName: String?
    public var courseId: CanvasID?
    public var htmlUrl: String?
    public var ignore: String?
    public var ignorePermanently: String?
    public var assignment: Assignment?
    public var quiz: Quiz?
}

/// `GET /planner/items`
public struct PlannerItem: Codable, Equatable, Sendable {
    public var contextType: String?
    public var contextName: String?
    public var courseId: CanvasID?
    public var plannableId: CanvasID
    public var plannableType: String
    public var plannableDate: Date?
    public var plannable: Plannable
    public var htmlUrl: String?
    public var submissions: PlannerSubmissions?
    public var plannerOverride: PlannerOverride?
    public var newActivity: Bool?

    public struct Plannable: Codable, Equatable, Sendable {
        public var id: CanvasID?
        public var title: String?
        public var dueAt: Date?
        public var todoDate: Date?
        public var pointsPossible: Double?
        public var startAt: Date?
        public var endAt: Date?
        public var allDay: Bool?
        public var locationName: String?
        public var readState: String?
        public var unreadCount: Int?
    }

    public struct PlannerSubmissions: Codable, Equatable, Sendable {
        public var submitted: Bool?
        public var excused: Bool?
        public var graded: Bool?
        public var late: Bool?
        public var missing: Bool?
        public var needsGrading: Bool?
        public var hasFeedback: Bool?
    }

    public struct PlannerOverride: Codable, Identifiable, Equatable, Sendable {
        public var id: CanvasID
        public var plannableType: String?
        public var plannableId: CanvasID?
        public var markedComplete: Bool?
        public var dismissed: Bool?
    }

    /// `submissions` decodes as `false` (a JSON boolean) for items without a submission; treat that as nil.
    enum CodingKeys: String, CodingKey {
        case contextType, contextName, courseId, plannableId, plannableType, plannableDate, plannable, htmlUrl, submissions, plannerOverride, newActivity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contextType = try container.decodeIfPresent(String.self, forKey: .contextType)
        contextName = try container.decodeIfPresent(String.self, forKey: .contextName)
        courseId = try container.decodeIfPresent(CanvasID.self, forKey: .courseId)
        plannableId = try container.decode(CanvasID.self, forKey: .plannableId)
        plannableType = try container.decode(String.self, forKey: .plannableType)
        plannableDate = try container.decodeIfPresent(Date.self, forKey: .plannableDate)
        plannable = try container.decode(Plannable.self, forKey: .plannable)
        htmlUrl = try container.decodeIfPresent(String.self, forKey: .htmlUrl)
        submissions = try? container.decodeIfPresent(PlannerSubmissions.self, forKey: .submissions)
        plannerOverride = try? container.decodeIfPresent(PlannerOverride.self, forKey: .plannerOverride)
        newActivity = try container.decodeIfPresent(Bool.self, forKey: .newActivity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contextType, forKey: .contextType)
        try container.encodeIfPresent(contextName, forKey: .contextName)
        try container.encodeIfPresent(courseId, forKey: .courseId)
        try container.encode(plannableId, forKey: .plannableId)
        try container.encode(plannableType, forKey: .plannableType)
        try container.encodeIfPresent(plannableDate, forKey: .plannableDate)
        try container.encode(plannable, forKey: .plannable)
        try container.encodeIfPresent(htmlUrl, forKey: .htmlUrl)
        try container.encodeIfPresent(submissions, forKey: .submissions)
        try container.encodeIfPresent(plannerOverride, forKey: .plannerOverride)
        try container.encodeIfPresent(newActivity, forKey: .newActivity)
    }
}

public struct CalendarEvent: Codable, Identifiable, Equatable, Sendable {
    /// Numeric for real calendar events; `"assignment_123"` for assignment events from `upcoming_events`.
    public var id: String
    public var title: String
    public var description: String?
    public var startAt: Date?
    public var endAt: Date?
    public var allDay: Bool?
    public var locationName: String?
    public var contextCode: String?
    public var contextName: String?
    public var htmlUrl: String?
    public var type: String?
    public var workflowState: String?
    public var assignment: Assignment?

    public var courseId: CanvasID? {
        guard let code = contextCode, code.hasPrefix("course_") else { return nil }
        return CanvasID(code.dropFirst("course_".count))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, startAt, endAt, allDay, locationName, contextCode, contextName, htmlUrl, type, workflowState, assignment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try? c.decode(Int.self, forKey: .id) { id = String(number) } else { id = try c.decode(String.self, forKey: .id) }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
        contextCode = try c.decodeIfPresent(String.self, forKey: .contextCode)
        contextName = try c.decodeIfPresent(String.self, forKey: .contextName)
        htmlUrl = try c.decodeIfPresent(String.self, forKey: .htmlUrl)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        workflowState = try c.decodeIfPresent(String.self, forKey: .workflowState)
        assignment = try c.decodeIfPresent(Assignment.self, forKey: .assignment)
    }
}

public struct Conversation: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var subject: String?
    public var workflowState: String?
    public var lastMessage: String?
    public var lastMessageAt: Date?
    public var lastAuthoredMessageAt: Date?
    public var messageCount: Int?
    public var subscribed: Bool?
    public var starred: Bool?
    public var contextName: String?
    public var contextCode: String?
    public var avatarUrl: String?
    public var participants: [ConversationParticipant]?
    public var audience: [CanvasID]?
    public var messages: [ConversationMessage]?

    public var isUnread: Bool { workflowState == "unread" }
}

public struct ConversationParticipant: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var fullName: String?
    public var pronouns: String?
    public var avatarUrl: String?
}

public struct ConversationMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var authorId: CanvasID?
    public var createdAt: Date?
    public var body: String?
    public var generated: Bool?
    public var attachments: [CanvasFile]?
    public var participatingUserIds: [CanvasID]?
}

/// A person on the course People page.
public struct CourseUser: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var sortableName: String?
    public var shortName: String?
    public var avatarUrl: String?
    public var pronouns: String?
    public var email: String?
    public var enrollments: [UserEnrollment]?

    public struct UserEnrollment: Codable, Equatable, Sendable {
        public var type: String?
        public var role: String?
        public var enrollmentState: String?
        public var courseSectionId: CanvasID?
    }

    public var roleLabel: String {
        let type = enrollments?.first?.type ?? ""
        switch type {
        case "TeacherEnrollment": return "Teacher"
        case "TaEnrollment": return "TA"
        case "DesignerEnrollment": return "Designer"
        case "ObserverEnrollment": return "Observer"
        default: return "Student"
        }
    }
}

/// Activity-stream entry (`GET /users/self/activity_stream`).
public struct StreamItem: Codable, Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var type: String
    public var title: String?
    public var message: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var courseId: CanvasID?
    public var contextType: String?
    public var htmlUrl: String?
    public var readState: Bool?
    public var notificationCategory: String?
    public var assignmentId: CanvasID?
    public var announcementId: CanvasID?
    public var discussionTopicId: CanvasID?
    public var conversationId: CanvasID?
}
