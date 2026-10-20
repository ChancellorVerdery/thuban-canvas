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

/// One class in a past semester: name, credit hours and the letter earned.
public struct PastClass: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var credits: Double
    /// Letter as shown on the transcript ("A-", "B+"); empty until chosen.
    public var letter: String

    public init(id: UUID = UUID(), name: String = "", credits: Double = 3, letter: String = "") {
        self.id = id
        self.name = name
        self.credits = credits
        self.letter = letter
    }

    public var points: Double? { GradePoints.points(for: letter) }
    /// Counts toward the semester GPA only with a recognised letter and positive credits.
    public var counts: Bool { points != nil && credits > 0 }
}

/// A semester the user typed in by hand (Canvas has no transcript API). Either lists its classes — the GPA and
/// credits are then computed — or, with no classes, carries a GPA and credit total typed directly.
public struct PastSemester: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var classes: [PastClass]
    /// Which letters the class picker offers (plus/minus or plain letters).
    public var scale: LetterScale
    /// Typed totals, used only when `classes` is empty.
    public var manualGPA: Double
    public var manualCredits: Double

    public init(id: UUID = UUID(), name: String, gpa: Double = 0, credits: Double = 0, classes: [PastClass] = [], scale: LetterScale = .plusMinus) {
        self.id = id
        self.name = name
        self.classes = classes
        self.scale = scale
        manualGPA = gpa
        manualCredits = credits
    }

    // Stored as `gpa` / `credits` so files written before classes existed still load.
    enum CodingKeys: String, CodingKey { case id, name, classes, scale, manualGPA = "gpa", manualCredits = "credits" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        classes = try c.decodeIfPresent([PastClass].self, forKey: .classes) ?? []
        scale = try c.decodeIfPresent(LetterScale.self, forKey: .scale) ?? .plusMinus
        manualGPA = try c.decodeIfPresent(Double.self, forKey: .manualGPA) ?? 0
        manualCredits = try c.decodeIfPresent(Double.self, forKey: .manualCredits) ?? 0
    }

    public var usesClasses: Bool { !classes.isEmpty }

    /// Credits that count: the sum over classes with a letter, or the typed total.
    public var credits: Double {
        usesClasses ? classes.filter(\.counts).reduce(0) { $0 + $1.credits } : manualCredits
    }

    /// Semester GPA; nil when nothing counts yet.
    public var gpa: Double? {
        if usesClasses {
            let counted = classes.filter(\.counts)
            let credits = counted.reduce(0) { $0 + $1.credits }
            guard credits > 0 else { return nil }
            return counted.reduce(0) { $0 + ($1.points ?? 0) * $1.credits } / credits
        }
        return manualCredits > 0 ? manualGPA : nil
    }

    /// Classes without a letter yet (they are left out of the GPA).
    public var unlettered: Int { classes.filter { !$0.counts }.count }
}

public struct GPAResult: Equatable, Sendable {
    public var term: Double?
    public var termCredits: Double
    public var cumulative: Double?
    public var cumulativeCredits: Double
    /// Cumulative GPA of the past semesters alone — where it stood before this term.
    public var prior: Double?
    public var priorCredits: Double
    /// Courses that could not be counted (no letter yet).
    public var skipped: [String]

    public init(term: Double?, termCredits: Double, cumulative: Double?, cumulativeCredits: Double,
                prior: Double? = nil, priorCredits: Double = 0, skipped: [String]) {
        self.term = term
        self.termCredits = termCredits
        self.cumulative = cumulative
        self.cumulativeCredits = cumulativeCredits
        self.prior = prior
        self.priorCredits = priorCredits
        self.skipped = skipped
    }

    /// How far this term moves the cumulative GPA from where it stood before the term.
    public var cumulativeChange: Double? {
        guard let cumulative, let prior else { return nil }
        return cumulative - prior
    }
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
        var priorPoints = 0.0
        var priorCredits = 0.0
        for semester in past {
            guard let gpa = semester.gpa, semester.credits > 0 else { continue }
            priorPoints += gpa * semester.credits
            priorCredits += semester.credits
        }
        let allPoints = qualityPoints + priorPoints
        let allCredits = credits + priorCredits
        let cumulative = allCredits > 0 ? allPoints / allCredits : nil
        let prior = priorCredits > 0 ? priorPoints / priorCredits : nil
        return GPAResult(term: term, termCredits: credits, cumulative: cumulative, cumulativeCredits: allCredits,
                         prior: prior, priorCredits: priorCredits, skipped: skipped)
    }

    /// Two decimals, "—" when nil.
    public static func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }
}
