import SwiftUI
import ThubanCanvasCore

/// Grades & GPA pane: live GPA figures, the letter scale, default credits, per-course preferences and past semesters.
struct GradesSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let result = app.gpa
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Right now", caption: "Estimated from current scores, using each course’s grading scheme or the letter scale below. Changes here apply immediately.") {
                HStack(alignment: .top, spacing: 32) {
                    figure("Term GPA", value: result.term, credits: result.termCredits)
                    figure("Cumulative", value: result.cumulative, credits: result.cumulativeCredits)
                    Spacer(minLength: 0)
                    if !result.skipped.isEmpty {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Not counted yet".uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
                            ForEach(result.skipped, id: \.self) { name in
                                Text(name).font(ThubanFont.small).foregroundStyle(theme.inkFaintColor).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: 240, alignment: .trailing)
                    }
                }
                .padding(16)
                .thubanPanel(padding: 0)
                .accessibilityElement(children: .combine)
            }

            SettingsGroup("Letter scale", caption: "Used for courses whose instructor set no grading scheme in Canvas (and for what-if letters).") {
                SegmentedPicker(
                    selection: Binding(get: { app.settings.letterScale }, set: { app.settings.letterScale = $0 }),
                    options: LetterScale.allCases.map { SegmentOption($0, $0.label) }
                )
                SettingsNote(text: app.settings.letterScale.scheme.summary)
            }

            SettingsGroup("Credits") {
                SettingsRow("Default credit hours", detail: "Applied to any course without its own credits below.") {
                    GradesNumberField(label: "default credit hours", value: defaultCredits, placeholder: "3", step: 1, range: 0...12)
                }
            }

            SettingsGroup("Courses", caption: "Nickname (shown on the tab), credit hours, tint, custom letter cutoffs, and whether the course counts toward the GPA.") {
                if app.orderedSessions.isEmpty {
                    SettingsNote(text: app.client == nil ? "Connect to Canvas to see your starred courses." : "No starred courses yet.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(app.orderedSessions) { session in
                            GradesCourseEditor(session: session)
                        }
                    }
                }
            }

            SettingsGroup("Past semesters", caption: "Canvas has no transcript, so type each finished semester’s GPA and credits to get a cumulative figure.") {
                GradesPastSemesters()
            }
        }
    }

    private func figure(_ label: String, value: Double?, credits: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
            Text(GPACalculator.format(value))
                .font(ThubanFont.display(30))
                .foregroundStyle(value == nil ? theme.inkFaintColor : theme.inkColor)
                .monospacedDigit()
            Text(credits > 0 ? "\(DueFormatter.points(credits)) credits" : "no credits counted")
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
        }
    }

    private var defaultCredits: Binding<Double?> {
        Binding(
            get: { app.settings.defaultCredits },
            set: { app.settings.defaultCredits = max(0, $0 ?? 3) }
        )
    }
}
