import Foundation

/// Letter cutoffs, highest first. Values are percentages (90 = 90 %).
public struct GradingScheme: Codable, Equatable, Sendable {
    public struct Cutoff: Codable, Equatable, Sendable {
        public var letter: String
        public var minimum: Double
        public init(_ letter: String, _ minimum: Double) { self.letter = letter; self.minimum = minimum }
    }

    public var title: String
    public var cutoffs: [Cutoff]

    public init(title: String, cutoffs: [Cutoff]) {
        self.title = title
        self.cutoffs = cutoffs.sorted { $0.minimum > $1.minimum }
    }

    /// A 90 / B 80 / C 70 / D 60.
    public static let plain = GradingScheme(title: "Letters", cutoffs: [
        Cutoff("A", 90), Cutoff("B", 80), Cutoff("C", 70), Cutoff("D", 60), Cutoff("F", 0),
    ])

    /// The common plus/minus scale.
    public static let plusMinus = GradingScheme(title: "Plus / minus", cutoffs: [
        Cutoff("A", 93), Cutoff("A-", 90), Cutoff("B+", 87), Cutoff("B", 83), Cutoff("B-", 80),
        Cutoff("C+", 77), Cutoff("C", 73), Cutoff("C-", 70), Cutoff("D+", 67), Cutoff("D", 63), Cutoff("D-", 60), Cutoff("F", 0),
    ])

    public init(standard: GradingStandard) {
        self.init(title: standard.title, cutoffs: standard.gradingScheme.map { Cutoff($0.name, $0.value * 100) })
    }

    /// Parses "A 90, B 80, C 70" (also "A:90; B=80"). Returns nil when nothing parses.
    public init?(parsing text: String) {
        let pieces = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
        var cutoffs: [Cutoff] = []
        for piece in pieces {
            let parts = piece.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "=" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard parts.count == 2, let raw = Double(parts[1].replacingOccurrences(of: "%", with: "")), raw.isFinite else { continue }
            cutoffs.append(Cutoff(parts[0].uppercased(), min(max(raw, 0), 1000)))
        }
        guard !cutoffs.isEmpty else { return nil }
        if !cutoffs.contains(where: { $0.minimum == 0 }) { cutoffs.append(Cutoff("F", 0)) }
        self.init(title: "Custom", cutoffs: cutoffs)
    }

    /// "A 90, B 80, C 70, D 60"
    public var summary: String {
        cutoffs.filter { $0.minimum > 0 }.map { "\($0.letter) \(Self.format($0.minimum))" }.joined(separator: ", ")
    }

    /// The letter for a percentage. Canvas rounds the score to two decimals before comparing.
    public func letter(for percent: Double) -> String {
        let rounded = (percent * 100).rounded() / 100
        for cutoff in cutoffs where rounded >= cutoff.minimum - 1e-9 { return cutoff.letter }
        return cutoffs.last?.letter ?? "F"
    }

    /// The next cutoff above `percent` (nil at the top).
    public func nextCutoff(above percent: Double) -> Cutoff? {
        cutoffs.reversed().first { $0.minimum > percent }
    }

    static func format(_ value: Double) -> String {
        guard abs(value) < 1e15 else { return String(format: "%.0f", value) }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// 4.0-scale points for a letter (A+ counts as 4.0). Unknown letters → nil (P, S, I, W …).
public enum GradePoints {
    public static let table: [String: Double] = [
        "A+": 4.0, "A": 4.0, "A-": 3.7,
        "B+": 3.3, "B": 3.0, "B-": 2.7,
        "C+": 2.3, "C": 2.0, "C-": 1.7,
        "D+": 1.3, "D": 1.0, "D-": 0.7,
        "F": 0.0,
    ]

    public static func points(for letter: String) -> Double? {
        table[letter.trimmingCharacters(in: .whitespaces).uppercased()]
    }
}
