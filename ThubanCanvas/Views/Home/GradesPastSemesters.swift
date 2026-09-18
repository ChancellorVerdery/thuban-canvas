import SwiftUI
import ThubanCanvasCore

/// Hand-typed past semesters (name, GPA, credits) that feed the cumulative GPA. Canvas has no transcript API.
struct GradesPastSemesters: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if app.settings.pastSemesters.isEmpty {
                SettingsNote(text: "None yet. Add each finished semester's GPA and credit hours from your transcript.")
            } else {
                HStack(spacing: 10) {
                    header("Semester").frame(maxWidth: .infinity, alignment: .leading)
                    header("GPA").frame(width: 84)
                    header("Credits").frame(width: 84)
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 14)
                ForEach(app.settings.pastSemesters) { semester in
                    GradesPastSemesterRow(semester: semester)
                }
            }
            Button {
                add()
            } label: {
                HStack(spacing: 6) {
                    Glyph(.plus, size: 13)
                    Text("Add semester")
                }
            }
            .buttonStyle(.thubanSecondary)
            .accessibilityLabel("Add a past semester")
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
    }

    /// Suggests the previous term's name ("Spring 2026" before "Fall 2026") for the new row.
    private func add() {
        let taken = Set(app.settings.pastSemesters.map(\.name))
        var name = "Past semester"
        if let current = HomeSummary.termName(for: app.orderedSessions), let previous = Self.previousTerm(before: current) {
            name = previous
            var candidate = previous
            var step = 1
            while taken.contains(candidate), let earlier = Self.previousTerm(before: candidate), step < 12 {
                candidate = earlier
                step += 1
            }
            if !taken.contains(candidate) { name = candidate }
        }
        app.settings.pastSemesters.append(PastSemester(name: name, gpa: 0, credits: 0))
    }

    /// "Fall 2026" → "Spring 2026"; "Spring 2026" → "Fall 2025". Nil for anything else.
    static func previousTerm(before name: String) -> String? {
        let parts = name.split(separator: " ")
        guard parts.count == 2, let year = Int(parts[1]) else { return nil }
        switch parts[0].lowercased() {
        case "fall": return "Spring \(year)"
        case "spring": return "Fall \(year - 1)"
        case "summer": return "Spring \(year)"
        default: return nil
        }
    }
}

/// One editable past-semester row.
private struct GradesPastSemesterRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var semester: PastSemester

    var body: some View {
        HStack(spacing: 10) {
            TextField("Semester", text: binding(\.name))
                .thubanField(height: 30)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Semester name")
            TextField("0.00", value: binding(\.gpa, clamp: 0...10), format: .number.precision(.fractionLength(0...3)))
                .thubanField(invalid: semester.gpa < 0 || semester.gpa > 4.5, mono: true, height: 30)
                .multilineTextAlignment(.center)
                .frame(width: 84)
                .accessibilityLabel("GPA for \(semester.name)")
            TextField("0", value: binding(\.credits, clamp: 0...1000), format: .number.precision(.fractionLength(0...2)))
                .thubanField(invalid: semester.credits < 0, mono: true, height: 30)
                .multilineTextAlignment(.center)
                .frame(width: 84)
                .accessibilityLabel("Credits for \(semester.name)")
            IconButton(glyph: .close, label: "Remove \(semester.name)", size: 28, iconSize: 13) {
                app.settings.pastSemesters.removeAll { $0.id == semester.id }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .thubanPanel(padding: 0)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<PastSemester, T>) -> Binding<T> {
        Binding(
            get: { (app.settings.pastSemesters.first { $0.id == semester.id } ?? semester)[keyPath: keyPath] },
            set: { value in
                guard let index = app.settings.pastSemesters.firstIndex(where: { $0.id == semester.id }) else { return }
                app.settings.pastSemesters[index][keyPath: keyPath] = value
            }
        )
    }

    /// Numeric fields are clamped so unbounded typed values never reach the formatters.
    private func binding(_ keyPath: WritableKeyPath<PastSemester, Double>, clamp range: ClosedRange<Double>) -> Binding<Double> {
        let raw = binding(keyPath)
        return Binding(
            get: { raw.wrappedValue },
            set: { value in raw.wrappedValue = value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound }
        )
    }
}
