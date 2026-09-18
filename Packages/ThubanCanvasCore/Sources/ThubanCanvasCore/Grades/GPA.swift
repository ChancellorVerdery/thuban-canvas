import Foundation

/// One course's contribution to a GPA.
public struct GPACourse: Identifiable, Equatable, Sendable {
    public var id: CanvasID
    public var name: String
    public var letter: String?
    public var credits: Double
    public var included: Bool

    public init(id: CanvasID, name: String, letter: String?, credits: Double, included: Bool = true) {
        self.id = id
        self.name = name
        self.letter = letter
        self.credits = credits
        self.included = included
    }

    public var points: Double? { letter.flatMap(GradePoints.points) }
}

/// A semester the user typed in by hand (Canvas has no transcript API).
public struct PastSemester: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var gpa: Double
    public var credits: Double

    public init(id: UUID = UUID(), name: String, gpa: Double, credits: Double) {
        self.id = id
        self.name = name
        self.gpa = gpa
        self.credits = credits
    }
}

public struct GPAResult: Equatable, Sendable {
    public var term: Double?
    public var termCredits: Double
    public var cumulative: Double?
    public var cumulativeCredits: Double
    /// Courses that could not be counted (no letter yet).
    public var skipped: [String]
}

public enum GPACalculator {
    public static func compute(courses: [GPACourse], past: [PastSemester]) -> GPAResult {
        var qualityPoints = 0.0
        var credits = 0.0
        var skipped: [String] = []
        for course in courses where course.included {
            guard let points = course.points, course.credits > 0 else {
                if course.credits > 0 { skipped.append(course.name) }
                continue
            }
            qualityPoints += points * course.credits
            credits += course.credits
        }
        let term = credits > 0 ? qualityPoints / credits : nil
        var allPoints = qualityPoints
        var allCredits = credits
        for semester in past where semester.credits > 0 {
            allPoints += semester.gpa * semester.credits
            allCredits += semester.credits
        }
        let cumulative = allCredits > 0 ? allPoints / allCredits : nil
        return GPAResult(term: term, termCredits: credits, cumulative: cumulative, cumulativeCredits: allCredits, skipped: skipped)
    }

    /// Two decimals, "—" when nil.
    public static func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }
}
