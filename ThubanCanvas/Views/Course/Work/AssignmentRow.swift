import SwiftUI
import ThubanCanvasCore

/// One assignment / quiz / discussion in a list: type glyph, name, due line with countdown, score, status chips.
struct AssignmentRow: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var item: WorkItem
    var action: () -> Void

    var body: some View {
        ListRowCard(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isDone ? theme.inkFaintColor : theme.brassInkColor)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(ThubanFont.scaled(14, scale: textScale, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(WorkText.due(item.dueAt))
                            .font(ThubanFont.scaled(12.5, scale: textScale))
                            .foregroundStyle(dueColor)
                            .monospacedDigit()
                        if item.lockedForUser {
                            Glyph(.lock, size: 12).foregroundStyle(theme.inkFaintColor)
                        }
                    }
                }
                Spacer(minLength: 12)
                if let chip = Chip.status(item) { chip }
                if item.late, item.status == .overdue || item.status == .upcoming {
                    Chip("Late", kind: .neg)
                }
                ScoreText(score: item.score, possible: item.pointsPossible)
                    .frame(width: 84, alignment: .trailing)
                    .opacity(item.pointsPossible == nil && item.score == nil ? 0.4 : 1)
                Glyph(.chevronRight, size: 12).foregroundStyle(theme.inkFaintColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var dueColor: Color {
        switch item.status {
        case .overdue: return theme.negTextColor
        case .upcoming:
            if let due = item.dueAt, due.timeIntervalSinceNow < 86_400 { return theme.brassInkColor }
            return theme.inkDimColor
        default: return theme.inkDimColor
        }
    }

    private var accessibilityText: String {
        var parts = ["\(item.kind.label): \(item.title)", WorkText.due(item.dueAt)]
        if item.lockedForUser { parts.append("locked") }
        if let score = item.score { parts.append("score \(DueFormatter.points(score)) of \(DueFormatter.points(item.pointsPossible))") }
        else if let possible = item.pointsPossible { parts.append("\(DueFormatter.points(possible)) points") }
        parts.append(item.status.rawValue)
        return parts.joined(separator: ", ")
    }
}
