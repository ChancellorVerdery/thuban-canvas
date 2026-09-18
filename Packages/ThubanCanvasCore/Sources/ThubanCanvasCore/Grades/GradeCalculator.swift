import Foundation

/// A hypothetical entry in the what-if table.
public enum WhatIfScore: Codable, Equatable, Sendable {
    /// Pretend the assignment scored this many points.
    case score(Double)
    /// Pretend the assignment is not graded yet.
    case ungraded
}

/// Hypothetical scores the student types in the Grades table (what-if).
public struct WhatIf: Codable, Equatable, Sendable {
    /// assignment id → hypothetical score.
    public var scores: [CanvasID: WhatIfScore]
    /// Count every ungraded assignment as zero (Canvas's "final" score) instead of ignoring it.
    public var ungradedAsZero: Bool

    public init(scores: [CanvasID: WhatIfScore] = [:], ungradedAsZero: Bool = false) {
        self.scores = scores
        self.ungradedAsZero = ungradedAsZero
    }

    public static let none = WhatIf()
    public var isEmpty: Bool { scores.isEmpty && !ungradedAsZero }
}

/// Result of one course computation.
public struct CourseGrade: Equatable, Sendable {
    public struct GroupResult: Identifiable, Equatable, Sendable {
        public var id: CanvasID
        public var name: String
        public var weight: Double?
        public var earned: Double
        public var possible: Double
        public var dropped: Set<CanvasID>
        public var percent: Double? { possible > 0 ? earned / possible * 100 : nil }
    }

    public var percent: Double?
    public var groups: [GroupResult]
    public var earned: Double
    public var possible: Double
    public var weighted: Bool
}

/// Reproduces Canvas's current-score arithmetic from assignment groups + the student's submissions, with what-if
/// overrides layered on top.
public enum GradeCalculator {
    public static func compute(groups: [AssignmentGroup], weighted: Bool, whatIf: WhatIf = .none) -> CourseGrade {
        var results: [CourseGrade.GroupResult] = []
        for group in groups.sorted(by: { ($0.position ?? 0) < ($1.position ?? 0) }) {
            var entries: [(id: CanvasID, score: Double, possible: Double)] = []
            for assignment in group.assignments ?? [] where assignment.countsTowardGrade {
                guard let possible = assignment.pointsPossible, possible > 0 else { continue }
                if let override = whatIf.scores[assignment.id] {
                    switch override {
                    case .score(let score): entries.append((assignment.id, score, possible))
                    case .ungraded: if whatIf.ungradedAsZero { entries.append((assignment.id, 0, possible)) }
                    }
                    continue
                }
                if let submission = assignment.submission, submission.excused == true { continue }
                if let submission = assignment.submission, submission.isGraded, let score = submission.score {
                    entries.append((assignment.id, score, possible))
                } else if whatIf.ungradedAsZero {
                    entries.append((assignment.id, 0, possible))
                }
            }
            let dropped = applyDropRules(entries, rules: group.rules)
            let kept = entries.filter { !dropped.contains($0.id) }
            results.append(CourseGrade.GroupResult(
                id: group.id, name: group.name, weight: group.groupWeight,
                earned: kept.reduce(0) { $0 + $1.score }, possible: kept.reduce(0) { $0 + $1.possible }, dropped: dropped
            ))
        }

        let earned = results.reduce(0) { $0 + $1.earned }
        let possible = results.reduce(0) { $0 + $1.possible }
        let percent: Double?
        if weighted {
            // Canvas: Σ(weight × group %) over groups that have possible points, divided by those groups' total weight.
            let active = results.filter { $0.possible > 0 && ($0.weight ?? 0) > 0 }
            let totalWeight = active.reduce(0) { $0 + ($1.weight ?? 0) }
            if totalWeight > 0 {
                let sum = active.reduce(0.0) { $0 + ($1.weight ?? 0) * ($1.percent ?? 0) }
                percent = sum / totalWeight
            } else {
                percent = possible > 0 ? earned / possible * 100 : nil
            }
        } else {
            percent = possible > 0 ? earned / possible * 100 : nil
        }
        return CourseGrade(percent: percent, groups: results, earned: earned, possible: possible, weighted: weighted)
    }

    /// Drop-lowest / drop-highest: repeatedly removes the assignment whose removal best (or worst) moves the group
    /// percentage — the same greedy rule Canvas documents. `never_drop` ids are protected.
    static func applyDropRules(_ entries: [(id: CanvasID, score: Double, possible: Double)], rules: AssignmentGroup.Rules?) -> Set<CanvasID> {
        guard let rules else { return [] }
        let protected = Set(rules.neverDrop ?? [])
        var remaining = entries
        var dropped = Set<CanvasID>()
        func percent(_ list: [(id: CanvasID, score: Double, possible: Double)]) -> Double {
            let possible = list.reduce(0) { $0 + $1.possible }
            return possible > 0 ? list.reduce(0) { $0 + $1.score } / possible : 0
        }
        for _ in 0..<(rules.dropLowest ?? 0) {
            let candidates = remaining.filter { !protected.contains($0.id) }
            guard candidates.count > 1 else { break }
            var best: (id: CanvasID, percent: Double)?
            for candidate in candidates {
                let without = remaining.filter { $0.id != candidate.id }
                let value = percent(without)
                if best == nil || value > best!.percent { best = (candidate.id, value) }
            }
            guard let pick = best else { break }
            dropped.insert(pick.id)
            remaining.removeAll { $0.id == pick.id }
        }
        for _ in 0..<(rules.dropHighest ?? 0) {
            let candidates = remaining.filter { !protected.contains($0.id) }
            guard candidates.count > 1 else { break }
            var worst: (id: CanvasID, percent: Double)?
            for candidate in candidates {
                let without = remaining.filter { $0.id != candidate.id }
                let value = percent(without)
                if worst == nil || value < worst!.percent { worst = (candidate.id, value) }
            }
            guard let pick = worst else { break }
            dropped.insert(pick.id)
            remaining.removeAll { $0.id == pick.id }
        }
        return dropped
    }

    /// Points needed on a future assignment (worth `possible`) to reach `target` percent, given the current state.
    /// Only meaningful for unweighted courses or within one weighted group; returns nil when unreachable.
    public static func pointsNeeded(currentEarned: Double, currentPossible: Double, upcoming possible: Double, target: Double) -> Double? {
        let needed = target / 100 * (currentPossible + possible) - currentEarned
        guard needed <= possible + 1e-9 else { return nil }
        return max(0, needed)
    }
}
