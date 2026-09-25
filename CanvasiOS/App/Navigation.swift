import Foundation
import ThubanCanvasCore

/// The four iPhone tabs (Settings is a sheet from Home's gear).
enum MainTab: String, CaseIterable, Hashable {
    case home, courses, calendar, inbox

    var title: String {
        switch self {
        case .home: return "Home"
        case .courses: return "Courses"
        case .calendar: return "Calendar"
        case .inbox: return "Inbox"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .courses: return "books.vertical"
        case .calendar: return "calendar"
        case .inbox: return "tray"
        }
    }
}

/// Everything that can be pushed on a navigation stack.
enum Route: Hashable {
    case course(CanvasID)
    case modules(CanvasID)
    case assignments(CanvasID)
    case grades(CanvasID)
    case announcements(CanvasID)
    case discussions(CanvasID)
    case syllabus(CanvasID)
    case people(CanvasID)
    case files(CanvasID)
    case pages(CanvasID)
    case assignment(course: CanvasID, id: CanvasID)
    case page(course: CanvasID, slug: String)
    case announcement(course: CanvasID, id: CanvasID)
    case discussion(course: CanvasID, id: CanvasID)
    case event(String)
    case conversation(CanvasID)
    case pastSemesters

    /// The course this route belongs to, if any.
    var courseId: CanvasID? {
        switch self {
        case .course(let id), .modules(let id), .assignments(let id), .grades(let id), .announcements(let id),
             .discussions(let id), .syllabus(let id), .people(let id), .files(let id), .pages(let id):
            return id
        case .assignment(let course, _), .page(let course, _), .announcement(let course, _), .discussion(let course, _):
            return course
        case .event, .conversation, .pastSemesters:
            return nil
        }
    }

    /// Short name used as the back-button title on the next screen.
    @MainActor
    func backTitle(app: AppModel) -> String {
        switch self {
        case .course(let id): return app.sessions[id]?.shortTitle ?? "Course"
        case .modules: return "Modules"
        case .assignments: return "Assignments"
        case .grades: return "Grades"
        case .announcements: return "Announcements"
        case .discussions: return "Discussions"
        case .syllabus: return "Syllabus"
        case .people: return "People"
        case .files: return "Files"
        case .pages: return "Pages"
        case .assignment: return "Assignment"
        case .page: return "Page"
        case .announcement: return "Announcement"
        case .discussion: return "Discussion"
        case .event: return "Event"
        case .conversation: return "Message"
        case .pastSemesters: return "Past semesters"
        }
    }
}

/// Course sections shown in the hub and the iPad section bar, in display order.
enum HubSection: String, CaseIterable, Hashable {
    case overview, modules, assignments, grades, announcements, discussions, syllabus, people, files, pages

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .modules: return "Modules"
        case .assignments: return "Assignments"
        case .grades: return "Grades"
        case .announcements: return "Announcements"
        case .discussions: return "Discussions"
        case .syllabus: return "Syllabus"
        case .people: return "People"
        case .files: return "Files"
        case .pages: return "Pages"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .modules: return "list.bullet.rectangle"
        case .assignments: return "checklist"
        case .grades: return "chart.bar"
        case .announcements: return "megaphone"
        case .discussions: return "bubble.left.and.bubble.right"
        case .syllabus: return "book.closed"
        case .people: return "person.2"
        case .files: return "folder"
        case .pages: return "doc.text"
        }
    }

    func route(_ course: CanvasID) -> Route {
        switch self {
        case .overview: return .course(course)
        case .modules: return .modules(course)
        case .assignments: return .assignments(course)
        case .grades: return .grades(course)
        case .announcements: return .announcements(course)
        case .discussions: return .discussions(course)
        case .syllabus: return .syllabus(course)
        case .people: return .people(course)
        case .files: return .files(course)
        case .pages: return .pages(course)
        }
    }
}

/// iPad sidebar selection.
enum SidebarItem: Hashable {
    case home, calendar, inbox
    case course(CanvasID)
}
