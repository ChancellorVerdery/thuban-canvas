import AppKit
import SwiftUI
import ThubanCanvasCore

/// Formatting shared by the Assignments, Grades, Announcements and Discussions screens.
enum WorkText {
    /// "Sun, Sep 21 · 11:59 PM" (adds the year when it differs from now).
    static func full(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = sameYear
            ? date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        return day + " · " + date.formatted(date: .omitted, time: .shortened)
    }

    /// "Tomorrow · 11:59 PM · in 21 h" for future dates, "Sep 7 · 11:59 PM" for past ones, "No due date" when nil.
    static func due(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "No due date" }
        let relative = DueFormatter.relative(date, now: now)
        // Weekday names are ambiguous on their own ("Tuesday" could be last week's or next week's): add the distance.
        return abs(date.timeIntervalSince(now)) < 6 * 86_400 || date > now ? relative + " · " + DueFormatter.countdown(date, now: now) : relative
    }

    /// "Today" / "Yesterday" / "Sep 13" / "Sep 13, 2024" for list metadata.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// score ÷ possible as "94.5%"; nil when either side is missing or possible is 0.
    static func percent(score: Double?, possible: Double?, decimals: Int = 1) -> String? {
        guard let score, let possible, possible > 0 else { return nil }
        return DueFormatter.percent(score / possible * 100, decimals: decimals)
    }

    /// "30%" for a group weight; whole numbers stay whole.
    static func weight(_ value: Double?) -> String? {
        guard let value else { return nil }
        return value == value.rounded() ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    /// Human labels for `submission_types`, folding allowed extensions into the upload chip.
    static func submissionTypes(_ assignment: Assignment) -> [String] {
        (assignment.submissionTypes ?? []).map { type in
            switch type {
            case "online_upload":
                if let extensions = assignment.allowedExtensions, !extensions.isEmpty {
                    return "Online upload · " + extensions.map { $0.uppercased() }.joined(separator: ", ")
                }
                return "Online upload"
            case "online_text_entry": return "Text entry"
            case "online_url": return "Website URL"
            case "media_recording": return "Media recording"
            case "student_annotation": return "Annotation"
            case "online_quiz": return "Quiz"
            case "discussion_topic": return "Discussion"
            case "external_tool": return "External tool"
            case "on_paper": return "On paper"
            case "none": return "No submission"
            case "not_graded": return "Not graded"
            default: return type.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    /// "1 reply", "173 replies".
    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(plural ?? singular + "s")"
    }
}

extension WorkItem.Kind {
    /// SF Symbol for a row's leading glyph.
    var symbol: String {
        switch self {
        case .assignment: return "doc.text"
        case .quiz: return "checkmark.square"
        case .discussion: return "bubble.left.and.bubble.right"
        case .event: return "calendar"
        case .todo: return "checklist"
        }
    }

    var label: String {
        switch self {
        case .assignment: return "Assignment"
        case .quiz: return "Quiz"
        case .discussion: return "Discussion"
        case .event: return "Event"
        case .todo: return "To-do"
        }
    }
}

extension Assignment {
    var kind: WorkItem.Kind {
        if isQuizAssignment == true || quizId != nil || submissionTypes?.contains("online_quiz") == true { return .quiz }
        if discussionTopic != nil || submissionTypes?.contains("discussion_topic") == true { return .discussion }
        return .assignment
    }

    var isExternalTool: Bool { submissionTypes?.contains("external_tool") == true }

    /// Whether the student gradebook lists this assignment at all.
    var showsInGradebook: Bool { published != false && hideInGradebook != true }
}

/// Opens a Canvas page in the default browser.
enum CanvasBrowser {
    static func open(_ raw: String?) {
        guard let raw, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// An eyebrow label above a value, for detail headers ("DUE" / "Tomorrow · 11:59 PM").
struct MetaField: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var value: String
    var tone: Tone = .normal

    enum Tone { case normal, dim, neg }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(ThubanFont.micro)
                .kerning(0.5)
                .foregroundStyle(theme.inkDimColor)
            Text(value)
                .font(ThubanFont.body(14, weight: .medium))
                .foregroundStyle(color)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var color: Color {
        switch tone {
        case .normal: return theme.inkColor
        case .dim: return theme.inkDimColor
        case .neg: return theme.negTextColor
        }
    }
}

/// A quiet inline note with a leading symbol (lock explanations, "opens in Canvas", success messages).
struct InlineNote: View {
    @Environment(\.thubanTheme) private var theme
    var symbol: String
    var text: String
    var tone: Tone = .neutral

    enum Tone { case neutral, warn, pos, neg }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(text).font(ThubanFont.small).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return theme.inkDimColor
        case .warn: return theme.brassInkColor
        case .pos: return theme.posTextColor
        case .neg: return theme.negTextColor
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return theme.panel2Color
        case .warn: return theme.warnSoftColor
        case .pos: return theme.posSoftColor
        case .neg: return theme.negSoftColor
        }
    }
}

/// The standard frame for a scrolling course section: 24 pt gutters, content capped at a readable width.
struct SectionPage<Content: View>: View {
    var maxWidth: CGFloat = 1080
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
