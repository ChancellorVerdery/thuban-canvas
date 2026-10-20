import Charts
import SwiftUI
import ThubanCanvasCore

/// The GPA over the semester: one point per day from `AppModel.gpaHistory`, term and cumulative lines, plus a
/// per-course score view. Opened from the Home GPA card.
struct HomeGPAHistorySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .gpa

    enum Mode: Hashable { case gpa, scores }

    /// This term's snapshots (all of them when the term is unknown).
    private var points: [GPASnapshot] {
        let term = HomeSummary.termName(for: app.orderedSessions)
        let all = app.gpaHistory
        guard let term else { return all }
        let matching = all.filter { $0.termName == term }
        return matching.isEmpty ? all : matching
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GPA over the semester")
                        .font(ThubanFont.display(22))
                        .foregroundStyle(theme.inkColor)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                }
                Spacer()
                SegmentedPicker(selection: $mode, options: [SegmentOption(.gpa, "GPA"), SegmentOption(.scores, "Course scores")],
                                segmentHeight: SegmentedPickerHeight.toolbar)
                    .accessibilityLabel("Graph")
            }

            if points.isEmpty {
                EmptyState(title: "Tracking starts today",
                           message: "Thuban Canvas saves one GPA point per day after it refreshes from Canvas. Check back tomorrow for a line.")
                    .frame(height: 300)
            } else {
                Group {
                    switch mode {
                    case .gpa: gpaChart
                    case .scores: scoresChart
                    }
                }
                .frame(height: 320)
                legend(legendItems)
                summary
            }

            HStack {
                Text("What-if scores never count. One point per day — the day’s last refresh wins.")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.thubanSecondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 760)
        .background(theme.panelColor)
    }

    private var subtitle: String {
        let term = HomeSummary.termName(for: app.orderedSessions) ?? "This term"
        let count = points.count
        return "\(term) · \(count == 1 ? "1 day" : "\(count) days") recorded"
    }

    // MARK: GPA

    private var gpaChart: some View {
        Chart {
            if let prior = app.gpa.prior {
                RuleMark(y: .value("Before this term", prior))
                    .foregroundStyle(theme.inkDimColor)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Before this term · \(GPACalculator.format(prior))")
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.inkDimColor)
                    }
            }
            ForEach(points) { point in
                if let term = point.term {
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("GPA", term), series: .value("Series", "Term"))
                        .foregroundStyle(theme.accentColor)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value("GPA", term))
                        .foregroundStyle(theme.accentColor)
                        .symbolSize(points.count > 40 ? 12 : 30)
                }
                if let cumulative = point.cumulative, cumulative != point.term {
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("GPA", cumulative), series: .value("Series", "Cumulative"))
                        .foregroundStyle(theme.signalColor)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                }
            }
        }
        .chartYScale(domain: gpaDomain)
        .chartXScale(domain: xDomain)
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
            AxisGridLine().foregroundStyle(theme.lineColor)
            AxisValueLabel().foregroundStyle(theme.inkDimColor)
        } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in
            AxisGridLine().foregroundStyle(theme.lineColor)
            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(theme.inkDimColor)
        } }
        .chartLegend(.hidden)
        .chartPlotStyle { $0.padding(.trailing, 18) }
        .accessibilityLabel(gpaAccessibility)
    }

    private var gpaDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.term, $0.cumulative].compactMap { $0 } } + [app.gpa.prior].compactMap { $0 }
        guard let low = values.min(), let high = values.max() else { return 0...4 }
        let lower = max(0, (low - 0.3).rounded(.down))
        let upper = min(4.0, max(high + 0.2, lower + 1))
        return lower...max(upper, lower + 0.5)
    }

    // MARK: Course scores

    private var courseIds: [CanvasID] {
        let starred = app.orderedSessions.map(\.id)
        let seen = Set(points.flatMap { $0.scores.keys })
        return starred.filter { seen.contains($0) } + seen.subtracting(starred).sorted()
    }

    private func courseName(_ id: CanvasID) -> String {
        app.sessions[id]?.tabTitle ?? points.last(where: { $0.names[id] != nil })?.names[id] ?? "Course"
    }

    private func courseColor(_ id: CanvasID, index: Int) -> Color {
        if let tint = app.sessions[id]?.preferences.tint { return Color(hex: tint) }
        let palette = [theme.accentColor, theme.signalColor, theme.posColor, theme.negColor, theme.accentDeepColor, theme.inkDimColor]
        return palette[index % palette.count]
    }

    private var scoresChart: some View {
        let ids = courseIds
        return Chart {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                ForEach(points) { point in
                    if let score = point.scores[id] {
                        LineMark(x: .value("Day", point.date, unit: .day), y: .value("Score", score), series: .value("Course", courseName(id)))
                            .foregroundStyle(courseColor(id, index: index))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
            }
        }
        .chartYScale(domain: scoreDomain)
        .chartXScale(domain: xDomain)
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
            AxisGridLine().foregroundStyle(theme.lineColor)
            AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))%") } }.foregroundStyle(theme.inkDimColor)
        } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in
            AxisGridLine().foregroundStyle(theme.lineColor)
            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(theme.inkDimColor)
        } }
        .chartLegend(.hidden)
        .chartPlotStyle { $0.padding(.trailing, 18) }
    }

    /// Legend for the current graph, laid out under the plot so it never covers a line.
    private var legendItems: [(String, Color, Bool)] {
        switch mode {
        case .gpa: return [("Term", theme.accentColor, false), ("Cumulative (incl. past semesters)", theme.signalColor, true)]
        case .scores: return courseIds.enumerated().map { (courseName($0.element), courseColor($0.element, index: $0.offset), false) }
        }
    }

    private var scoreDomain: ClosedRange<Double> {
        let values = points.flatMap { $0.scores.values }
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        return max(0, (low - 5).rounded(.down))...max(100, (high + 2).rounded(.up))
    }

    // MARK: Shared

    /// The term's dates when known (so early-semester points sit at the left), else the recorded span.
    private var xDomain: ClosedRange<Date> {
        let first = points.first?.date ?? Date()
        let last = points.last?.date ?? Date()
        if let term = app.termInterval, term.contains(first) || term.contains(last) {
            return min(term.start, first)...max(term.end, last)
        }
        let start = Calendar.current.date(byAdding: .day, value: -3, to: first) ?? first
        let end = Calendar.current.date(byAdding: .day, value: 3, to: last) ?? last
        return start...end
    }

    private func legend(_ items: [(String, Color, Bool)]) -> some View {
        HStack(spacing: 18) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 6) {
                    Capsule().fill(item.1).frame(width: 18, height: 3).opacity(item.2 ? 0.85 : 1)
                    Text(item.0).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private var summary: some View {
        let first = points.first(where: { $0.term != nil })
        let last = points.last(where: { $0.term != nil })
        return HStack(spacing: 28) {
            stat("Now", GPACalculator.format(last?.term))
            stat("Started", GPACalculator.format(first?.term))
            stat("Change", change(first?.term, last?.term))
            stat("High", GPACalculator.format(points.compactMap(\.term).max()))
            stat("Low", GPACalculator.format(points.compactMap(\.term).min()))
            Spacer()
        }
    }

    private func change(_ from: Double?, _ to: Double?) -> String {
        guard let from, let to else { return "—" }
        let delta = to - from
        if abs(delta) < 0.005 { return "±0.00" }
        return (delta > 0 ? "+" : "−") + String(format: "%.2f", abs(delta))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
            Text(value).font(ThubanFont.display(20)).foregroundStyle(theme.inkColor).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var gpaAccessibility: String {
        let values = points.compactMap { point in point.term.map { "\(point.day): \(GPACalculator.format($0))" } }
        return "Term GPA by day. " + values.suffix(10).joined(separator: ", ")
    }
}
