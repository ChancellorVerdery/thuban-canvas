import SwiftUI
import ThubanCanvasCore

/// Hand-typed past semesters that feed the cumulative GPA (Canvas has no transcript API). Each semester is a
/// collapsed row — name, credits, GPA — that expands to its classes (name, credits, letter) and letter scale.
struct GradesPastSemesters: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var expanded: Set<UUID> = []
    /// Smoke screenshots show the first semester expanded.
    private var expandsFirstForSmoke: Bool { SmokeHarness.isEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if app.settings.pastSemesters.isEmpty {
                SettingsNote(text: "None yet. Add each finished semester from your transcript: its classes, their credit hours and letters.")
            } else {
                ForEach(app.settings.pastSemesters) { semester in
                    let first = expandsFirstForSmoke && semester.id == app.settings.pastSemesters.first?.id
                    GradesPastSemesterRow(semester: semester, isExpanded: expanded.contains(semester.id) || first) {
                        withAnimation(app.settings.reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            if expanded.contains(semester.id) { expanded.remove(semester.id) } else { expanded.insert(semester.id) }
                        }
                    }
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
        let semester = PastSemester(name: name, classes: [PastClass(credits: app.settings.defaultCredits)], scale: app.settings.letterScale)
        app.settings.pastSemesters.append(semester)
        expanded.insert(semester.id)
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

/// One past semester: a summary row (chevron, name, credits, GPA, remove) that expands to the editor.
private struct GradesPastSemesterRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var semester: PastSemester
    var isExpanded: Bool
    var toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            summary
            if isExpanded {
                Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline)
                GradesPastSemesterEditor(semester: semester)
                    .padding(14)
            }
        }
        .thubanPanel(padding: 0)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Glyph(isExpanded ? .chevronDown : .chevronRight, size: 14)
                        .foregroundStyle(theme.inkDimColor)
                        .frame(width: 16)
                    Text(semester.name.isEmpty ? "Untitled semester" : semester.name)
                        .font(ThubanFont.body(14, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                    if semester.usesClasses {
                        Text(semester.classes.count == 1 ? "1 class" : "\(semester.classes.count) classes")
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.inkDimColor)
                    }
                    Spacer(minLength: 8)
                    Text(creditsText)
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                    Text(GPACalculator.format(semester.gpa))
                        .font(ThubanFont.display(15))
                        .foregroundStyle(semester.gpa == nil ? theme.inkDimColor : theme.inkColor)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(semester.name), \(creditsText), GPA \(GPACalculator.format(semester.gpa))")
            .accessibilityHint(isExpanded ? "Collapses the semester" : "Expands the semester to edit its classes")
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            IconButton(glyph: .close, label: "Remove \(semester.name)", size: 28, iconSize: 13) {
                app.settings.pastSemesters.removeAll { $0.id == semester.id }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(hovering && !isExpanded ? theme.panel2Color.opacity(0.6) : .clear)
        .onHover { hovering = $0 }
    }

    private var creditsText: String {
        let credits = semester.credits
        let text = credits == credits.rounded() ? String(Int(credits)) : String(format: "%.1f", credits)
        return credits == 1 ? "1 credit" : "\(text) credits"
    }
}

/// The expanded editor: semester name, letter scale, the class table, and — with no classes — typed totals.
private struct GradesPastSemesterEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var semester: PastSemester

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("Semester")
                    TextField("Fall 2025", text: binding(\.name))
                        .thubanField(height: 30)
                        .frame(maxWidth: 260)
                        .accessibilityLabel("Semester name")
                }
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("Letter scale")
                    SegmentedPicker(selection: binding(\.scale), options: LetterScale.allCases.map { SegmentOption($0, $0.label) }, segmentHeight: 24)
                        .accessibilityLabel("Letter scale for \(semester.name)")
                }
                Spacer(minLength: 0)
            }

            if semester.usesClasses {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        eyebrow("Class").frame(maxWidth: .infinity, alignment: .leading)
                        eyebrow("Credits").frame(width: 72)
                        eyebrow("Grade").frame(width: 96)
                        Color.clear.frame(width: 28)
                    }
                    ForEach(semester.classes) { pastClass in
                        classRow(pastClass)
                    }
                }
                if semester.unlettered > 0 {
                    SettingsNote(text: semester.unlettered == 1 ? "One class has no letter yet and is left out of the GPA." : "\(semester.unlettered) classes have no letter yet and are left out of the GPA.")
                }
            } else {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        eyebrow("Semester GPA")
                        TextField("0.00", value: binding(\.manualGPA, clamp: 0...10), format: .number.precision(.fractionLength(0...3)))
                            .thubanField(invalid: semester.manualGPA > 4.5, mono: true, height: 30)
                            .multilineTextAlignment(.center)
                            .frame(width: 84)
                            .accessibilityLabel("GPA for \(semester.name)")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        eyebrow("Credits")
                        TextField("0", value: binding(\.manualCredits, clamp: 0...1000), format: .number.precision(.fractionLength(0...2)))
                            .thubanField(mono: true, height: 30)
                            .multilineTextAlignment(.center)
                            .frame(width: 84)
                            .accessibilityLabel("Credits for \(semester.name)")
                    }
                    Spacer(minLength: 0)
                }
                SettingsNote(text: "No classes listed — the GPA and credits above are used as typed. Add classes to have them computed instead.")
            }

            Button {
                var classes = semester.classes
                classes.append(PastClass(credits: app.settings.defaultCredits))
                binding(\.classes).wrappedValue = classes
            } label: {
                HStack(spacing: 6) {
                    Glyph(.plus, size: 12)
                    Text("Add class")
                }
            }
            .buttonStyle(GhostButtonStyle(height: 28, tinted: true, horizontalPadding: 8))
            .accessibilityLabel("Add a class to \(semester.name)")
        }
    }

    private func classRow(_ pastClass: PastClass) -> some View {
        HStack(spacing: 10) {
            TextField("Class name", text: classBinding(pastClass.id, \.name))
                .thubanField(height: 30)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Class name")
            TextField("3", value: classBinding(pastClass.id, \.credits, clamp: 0...30), format: .number.precision(.fractionLength(0...2)))
                .thubanField(mono: true, height: 30)
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .accessibilityLabel("Credits for \(pastClass.name.isEmpty ? "class" : pastClass.name)")
            Picker("", selection: classBinding(pastClass.id, \.letter)) {
                Text("—").tag("")
                ForEach(semester.scale.letters, id: \.self) { letter in Text(letter).tag(letter) }
                if !pastClass.letter.isEmpty, !semester.scale.letters.contains(pastClass.letter) {
                    Text(pastClass.letter).tag(pastClass.letter)
                }
            }
            .labelsHidden()
            .frame(width: 96)
            .accessibilityLabel("Letter grade for \(pastClass.name.isEmpty ? "class" : pastClass.name)")
            IconButton(glyph: .close, label: "Remove \(pastClass.name.isEmpty ? "class" : pastClass.name)", size: 28, iconSize: 13) {
                var classes = semester.classes
                classes.removeAll { $0.id == pastClass.id }
                binding(\.classes).wrappedValue = classes
            }
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
    }

    private var current: PastSemester {
        app.settings.pastSemesters.first { $0.id == semester.id } ?? semester
    }

    private func binding<T>(_ keyPath: WritableKeyPath<PastSemester, T>) -> Binding<T> {
        Binding(
            get: { current[keyPath: keyPath] },
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

    private func classBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<PastClass, T>) -> Binding<T> {
        Binding(
            get: { (current.classes.first { $0.id == id } ?? PastClass())[keyPath: keyPath] },
            set: { value in
                guard let index = app.settings.pastSemesters.firstIndex(where: { $0.id == semester.id }),
                      let classIndex = app.settings.pastSemesters[index].classes.firstIndex(where: { $0.id == id }) else { return }
                app.settings.pastSemesters[index].classes[classIndex][keyPath: keyPath] = value
            }
        )
    }

    private func classBinding(_ id: UUID, _ keyPath: WritableKeyPath<PastClass, Double>, clamp range: ClosedRange<Double>) -> Binding<Double> {
        let raw = classBinding(id, keyPath)
        return Binding(
            get: { raw.wrappedValue },
            set: { value in raw.wrappedValue = value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound }
        )
    }
}
