import SwiftUI
import ThubanCanvasCore

/// One card per starred course: name, code, current score + letter, teacher, a score bar and what is due.
/// Adaptive columns: four across at 1400 pt, three at 1100 pt.
struct HomeGradeBoard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            ForEach(app.orderedSessions) { session in
                HomeGradeCard(session: session)
            }
        }
    }
}

/// A course's grade at a glance. Click → the course's Grades section.
struct HomeGradeCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    @State private var hovering = false

    var body: some View {
        Button {
            app.open(course: session.id, section: .grades)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CourseDot(tint: session.preferences.tint, size: 9)
                    Text(session.displayName)
                        .font(ThubanFont.display(17))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(subtitle)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
                    .padding(.leading, 17)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(DueFormatter.percent(score))
                        .font(ThubanFont.display(30))
                        .foregroundStyle(score == nil ? theme.inkFaintColor : theme.inkColor)
                        .monospacedDigit()
                    if let letter = session.displayLetter {
                        Chip.letter(letter)
                        if session.canvasLetter == nil || !session.whatIf.isEmpty {
                            Text("est.").font(ThubanFont.micro).foregroundStyle(theme.inkDimColor)
                        }
                    }
                    Spacer(minLength: 0)
                    if !session.whatIf.isEmpty { Chip("What-if", kind: .warn) }
                }
                .padding(.top, 2)

                ProgressBar(value: (score ?? 0) / 100, height: 4, tint: session.preferences.tint.map { Color(hex: $0) })
                    .accessibilityHidden(true)

                Text(dueLine)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? theme.panel2Color : theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help("Open \(session.displayName) grades")
    }

    private var score: Double? { session.displayScore }

    /// "MATH 2241 · Mark Ellison" (extra teachers as "+3"). Falls back to whichever half exists.
    private var subtitle: String {
        var parts: [String] = []
        let code = session.shortCode
        if !code.isEmpty, code != session.course.courseCode { parts.append(code) }
        if let teachers = session.course.teachers, let first = teachers.first {
            parts.append(teachers.count > 1 ? "\(first.displayName) +\(teachers.count - 1)" : first.displayName)
        }
        if parts.isEmpty, let term = session.course.term?.name { parts.append(term) }
        return parts.joined(separator: " · ")
    }

    private var dueLine: String {
        if let line = HomeSummary.dueLine(for: session, dismissed: app.settings.dismissedOverdue) { return line }
        if session.groups.isLoading { return "Loading assignments…" }
        if session.groups.unavailable { return "Assignments not available" }
        if session.groups.error != nil { return "Assignments couldn’t load" }
        return "No assignments yet"
    }

    private var accessibilityText: String {
        var text = session.displayName
        if let score { text += ", \(DueFormatter.percent(score))" } else { text += ", no grade yet" }
        if let letter = session.displayLetter { text += (session.canvasLetter == nil || !session.whatIf.isEmpty) ? ", \(letter) estimated" : ", \(letter)" }
        if !session.whatIf.isEmpty { text += ", what-if active" }
        text += ". \(dueLine). Opens grades."
        return text
    }
}
