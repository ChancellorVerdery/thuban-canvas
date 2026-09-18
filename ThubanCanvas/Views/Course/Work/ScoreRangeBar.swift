import SwiftUI
import ThubanCanvasCore

/// Class score statistics as one horizontal bar on a 0…possible axis: the min–max range as a thin track, the
/// lower–upper quartile band as a thicker accent-tinted block, a tick at the mean, and a filled marker at the
/// student's own score. Labels underneath give the numbers; VoiceOver reads them as one sentence.
struct ScoreRangeBar: View {
    @Environment(\.thubanTheme) private var theme
    var statistics: ScoreStatistics
    var possible: Double?
    var score: Double?

    private var axisMax: Double {
        let candidates = [possible, statistics.max, score].compactMap { $0 }
        return max(candidates.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let x = position(in: geometry.size.width)
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.panel2Color).frame(height: 6)
                    if let low = statistics.min, let high = statistics.max, high >= low {
                        Capsule().fill(theme.line2Color)
                            .frame(width: max(2, x(high) - x(low)), height: 6)
                            .offset(x: x(low))
                    }
                    if let lower = statistics.lowerQ, let upper = statistics.upperQ, upper >= lower {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(theme.accentTintColor)
                            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(theme.accentColor.opacity(0.5), lineWidth: 1))
                            .frame(width: max(4, x(upper) - x(lower)), height: 14)
                            .offset(x: x(lower))
                    }
                    if let mean = statistics.mean {
                        Rectangle().fill(theme.inkDimColor).frame(width: 2, height: 20).offset(x: x(mean) - 1)
                    }
                    if let score {
                        Circle()
                            .fill(theme.accentColor)
                            .overlay(Circle().strokeBorder(theme.panelColor, lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .offset(x: x(score) - 7)
                    }
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            HStack(spacing: 0) {
                legend("Low", statistics.min)
                Spacer()
                legend("Mean", statistics.mean)
                Spacer()
                legend("Median", statistics.median)
                Spacer()
                legend("High", statistics.max)
            }
            HStack(spacing: 12) {
                key(theme.accentTintColor, "Middle half", square: true)
                key(theme.inkDimColor, "Mean", square: false)
                if score != nil { key(theme.accentColor, "You", square: false, round: true) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Class scores")
        .accessibilityValue(accessibilityValue)
    }

    /// Maps a score onto the bar's width.
    private func position(in width: CGFloat) -> (Double) -> CGFloat {
        let axis = axisMax
        return { value in CGFloat(min(max(value / axis, 0), 1)) * width }
    }

    /// One decimal at most ("80.7", "92").
    static func number(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func legend(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
            Text(Self.number(value)).font(ThubanFont.mono(12)).foregroundStyle(theme.inkDimColor)
        }
    }

    private func key(_ color: Color, _ label: String, square: Bool, round: Bool = false) -> some View {
        HStack(spacing: 5) {
            Group {
                if round { Circle().fill(color).frame(width: 8, height: 8) }
                else if square { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8) }
                else { Rectangle().fill(color).frame(width: 2, height: 10) }
            }
            Text(label).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let low = statistics.min, let high = statistics.max { parts.append("range \(Self.number(low)) to \(Self.number(high))") }
        if let mean = statistics.mean { parts.append("mean \(Self.number(mean))") }
        if let median = statistics.median { parts.append("median \(Self.number(median))") }
        if let lower = statistics.lowerQ, let upper = statistics.upperQ { parts.append("middle half \(Self.number(lower)) to \(Self.number(upper))") }
        if let score { parts.append("your score \(DueFormatter.points(score))") }
        if let possible { parts.append("out of \(DueFormatter.points(possible))") }
        return parts.joined(separator: ", ")
    }
}
