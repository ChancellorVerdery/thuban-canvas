import Foundation
import ThubanCanvasCore

/// SwiftUI's `ColorScheme` shadows the core type inside the app target.
typealias ThubanScheme = ThubanCanvasCore.ColorScheme

/// Top-level tabs in the title bar: Home, then one per starred course.
enum AppTab: Hashable, Codable {
    case home
    case course(CanvasID)

    var storageKey: String {
        switch self {
        case .home: return "home"
        case .course(let id): return "course:\(id)"
        }
    }

    init?(storageKey: String) {
        if storageKey == "home" { self = .home; return }
        guard storageKey.hasPrefix("course:"), let id = CanvasID(storageKey.dropFirst("course:".count)) else { return nil }
        self = .course(id)
    }
}

/// Utility panels reachable from the title bar's right side (not tabs).
enum UtilityPanel: String, Hashable { case calendar, inbox }

/// The uniform section set every course tab offers, in display order. Sections the course does not support are
/// hidden by `CourseSession.availableSections`.
enum CourseSection: String, CaseIterable, Hashable, Codable {
    case overview, modules, assignments, grades, files, announcements, discussions, pages, syllabus, people

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .modules: return "Modules"
        case .assignments: return "Assignments"
        case .grades: return "Grades"
        case .files: return "Files"
        case .announcements: return "Announcements"
        case .discussions: return "Discussions"
        case .pages: return "Pages"
        case .syllabus: return "Syllabus"
        case .people: return "People"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .modules: return "list.bullet.rectangle"
        case .assignments: return "checklist"
        case .grades: return "chart.bar"
        case .files: return "folder"
        case .announcements: return "megaphone"
        case .discussions: return "bubble.left.and.bubble.right"
        case .pages: return "doc.text"
        case .syllabus: return "book"
        case .people: return "person.2"
        }
    }
}

/// A detail screen pushed inside a course tab.
enum CourseRoute: Hashable {
    case assignment(CanvasID)
    case page(slug: String)
    case file(CanvasID)
    case discussion(CanvasID)
    case quiz(CanvasID)
    case module(CanvasID)
    case externalURL(URL)
}
