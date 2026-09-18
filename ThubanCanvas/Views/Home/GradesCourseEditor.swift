import SwiftUI
import ThubanCanvasCore

/// One starred course's preferences: nickname, credits, tint, custom cutoffs and whether it counts toward the GPA.
struct GradesCourseEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession

    var body: some View {
        let preferences = session.preferences
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CourseDot(tint: preferences.tint, size: 9)
                Text(session.course.name)
                    .font(ThubanFont.body(14, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !session.shortCode.isEmpty, session.shortCode != session.course.courseCode {
                    Text(session.shortCode).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                }
                Spacer(minLength: 8)
                if let score = session.displayScore {
                    Text(DueFormatter.percent(score)).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).monospacedDigit()
                }
                if let letter = session.displayLetter { Chip.letter(letter) }
            }

            HStack(alignment: .top, spacing: 14) {
                field("Nickname") {
                    TextField(session.tabTitle, text: nickname)
                        .thubanField(height: 30)
                        .accessibilityLabel("Nickname for \(session.course.name)")
                }
                .frame(maxWidth: .infinity)
                field("Credits") {
                    GradesNumberField(label: "credits for \(session.course.name)", value: credits,
                                      placeholder: DueFormatter.points(app.settings.defaultCredits), step: 1, range: 0...12)
                }
                field("Counts toward GPA") {
                    ThubanToggle(isOn: included, label: "Count \(session.course.name) toward GPA")
                        .frame(height: 30)
                }
            }

            field("Tint") {
                GradesTintPicker(selection: preferences.tint, courseName: session.course.name) { hex in
                    app.updatePreferences(for: session.id) { $0.tint = hex }
                }
            }

            field("Custom cutoffs") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("A 90, B 80, C 70, D 60", text: cutoffs)
                        .thubanField(invalid: cutoffsInvalid, mono: true, height: 30)
                        .accessibilityLabel("Custom letter cutoffs for \(session.course.name)")
                    SettingsNote(text: cutoffsNote, tone: cutoffsInvalid ? .negative : .neutral)
                }
            }
        }
        .padding(14)
        .thubanPanel(padding: 0)
        .task(id: session.id) { await session.loadGradingStandards() }
    }

    private func field<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(ThubanFont.micro)
                .kerning(0.5)
                .foregroundStyle(theme.inkDimColor)
            control()
        }
    }

    // MARK: Bindings

    private var nickname: Binding<String> {
        Binding(
            get: { session.preferences.nickname ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                app.updatePreferences(for: session.id) { $0.nickname = trimmed.isEmpty ? nil : text }
            }
        )
    }

    private var credits: Binding<Double?> {
        Binding(
            get: { session.preferences.credits },
            set: { value in app.updatePreferences(for: session.id) { $0.credits = value } }
        )
    }

    private var included: Binding<Bool> {
        Binding(
            get: { !session.preferences.excludeFromGPA },
            set: { value in app.updatePreferences(for: session.id) { $0.excludeFromGPA = !value } }
        )
    }

    private var cutoffs: Binding<String> {
        Binding(
            get: { session.preferences.customCutoffs ?? "" },
            set: { text in app.updatePreferences(for: session.id) { $0.customCutoffs = text.isEmpty ? nil : text } }
        )
    }

    // MARK: Cutoffs feedback

    private var cutoffsInvalid: Bool {
        guard let text = session.preferences.customCutoffs, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return GradingScheme(parsing: text) == nil
    }

    private var cutoffsNote: String {
        if let text = session.preferences.customCutoffs, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let scheme = GradingScheme(parsing: text) else {
                return "Couldn’t read that. Use letter–percent pairs like “A 90, B 80, C 70”."
            }
            let letter = session.displayScore.map { " · currently \(scheme.letter(for: $0))" } ?? ""
            return "Using \(scheme.summary)\(letter)."
        }
        if let letter = session.canvasLetter {
            let scheme = session.hasCourseScheme ? " (\(session.gradingScheme.summary))" : ""
            return "Canvas reports the letter \(letter)\(scheme). Cutoffs typed here override it."
        }
        if session.hasCourseScheme {
            return "Using the course’s own scheme: \(session.gradingScheme.summary)."
        }
        return "Canvas gives no letter for this course — using your letter scale (\(session.gradingScheme.summary))."
    }
}
