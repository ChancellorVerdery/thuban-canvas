import SwiftUI
import ThubanCanvasCore

/// The eight course tints a course can carry (stored as hex in `CoursePreferences.tint`). This is the one place
/// the values live; views draw them through `Color(hex:)` like `CourseDot` does.
enum GradesTintPalette {
    struct Tint: Identifiable, Equatable {
        var name: String
        var hex: String
        var id: String { hex }
    }

    static let all: [Tint] = [
        Tint(name: "Brass", hex: "#B8860B"),
        Tint(name: "Clay", hex: "#C0623A"),
        Tint(name: "Rose", hex: "#B5495B"),
        Tint(name: "Plum", hex: "#7B4F9D"),
        Tint(name: "Indigo", hex: "#3F5FBF"),
        Tint(name: "Teal", hex: "#2E8B8B"),
        Tint(name: "Moss", hex: "#5F8A3C"),
        Tint(name: "Slate", hex: "#5C6B7A"),
    ]

    static func name(for hex: String?) -> String? {
        guard let hex else { return nil }
        return all.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name
    }
}

/// A row of tint dots plus a "none" slot. Selected dot gets a ring in `ink`.
struct GradesTintPicker: View {
    @Environment(\.thubanTheme) private var theme
    var selection: String?
    var courseName: String
    var select: (String?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            dot(tint: nil, selected: selection == nil)
            ForEach(GradesTintPalette.all) { tint in
                dot(tint: tint, selected: selection?.caseInsensitiveCompare(tint.hex) == .orderedSame)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tint for \(courseName)")
    }

    private func dot(tint: GradesTintPalette.Tint?, selected: Bool) -> some View {
        Button {
            select(tint?.hex)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(selected ? theme.inkColor : .clear, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                if let tint {
                    Circle().fill(Color(hex: tint.hex)).frame(width: 14, height: 14)
                } else {
                    Circle()
                        .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline)
                        .background(Circle().fill(theme.panelColor))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Rectangle().fill(theme.line2Color).frame(width: 10, height: 1).rotationEffect(.degrees(-45))
                        )
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tint?.name ?? "No tint")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(tint?.name ?? "None (use the accent)")
    }
}

/// A number field with − / + buttons, for credits and the like. `nil` shows the placeholder.
struct GradesNumberField: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    @Binding var value: Double?
    var placeholder: String
    var step: Double = 1
    var range: ClosedRange<Double> = 0...30
    var width: CGFloat = 64

    var body: some View {
        HStack(spacing: 4) {
            stepButton(symbol: "minus", label: "Decrease \(label)") { adjust(-step) }
            TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0...2)))
                .thubanField(height: 30)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .accessibilityLabel(label)
            stepButton(symbol: "plus", label: "Increase \(label)") { adjust(step) }
        }
    }

    private func stepButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
        }
        .buttonStyle(GhostButtonStyle(height: 28, horizontalPadding: 7))
        .accessibilityLabel(label)
    }

    private func adjust(_ delta: Double) {
        let base = value ?? (Double(placeholder) ?? range.lowerBound)
        value = min(range.upperBound, max(range.lowerBound, base + delta))
    }
}
