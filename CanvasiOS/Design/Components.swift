import SwiftUI
import ThubanCanvasCore

// The iOS component vocabulary: inset cards (radius 12), eyebrows, chips, 44 pt icon buttons, 50 pt primary
// buttons, filter chips, a segmented control and a switch, all drawn from theme tokens (never stock iOS blue).

/// An inset card: panel fill, 1 px hairline, radius 12, clipped.
struct Card<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var border: Color?
    var fill: Color?
    @ViewBuilder var content: Content

    init(border: Color? = nil, fill: Color? = nil, @ViewBuilder content: () -> Content) {
        self.border = border
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? theme.panelColor)
            .clipShape(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous)
                .strokeBorder(border ?? theme.lineColor, lineWidth: 1))
    }
}

/// A 1 px separator inside a card, inset from the leading edge.
struct RowDivider: View {
    @Environment(\.thubanTheme) private var theme
    var inset: CGFloat = 16

    var body: some View {
        Rectangle().fill(theme.lineColor).frame(height: 1).padding(.leading, inset)
    }
}

/// 12 pt uppercase eyebrow.
struct Eyebrow: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).tFont(.micro).foregroundStyle(color ?? theme.inkDimColor)
    }
}

/// Eyebrow on the left, optional trailing link or note.
struct SectionHeading<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 8)
    }
}

/// A brass text link used as a section trailing action ("All courses", "Calendar").
struct LinkButton: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var size: CGFloat = 15
    var action: () -> Void

    init(_ title: String, size: CGFloat = 15, action: @escaping () -> Void) {
        self.title = title
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).tFont(.text(size, .semibold)).foregroundStyle(theme.brassInkColor)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Soft chip (radius 6, 12.5 pt semibold).
struct ChipView: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanFontScale) private var scale
    var text: String
    var kind: ChipKind
    var mono = false

    init(_ text: String, kind: ChipKind = .neutral, mono: Bool = false) {
        self.text = text
        self.kind = kind
        self.mono = mono
    }

    var body: some View {
        let colors = kind.colors(theme)
        Text(text)
            .font(.system(size: 12.5 * min(scale, 1.5), weight: .semibold, design: mono ? .monospaced : .default))
            .foregroundStyle(colors.text)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: IOSMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IOSMetrics.chipRadius, style: .continuous)
                .strokeBorder(colors.border ?? .clear, lineWidth: 1))
    }
}

enum LetterTone {
    /// A → gain, B → brass, C → neutral, D/F → loss.
    static func kind(for letter: String) -> ChipKind {
        switch letter.trimmingCharacters(in: .whitespaces).uppercased().first {
        case "A": return .pos
        case "B": return .warn
        case "C": return .neutral
        case "D", "F": return .neg
        default: return .neutral
        }
    }
}

struct LetterChip: View {
    var letter: String
    var body: some View {
        ChipView(letter, kind: LetterTone.kind(for: letter))
            .accessibilityLabel("Letter \(letter)")
    }
}

/// 44 × 44 icon button (brass on light, accent on dark) with a VoiceOver label.
struct IconButton: View {
    @Environment(\.thubanTheme) private var theme
    var systemName: String
    var label: String
    var size: CGFloat = 20
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(theme.brassInkColor)
                .frame(width: IOSMetrics.hitTarget, height: IOSMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A brass text button with a 44 pt tall hit area ("Today", "Done", "Reset what-if").
struct BarTextButton: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var weight: Font.Weight = .semibold
    var action: () -> Void

    init(_ title: String, weight: Font.Weight = .semibold, action: @escaping () -> Void) {
        self.title = title
        self.weight = weight
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).tFont(.text(17, weight)).foregroundStyle(theme.brassInkColor)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: IOSMetrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-width 50 pt primary button: accent fill, on-accent ink, radius 12.
struct PrimaryButton: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    var title: String
    var systemImage: String?
    var busy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(theme.onAccentColor)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title).tFont(.bodyStrong)
            }
            .foregroundStyle(theme.onAccentColor)
            .frame(maxWidth: .infinity, minHeight: IOSMetrics.primaryHeight)
            .background(theme.accentColor.opacity(enabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
    }
}

/// Secondary: panel fill, line-2 hairline.
struct SecondaryButton: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var systemImage: String?
    var tint: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
                Text(title).tFont(.text(16, .semibold))
            }
            .foregroundStyle(tint ?? theme.inkColor)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: IOSMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IOSMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
    }
}

struct PressFadeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Row press feedback: a panel-2 wash while pressed.
struct RowPressStyle: ButtonStyle {
    @Environment(\.thubanTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.panel2Color : Color.clear)
    }
}

/// Search field: 40 pt, radius 10, inset fill.
struct SearchBar: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(theme.inkFaintColor)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.inkFaintColor))
                .tFont(.body)
                .foregroundStyle(theme.inkColor)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.inkFaintColor)
                        .frame(width: 32, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(theme.lineColor, in: RoundedRectangle(cornerRadius: IOSMetrics.controlRadius, style: .continuous))
    }
}

/// Horizontal filter chips (course filter, mailbox scope): 32 pt, radius 8.
struct FilterChips<Value: Hashable>: View {
    @Environment(\.thubanTheme) private var theme
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    var accessibilityLabel: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    let on = option.value == selection
                    Button { selection = option.value } label: {
                        Text(option.label)
                            .tFont(.text(14, .semibold))
                            .foregroundStyle(on ? theme.brassInkColor : theme.inkDimColor)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(on ? theme.accentTintColor : theme.panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? theme.accentColor : theme.line2Color, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, IOSMetrics.gutter)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Segmented control: inset track, selected segment = panel + line-2 hairline.
struct Segmented<Value: Hashable>: View {
    @Environment(\.thubanTheme) private var theme
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    var stretch = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .tFont(.text(14, .semibold))
                        .foregroundStyle(on ? theme.inkColor : theme.inkDimColor)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: stretch ? .infinity : nil, minHeight: 30)
                        .background(on ? theme.panelColor : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(on ? theme.line2Color : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(theme.lineColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .frame(minHeight: IOSMetrics.hitTarget)
    }
}

/// The house switch: 51 × 31, accent when on.
struct ThubanSwitch: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.accentColor : theme.line2Color)
                Circle().fill(theme.isDark ? theme.inkColor : theme.panelColor)
                    .overlay(Circle().strokeBorder(theme.line2Color, lineWidth: 1))
                    .frame(width: 27, height: 27)
                    .padding(2)
            }
            .frame(width: 51, height: 31)
            .frame(minHeight: IOSMetrics.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

struct CourseDot: View {
    var color: Color
    var size: CGFloat = 8
    var body: some View { Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true) }
}

/// Chevron for tappable rows.
struct RowChevron: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
            .accessibilityHidden(true)
    }
}

/// Icon + sentence inside a card.
struct EmptyNote: View {
    @Environment(\.thubanTheme) private var theme
    var systemName: String
    var text: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName).font(.system(size: 17, weight: .medium)).foregroundStyle(tint ?? theme.brassInkColor)
            Text(text).tFont(.secondary).foregroundStyle(theme.inkDimColor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }
}

/// Centered placeholder for a whole screen (loading / error / empty).
struct ScreenMessage: View {
    @Environment(\.thubanTheme) private var theme
    var systemName: String
    var title: String
    var message: String?
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName).font(.system(size: 26, weight: .regular)).foregroundStyle(theme.brassInkColor)
            Text(title).tFont(.display(20)).foregroundStyle(theme.inkColor).multilineTextAlignment(.center)
            if let message { Text(message).tFont(.secondary).foregroundStyle(theme.inkDimColor).multilineTextAlignment(.center) }
            if let retry {
                Button("Try again", action: retry).tFont(.text(16, .semibold)).foregroundStyle(theme.brassInkColor).frame(minHeight: 44)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingCard: View {
    @Environment(\.thubanTheme) private var theme
    var text = "Loading…"
    var body: some View {
        Card {
            HStack(spacing: 10) {
                ProgressView().tint(theme.brassInkColor)
                Text(text).tFont(.secondary).foregroundStyle(theme.inkDimColor)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
    }
}

/// Initials in a tinted circle.
struct InitialsAvatar: View {
    @Environment(\.thubanTheme) private var theme
    var name: String
    var index: Int
    var size: CGFloat = 40

    var body: some View {
        let tints: [(Color, Color)] = [(theme.warnSoftColor, theme.brassInkColor), (theme.signalSoftColor, theme.signalTextColor),
                                       (theme.posSoftColor, theme.posTextColor), (theme.panel2Color, theme.inkDimColor)]
        let tint = tints[abs(index) % tints.count]
        Text(Self.initials(name))
            .font(.system(size: size * 0.35, weight: .bold))
            .foregroundStyle(tint.1)
            .frame(width: size, height: size)
            .background(tint.0, in: Circle())
            .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "To: ", with: "").replacingOccurrences(of: "Dr. ", with: "")
        let words = cleaned.split(whereSeparator: { $0 == " " || $0 == "," }).filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap(\.first).map(String.init)
        return letters.joined().uppercased()
    }
}

/// Mono "19 / 20".
struct ScoreLabel: View {
    @Environment(\.thubanTheme) private var theme
    var score: Double?
    var possible: Double?
    var size: CGFloat = 15
    var dim = false

    var body: some View {
        Text("\(PointsText.short(score)) / \(PointsText.short(possible))")
            .tFont(.mono(size, .semibold))
            .foregroundStyle(dim ? theme.inkFaintColor : theme.inkColor)
            .accessibilityLabel("\(PointsText.short(score)) out of \(PointsText.short(possible))")
    }
}

extension View {
    /// Standard page gutters.
    func gutter() -> some View { padding(.horizontal, IOSMetrics.gutter) }
}

enum PointsText {
    /// "18.5", "8.25", "20" — `DueFormatter.points` without trailing zeros.
    static func short(_ value: Double?) -> String {
        var text = DueFormatter.points(value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
