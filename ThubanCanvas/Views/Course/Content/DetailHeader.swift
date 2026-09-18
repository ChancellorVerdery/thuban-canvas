import SwiftUI
import ThubanCanvasCore

/// The header every pushed detail (page, file, module item, link) shares: an optional eyebrow, the title in the
/// display serif, a meta line, and ghost actions on the right. Sits above the content with a hairline below.
struct DetailHeader<Actions: View>: View {
    @Environment(\.thubanTheme) private var theme
    var eyebrow: String?
    var title: String
    var meta: String?
    @ViewBuilder var actions: () -> Actions

    init(eyebrow: String? = nil, title: String, meta: String? = nil, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.meta = meta
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(ThubanFont.micro)
                        .kerning(0.5)
                        .foregroundStyle(theme.inkDimColor)
                }
                Text(title)
                    .font(ThubanFont.display(24))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) { actions() }
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .accessibilityElement(children: .contain)
    }
}

/// A ghost action for the header: SF Symbol + label, brass text.
struct HeaderAction: View {
    var symbol: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(label)
            }
        }
        .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 8))
        .accessibilityLabel(label)
        .help(label)
    }
}
