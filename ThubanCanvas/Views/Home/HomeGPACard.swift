import SwiftUI
import ThubanCanvasCore

/// Term and cumulative GPA (estimated from current scores), the courses counted, and a link to the settings.
struct HomeGPACard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var showingHistory = false

    var body: some View {
        let result = app.gpa
        let courses = app.gpaCourses
        HomeCard("GPA") {
            Button("Edit credits & scale") { app.openSettings(pane: SettingsPane.grades.rawValue) }
                .buttonStyle(GhostButtonStyle(height: 24, tinted: true, horizontalPadding: 6))
                .accessibilityLabel("Edit credits and letter scale in Settings")
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    showingHistory = true
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 18) {
                            figure(label: "Term", value: result.term, credits: result.termCredits)
                            figure(label: "Cumulative", value: result.cumulative, credits: result.cumulativeCredits)
                            if result.prior != nil {
                                figure(label: "Before term", value: result.prior, credits: result.priorCredits, detail: changeText(result))
                            }
                            Spacer(minLength: 0)
                        }
                        GPASparkline(points: app.gpaHistory.suffix(30).compactMap(\.term))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show the GPA graph for the semester")
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens a graph of your GPA over the semester")

                if courses.isEmpty {
                    HomeEmptyRow(symbol: "star", text: "Star courses in Canvas to estimate a GPA.", inset: false)
                } else {
                    VStack(spacing: 6) {
                        ForEach(courses) { course in
                            courseLine(course)
                        }
                    }
                }

                SettingsNote(text: note(result))
            }
            .padding(14)
        }
        .sheet(isPresented: $showingHistory) {
            HomeGPAHistorySheet()
                .environment(\.thubanTheme, theme)
        }
    }

    private func figure(label: String, value: Double?, credits: Double, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor).lineLimit(1)
            Text(GPACalculator.format(value))
                .font(ThubanFont.display(30))
                .foregroundStyle(value == nil ? theme.inkFaintColor : theme.inkColor)
                .monospacedDigit()
            Text(detail ?? (credits > 0 ? "\(DueFormatter.points(credits)) credits" : "no credits yet"))
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
        }
        .fixedSize()
    }

    /// "+0.04 this term" — how much this term moves the cumulative GPA.
    private func changeText(_ result: GPAResult) -> String {
        guard let change = result.cumulativeChange else { return "\(DueFormatter.points(result.priorCredits)) credits" }
        if abs(change) < 0.005 { return "no change yet" }
        return (change > 0 ? "+" : "−") + String(format: "%.2f", abs(change)) + " this term"
    }

    private func courseLine(_ course: GPACourse) -> some View {
        HStack(spacing: 8) {
            CourseDot(tint: app.sessions[course.id]?.preferences.tint)
            Text(course.name)
                .font(ThubanFont.small)
                .foregroundStyle(course.included ? theme.inkColor : theme.inkFaintColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(status(course))
                .font(ThubanFont.small)
                .foregroundStyle(course.included && course.points != nil ? theme.inkDimColor : theme.inkFaintColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// "A · 3 cr", "no letter yet", "excluded", "P · not counted".
    private func status(_ course: GPACourse) -> String {
        guard course.included else { return "excluded" }
        guard let letter = course.letter else { return "no letter yet" }
        let credits = "\(DueFormatter.points(course.credits)) cr"
        guard course.points != nil else { return "\(letter) · not counted" }
        return "\(letter) · \(credits)"
    }

    private func note(_ result: GPAResult) -> String {
        var text = "Estimated from current scores, using each course’s grading scheme or your letter scale."
        if !result.skipped.isEmpty {
            text += result.skipped.count == 1 ? " One course has no letter yet." : " \(result.skipped.count) courses have no letter yet."
        }
        if app.settings.pastSemesters.isEmpty {
            text += " Add past semesters in Settings for a cumulative figure."
        }
        return text
    }
}

/// A thin trend line of the last days' term GPA (just the shape; the sheet has the numbers), with "Graph ›".
/// A dashed baseline stands in until two days are recorded.
private struct GPASparkline: View {
    @Environment(\.thubanTheme) private var theme
    var points: [Double]

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                let width = proxy.size.width
                if points.count >= 2, let low = points.min(), let high = points.max() {
                    let span = max(high - low, 0.05)
                    Path { path in
                        for (index, value) in points.enumerated() {
                            let x = width * CGFloat(index) / CGFloat(points.count - 1)
                            let y = 20 - 18 * CGFloat((value - low) / span)
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else {
                    Path { path in path.move(to: CGPoint(x: 0, y: 11)); path.addLine(to: CGPoint(x: width, y: 11)) }
                        .stroke(theme.line2Color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
            .frame(height: 22)
            Text("Graph ›").font(ThubanFont.small).foregroundStyle(theme.brassInkColor).fixedSize()
        }
        .accessibilityHidden(true)
    }
}
