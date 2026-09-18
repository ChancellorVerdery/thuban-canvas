import SwiftUI
import ThubanCanvasCore

/// "UPCOMING · 4" eyebrow with an optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var count: Int?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, count: Int? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.count = count
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(ThubanFont.micro)
                .kerning(0.5)
                .foregroundStyle(theme.inkDimColor)
            if let count {
                Text(String(count))
                    .font(ThubanFont.micro)
                    .foregroundStyle(theme.inkFaintColor)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            accessory()
        }
    }
}

/// Page title in the display serif, with an optional subtitle line.
struct PageTitle: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(ThubanFont.display(28)).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
            }
        }
    }
}

/// Initials in a circle, or the remote avatar when it loads (Canvas avatar URLs are public thumbnails).
struct AvatarView: View {
    @Environment(\.thubanTheme) private var theme
    var name: String
    var url: String?
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(theme.accentTintColor)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
            if let url, let remote = URL(string: url), !url.contains("avatar-50") {
                AsyncImage(url: remote) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.clear }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

extension Chip {
    /// Status chip for a work item: Overdue (neg), Due soon (warn), Submitted (signal), Graded (pos), Excused.
    static func status(_ item: WorkItem, now: Date = Date()) -> Chip? {
        switch item.status {
        case .overdue: return Chip("Overdue", kind: .neg)
        case .upcoming:
            if let due = item.dueAt, due.timeIntervalSince(now) < 86_400 { return Chip("Due soon", kind: .warn) }
            return nil
        case .submitted: return Chip(item.late ? "Submitted late" : "Submitted", kind: .signal)
        case .graded: return Chip(item.late ? "Graded · late" : "Graded", kind: .pos)
        case .excused: return Chip("Excused", kind: .neutral)
        case .noDate: return nil
        }
    }

    /// Chip for a letter grade.
    static func letter(_ letter: String) -> Chip {
        let kind: ChipKind
        switch letter.prefix(1) {
        case "A": kind = .pos
        case "B": kind = .signal
        case "C": kind = .warn
        default: kind = .neg
        }
        return Chip(letter, kind: kind)
    }
}

/// A course tint dot (per-course color from Settings, else the accent).
struct CourseDot: View {
    @Environment(\.thubanTheme) private var theme
    var tint: String?
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(tint.map { Color(hex: $0) } ?? theme.accentColor).frame(width: size, height: size)
    }
}

/// Points and score in the "8 / 10" form with tabular digits.
struct ScoreText: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var score: Double?
    var possible: Double?
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            Text(DueFormatter.points(score)).foregroundStyle(score == nil ? theme.inkFaintColor : theme.inkColor)
            Text("/ \(DueFormatter.points(possible))").foregroundStyle(theme.inkDimColor)
        }
        .font(.system(size: size * textScale, weight: .medium))
        .monospacedDigit()
    }
}

/// A row card (hover highlight) used by lists across the app.
struct ListRowCard<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    init(action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.content = content
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .onHover { hovering = $0 }
    }

    private var row: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && action != nil ? theme.panel2Color : theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
    }
}

/// A search field in the Thuban style.
struct SearchField: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 6) {
            Glyph(.search, size: 14).foregroundStyle(theme.inkFaintColor)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(ThubanFont.body(13)).foregroundStyle(theme.inkColor)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Glyph(.close, size: 12)
                        .foregroundStyle(theme.inkDimColor)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
    }
}

/// Confirmation sheet shown before every write to Canvas.
struct ConfirmWriteSheet: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var message: String
    var actionLabel: String
    var isWorking: Bool
    var error: String?
    var confirm: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(ThubanFont.display(20)).foregroundStyle(theme.inkColor)
            Text(message).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(ThubanFont.small).foregroundStyle(theme.negTextColor) }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.thubanSecondary).keyboardShortcut(.cancelAction).disabled(isWorking)
                // Deliberately not the default action: Return must not be able to confirm a write to Canvas.
                Button(isWorking ? "Sending…" : actionLabel, action: confirm).buttonStyle(.thubanPrimary).disabled(isWorking)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.panelColor)
    }
}
