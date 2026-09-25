import Foundation
import SwiftSoup

// Short, phone-width strings for the iOS app (the Mac keeps `DueFormatter.relative`). Every function takes `now`
// and a `Calendar` so the output is deterministic in tests; the calendar's time zone is used for display.

public extension DueFormatter {
    /// "Today · 4:00 PM", "Tomorrow · 11:59 PM", "Yesterday · 8:00 AM", "Sun · 11:59 PM" within the next six days,
    /// "Thu Oct 1" (no time) further out, "Sep 18" in the past, "Sep 18, 2025" in another year.
    static func compact(_ date: Date, now: Date = Date(), calendar: Calendar = .current, includeTime: Bool = true) -> String {
        let time = includeTime ? " · " + format(date, "h:mm a", calendar) : ""
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch offset {
        case 0: return "Today" + time
        case 1: return "Tomorrow" + time
        case -1: return "Yesterday" + time
        case 2...6: return format(date, "EEE", calendar) + time
        default:
            if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
                return format(date, "MMM d, yyyy", calendar)
            }
            return offset > 0 ? format(date, "EEE MMM d", calendar) : format(date, "MMM d", calendar)
        }
    }

    /// Just the day part of `compact`: "Today", "Tomorrow", "Sun", "Thu Oct 1".
    static func compactDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        compact(date, now: now, calendar: calendar, includeTime: false)
    }

    /// "Sat Sep 26 · 11:59 PM"
    static func full(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "EEE MMM d", calendar) + " · " + format(date, "h:mm a", calendar)
    }

    /// "11:59 PM"
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "h:mm a", calendar)
    }

    /// Day-and-minute countdown for the assignment due card: "in 1d 9h 27m", "in 3h 5m", "in 12m", "2d 3h ago".
    static func preciseCountdown(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        let total = Int(abs(seconds) / 60)
        let days = total / 1_440
        let hours = (total % 1_440) / 60
        let minutes = total % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 || days > 0 { parts.append("\(hours)h") }
        if days == 0 { parts.append("\(max(minutes, seconds >= 0 ? 1 : 0))m") } else { parts.append("\(minutes)m") }
        let text = parts.joined(separator: " ")
        return seconds >= 0 ? "in \(text)" : "\(text) ago"
    }

    /// Words for the course hub: "in 1 day 9 hr", "in 5 hr", "in 40 min", "in 12 days".
    static func friendlyCountdown(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        let minutes = Int(abs(seconds) / 60)
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let text: String
        if days >= 3 { text = "\(days) days" }
        else if days >= 1 { text = hours > 0 ? "\(days) day\(days == 1 ? "" : "s") \(hours) hr" : "\(days) day\(days == 1 ? "" : "s")" }
        else if hours >= 1 { text = "\(hours) hr" }
        else { text = "\(max(1, minutes)) min" }
        return seconds >= 0 ? "in \(text)" : "\(text) ago"
    }

    /// How late something is: "2 days late", "1 day late", "5 hr late", "Due now".
    static func lateness(_ due: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(due)
        guard seconds > 60 else { return "Due now" }
        let days = Int(seconds / 86_400)
        if days >= 1 { return "\(days) day\(days == 1 ? "" : "s") late" }
        let hours = Int(seconds / 3_600)
        if hours >= 1 { return "\(hours) hr late" }
        return "\(Int(seconds / 60)) min late"
    }

    /// Eyebrow over the due card: "Due today", "Due tomorrow", "Due Sunday", "Due in 12 days", "Was due 2 days ago".
    static func dueEyebrow(_ due: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        if due < now {
            if offset == 0 { return "Was due today" }
            let days = -offset
            return days == 1 ? "Was due yesterday" : "Was due \(days) days ago"
        }
        switch offset {
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        case 2...6: return "Due " + format(due, "EEEE", calendar)
        default: return "Due in \(offset) days"
        }
    }

    /// Status chip text: "Refreshed just now", "Refreshed 4 min ago", "Refreshed 2 hr ago", "Refreshed Sep 18".
    static func refreshed(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "Not refreshed yet" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Refreshed just now" }
        if seconds < 3_600 { return "Refreshed \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "Refreshed \(Int(seconds / 3_600)) hr ago" }
        return "Refreshed " + format(date, "MMM d", calendar)
    }

    /// "1 day, 1 hour" for reminder lead times (hours, largest first).
    static func leadTimes(_ hours: [Int]) -> String {
        let sorted = Array(Set(hours.filter { $0 > 0 })).sorted(by: >)
        guard !sorted.isEmpty else { return "Off" }
        return sorted.map { hours in
            if hours % 24 == 0 { let days = hours / 24; return "\(days) day\(days == 1 ? "" : "s")" }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }.joined(separator: ", ")
    }

    /// Byte counts: "96 KB", "1.4 MB".
    static func bytes(_ count: Int?) -> String {
        guard let count, count >= 0 else { return "" }
        if count < 1_000 { return "\(count) B" }
        if count < 1_000_000 { return "\(Int((Double(count) / 1_000).rounded())) KB" }
        if count < 1_000_000_000 { return String(format: "%.1f MB", Double(count) / 1_000_000) }
        return String(format: "%.1f GB", Double(count) / 1_000_000_000)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// Module names like "Week 5: Laplace transforms" split into an eyebrow ("Week 5") and a title.
public enum ModuleName {
    public static func split(_ name: String) -> (eyebrow: String?, title: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [":", " · ", " – ", " — ", " - ", " | "] {
            guard let range = trimmed.range(of: separator) else { continue }
            let head = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let tail = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !head.isEmpty, !tail.isEmpty, head.count <= 16, head.contains(where: \.isNumber) else { continue }
            return (head, tail)
        }
        return (nil, trimmed)
    }
}

/// Pieces of SIS-style course codes ("202680-MATH-2171-005-10500").
public enum CourseCodeParser {
    /// The section number ("005"), or nil when the code carries none (cross-listed and training courses).
    public static func section(from code: String?) -> String? {
        guard let code, !code.contains(":") else { return nil }
        let pattern = #"[A-Z]{2,5}[-_ ]\d{3,4}[A-Z]?[-_ ]([A-Z]?\d{3})(?:[-_ ]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
              let range = Range(match.range(at: 1), in: code) else { return nil }
        return String(code[range])
    }
}

public extension CanvasHTML {
    /// A Canvas file an HTML fragment links to (an instructor's "PS5.pdf" inside an assignment description).
    struct FileLink: Equatable, Sendable {
        public var id: CanvasID
        public var course: CanvasID?
        public var name: String
    }

    /// Every distinct same-host file link in the fragment, in document order.
    static func fileLinks(_ html: String?, host: String) -> [FileLink] {
        guard let html, !html.isEmpty, let document = try? SwiftSoup.parseBodyFragment(html),
              let anchors = try? document.select("a[href]") else { return [] }
        var seen = Set<CanvasID>()
        var links: [FileLink] = []
        for anchor in anchors {
            guard let href = try? anchor.attr("href") else { continue }
            let absolute = href.hasPrefix("/") ? host + href : href
            guard let url = URL(string: absolute), case .file(let course, let id)? = classify(url, host: host) else { continue }
            guard seen.insert(id).inserted else { continue }
            let text = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = ((try? anchor.attr("title")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = !text.isEmpty && text != "Link" ? text : (!title.isEmpty && title != "Link" ? title : "File \(id)")
            links.append(FileLink(id: id, course: course, name: name))
        }
        return links
    }
}
