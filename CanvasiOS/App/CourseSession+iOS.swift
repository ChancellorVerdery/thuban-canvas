import Foundation
import ThubanCanvasCore

/// Derived facts the iOS course hub, grades and modules screens show.
extension CourseSession {
    /// Assignments that count toward the grade.
    var countedAssignments: [Assignment] {
        assignments.filter { $0.countsTowardGrade && $0.published != false }
    }

    var gradedCount: Int { countedAssignments.filter { $0.submission?.isGraded == true }.count }

    /// "0.5 above the A line" from the letter's cutoff in the course scheme.
    var cutoffNote: String? {
        guard let score = displayScore, let letter = displayLetter else { return nil }
        guard let cutoff = gradingScheme.cutoffs.first(where: { $0.letter == letter }) ?? gradingScheme.cutoffs.first(where: { score >= $0.minimum - 1e-9 }) else { return nil }
        let above = score - cutoff.minimum
        guard cutoff.minimum > 0 else { return nil }
        return "\(String(format: "%.1f", max(0, above))) above the \(cutoff.letter) line"
    }

    /// Graded in the last four days (the "New" chip).
    func isNewlyGraded(_ assignment: Assignment, now: Date = Date()) -> Bool {
        guard let submission = assignment.submission, submission.isGraded else { return false }
        guard let graded = submission.gradedAt ?? submission.postedAt else { return false }
        return now.timeIntervalSince(graded) < 4 * 86_400
    }

    var newGradeCount: Int { countedAssignments.filter { isNewlyGraded($0) }.count }

    var dueThisWeekCount: Int { WorkItemBuilder.upcoming(workItems, within: 7).count }

    var nextUp: WorkItem? { WorkItemBuilder.upcoming(workItems).first }

    /// The module to focus on: the first unlocked, unfinished one (Canvas "started"/"unlocked"), else the last completed.
    var currentModuleIndex: Int? {
        guard let list = modules.value, !list.isEmpty else { return nil }
        if let index = list.firstIndex(where: { $0.state == "started" || $0.state == "unlocked" }) { return index }
        if let index = list.lastIndex(where: { $0.state == "completed" }) { return index }
        return 0
    }

    /// "Week 5 of 15"
    var moduleSummary: String? {
        guard let list = modules.value, let index = currentModuleIndex else { return nil }
        let head = ModuleName.split(list[index].name).eyebrow ?? "Module \(index + 1)"
        return "\(head) of \(list.count)"
    }

    var unreadAnnouncementCount: Int { (announcements.value ?? []).filter { $0.readState == "unread" }.count }

    /// Hub rows in order; Overview is the hub itself.
    var hubSections: [HubSection] {
        HubSection.allCases.filter { section in
            switch section {
            case .overview: return false
            case .assignments, .grades: return true
            case .modules: return course.hasTab("modules") && !modules.unavailable
            case .announcements: return course.hasTab("announcements") && !announcements.unavailable
            case .discussions: return course.hasTab("discussions") && !discussions.unavailable
            case .syllabus: return course.hasTab("syllabus") || !(course.syllabusBody ?? "").isEmpty
            case .people: return course.hasTab("people") && !people.unavailable
            case .files: return course.hasTab("files") && !files.unavailable
            case .pages: return course.hasTab("pages") && !pages.unavailable
            }
        }
    }

    /// "Files, Pages off in this course"
    var missingSectionsNote: String? {
        let optional: [HubSection] = [.modules, .files, .pages, .discussions, .announcements]
        let off = optional.filter { !hubSections.contains($0) }.map(\.label)
        guard !off.isEmpty else { return nil }
        return off.prefix(3).joined(separator: ", ") + " off in this course"
    }

    /// Loads what the hub's row summaries need, in parallel (reads only).
    func loadHub() async {
        async let groups: Void = loadGroups()
        async let modules: Void = course.hasTab("modules") ? loadModules() : ()
        async let announcements: Void = course.hasTab("announcements") ? loadAnnouncements() : ()
        async let discussions: Void = course.hasTab("discussions") ? loadDiscussions() : ()
        async let people: Void = course.hasTab("people") ? loadPeople() : ()
        _ = await (groups, modules, announcements, discussions, people)
    }

    /// The assignment group an assignment belongs to.
    func group(of assignment: Assignment) -> AssignmentGroup? {
        (groups.value ?? []).first { $0.assignments?.contains { $0.id == assignment.id } == true }
    }

    /// "Homework · 25%"
    func groupLabel(of assignment: Assignment) -> String? {
        guard let group = group(of: assignment) else { return nil }
        if course.applyAssignmentGroupWeights == true, let weight = group.groupWeight, weight > 0 {
            return "\(group.name) · \(PointsText.short(weight))%"
        }
        return group.name
    }
}

extension Assignment {
    /// "File upload · PDF", "Text entry", "External tool", "On paper".
    var submitAsLabel: String {
        let types = submissionTypes ?? []
        var parts: [String] = []
        for type in types {
            switch type {
            case "online_upload": parts.append("File upload")
            case "online_text_entry": parts.append("Text entry")
            case "online_url": parts.append("Website URL")
            case "online_quiz": parts.append("Quiz")
            case "external_tool": parts.append("External tool")
            case "on_paper": parts.append("On paper")
            case "discussion_topic": parts.append("Discussion")
            case "media_recording": parts.append("Media")
            case "none", "not_graded": parts.append("Nothing to submit")
            default: break
            }
        }
        var label = parts.isEmpty ? "—" : parts.joined(separator: ", ")
        if types.contains("online_upload"), let extensions = allowedExtensions, !extensions.isEmpty {
            label += " · " + extensions.map { $0.uppercased() }.joined(separator: ", ")
        }
        return label
    }

    var attemptsLabel: String {
        guard let attempts = allowedAttempts, attempts > 0 else { return "Unlimited" }
        return "\(attempts)"
    }

    var showsInGradebook: Bool { published != false && hideInGradebook != true }
}
