import SwiftUI
import ThubanCanvasCore

/// Past semesters typed in by hand (Canvas has no transcript API), feeding the cumulative GPA. Stored on this
/// device only.
struct PastSemestersScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var back: String
    @State private var editing: PastSemester?

    var body: some View {
        PushedScreen("Past semesters", back: back) {
            BarTextButton("Add") { editing = PastSemester(name: suggestedName) }
                .accessibilityLabel("Add a past semester")
        } content: {
            VStack(alignment: .leading, spacing: IOSMetrics.sectionGap) {
                summary
                if app.settings.pastSemesters.isEmpty {
                    Card { EmptyNote(systemName: "graduationcap", text: "Add each finished semester’s GPA and credits for a cumulative GPA.") }
                } else {
                    Card {
                        ForEach(Array(app.settings.pastSemesters.enumerated()), id: \.element.id) { index, semester in
                            if index > 0 { RowDivider() }
                            Button { editing = semester } label: { row(semester) }
                                .buttonStyle(RowPressStyle())
                                .contextMenu {
                                    Button(role: .destructive) { app.settings.pastSemesters.removeAll { $0.id == semester.id } } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    Text("Tap a semester to edit it; long-press to delete. Stays on this device.")
                        .tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .gutter()
        }
        .sheet(item: $editing) { semester in
            SemesterEditor(semester: semester, isNew: !app.settings.pastSemesters.contains { $0.id == semester.id }) { saved in
                if let index = app.settings.pastSemesters.firstIndex(where: { $0.id == saved.id }) {
                    app.settings.pastSemesters[index] = saved
                } else {
                    app.settings.pastSemesters.append(saved)
                }
            }
            .environment(\.thubanTheme, theme)
            .presentationDetents([.medium])
            .presentationBackground(theme.bgColor)
        }
    }

    private var suggestedName: String {
        "Semester \(app.settings.pastSemesters.count + 1)"
    }

    private var summary: some View {
        let past = GPACalculator.compute(courses: [], past: app.settings.pastSemesters)
        return Card {
            HStack(spacing: 0) {
                figure("Past GPA", GPACalculator.format(past.cumulative), "\(PointsText.short(past.cumulativeCredits)) credits")
                Rectangle().fill(theme.lineColor).frame(width: 1).padding(.vertical, 12)
                figure("With this term", GPACalculator.format(app.gpa.cumulative), "\(PointsText.short(app.gpa.cumulativeCredits)) credits")
            }
        }
    }

    private func figure(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.inkDimColor)
            Text(value).tFont(.display(28)).foregroundStyle(theme.inkColor)
            Text(detail).tFont(.footnote).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ semester: PastSemester) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(semester.name.isEmpty ? "Untitled" : semester.name).tFont(.bodyStrong).foregroundStyle(theme.inkColor)
                Text("\(PointsText.short(semester.credits)) credits" + (semester.usesClasses ? " · \(semester.classes.count) classes" : ""))
                    .tFont(.footnote).foregroundStyle(theme.inkDimColor)
            }
            Spacer()
            Text(GPACalculator.format(semester.gpa)).tFont(.display(20)).foregroundStyle(theme.inkColor)
            RowChevron()
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct SemesterEditor: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var semester: PastSemester
    /// A fresh semester starts with empty fields; an existing one shows its stored values, even a 0-credit one,
    /// so re-saving it never zeroes a GPA the user entered.
    var isNew: Bool
    var save: (PastSemester) -> Void
    @State private var gpaText = ""
    @State private var creditsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BarTextButton("Cancel", weight: .regular) { dismiss() }
                Spacer()
                Text("Semester").tFont(.bodyStrong).foregroundStyle(theme.inkColor)
                Spacer()
                BarTextButton("Save") {
                    var edited = semester
                    if !edited.usesClasses {
                        edited.manualGPA = min(4.0, max(0, Double(gpaText.replacingOccurrences(of: ",", with: ".")) ?? 0))
                        edited.manualCredits = max(0, Double(creditsText.replacingOccurrences(of: ",", with: ".")) ?? 0)
                    }
                    save(edited)
                    dismiss()
                }
            }
            .padding(.top, 8)
            Card {
                field("Name", text: $semester.name, keyboard: .default)
                if semester.usesClasses {
                    RowDivider()
                    Text("GPA \(GPACalculator.format(semester.gpa)) from \(semester.classes.count) classes (edit classes on the Mac).")
                        .tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(16)
                } else {
                    RowDivider()
                    field("GPA", text: $gpaText, keyboard: .decimalPad)
                    RowDivider()
                    field("Credits", text: $creditsText, keyboard: .decimalPad)
                }
            }
            Spacer()
        }
        .gutter()
        .background(theme.bgColor.ignoresSafeArea())
        .onAppear {
            guard !isNew else { return }
            gpaText = String(format: "%.2f", semester.manualGPA)
            creditsText = PointsText.short(semester.manualCredits)
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label).tFont(.body).foregroundStyle(theme.inkColor).frame(width: 80, alignment: .leading)
            TextField("", text: text, prompt: Text(label == "Name" ? "Fall 2025" : "0").foregroundStyle(theme.inkFaintColor))
                .tFont(.body).foregroundStyle(theme.inkColor)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: IOSMetrics.rowHeight)
    }
}
