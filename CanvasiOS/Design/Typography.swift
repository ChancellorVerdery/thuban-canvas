import SwiftUI
import ThubanCanvasCore

// iOS type ramp from the iOS brief: body 17, secondary 15, footnote 13, micro eyebrow 12 uppercase, serif display
// for titles and big numbers. Every size is multiplied by `thubanFontScale` = Dynamic Type × the in-app text size,
// so the whole app follows the system text size setting.

private struct ThubanFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct ThubanDyslexiaKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Dynamic Type factor × Settings → Text size.
    var thubanFontScale: CGFloat {
        get { self[ThubanFontScaleKey.self] }
        set { self[ThubanFontScaleKey.self] = newValue }
    }

    /// Settings → Dyslexia-friendly font: body text switches to the rounded design with looser tracking.
    var thubanDyslexia: Bool {
        get { self[ThubanDyslexiaKey.self] }
        set { self[ThubanDyslexiaKey.self] = newValue }
    }
}

enum TypeScale {
    /// Body-size multiplier for each Dynamic Type step (17 pt at `.large`).
    static func factor(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 14.0 / 17
        case .small: return 15.0 / 17
        case .medium: return 16.0 / 17
        case .large: return 1
        case .xLarge: return 19.0 / 17
        case .xxLarge: return 21.0 / 17
        case .xxxLarge: return 23.0 / 17
        case .accessibility1: return 28.0 / 17
        case .accessibility2: return 33.0 / 17
        case .accessibility3: return 40.0 / 17
        case .accessibility4: return 47.0 / 17
        case .accessibility5: return 53.0 / 17
        @unknown default: return 1
        }
    }
}

enum TStyle {
    case display(CGFloat)
    case text(CGFloat, Font.Weight = .regular)
    case mono(CGFloat, Font.Weight = .regular)
    /// 12 pt semibold uppercase eyebrow.
    case micro

    static let body = TStyle.text(17, .regular)
    static let bodyStrong = TStyle.text(17, .semibold)
    static let secondary = TStyle.text(15, .regular)
    static let footnote = TStyle.text(13, .regular)
}

struct TFontModifier: ViewModifier {
    @Environment(\.thubanFontScale) private var scale
    @Environment(\.thubanDyslexia) private var dyslexia
    var style: TStyle

    func body(content: Content) -> some View {
        switch style {
        case .display(let size):
            content.font(.system(size: size * min(scale, 1.8), weight: .semibold, design: .serif))
        case .text(let size, let weight):
            content.font(.system(size: size * scale, weight: weight, design: dyslexia ? .rounded : .default))
                .tracking(dyslexia ? 0.4 : 0)
        case .mono(let size, let weight):
            content.font(.system(size: size * scale, weight: weight, design: .monospaced))
        case .micro:
            content.font(.system(size: 12 * min(scale, 1.6), weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.9)
        }
    }
}

extension View {
    func tFont(_ style: TStyle) -> some View { modifier(TFontModifier(style: style)) }
    func tFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View { modifier(TFontModifier(style: .text(size, weight))) }
}

/// Metrics from the iOS brief.
enum IOSMetrics {
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let chipRadius: CGFloat = 6
    static let rowHeight: CGFloat = 52
    static let hitTarget: CGFloat = 44
    static let barHeight: CGFloat = 44
    static let primaryHeight: CGFloat = 50
    static let sectionGap: CGFloat = 18
}
