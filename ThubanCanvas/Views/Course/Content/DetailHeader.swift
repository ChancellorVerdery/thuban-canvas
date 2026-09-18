import SwiftUI
import ThubanCanvasCore

/// The header every pushed detail shares: an optional eyebrow, the title in the display serif, a meta line or a
/// `subtitle` row (chips, author), ghost actions on the right, and optional `below` rows (meta fields, notes).
/// Sits above the content with a hairline below. Title size and header padding live only here.
struct DetailHeader<Subtitle: View, Actions: View, Below: View>: View {
    @Environment(\.thubanTheme) private var theme
    var eyebrow: String?
    var title: String
    var meta: String?
    var titleLineLimit: Int
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var below: () -> Below

    /// The simple header: eyebrow, title, a one-line meta string and actions.
    init(eyebrow: String? = nil, title: String, meta: String? = nil, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() })
    where Subtitle == EmptyView, Below == EmptyView {
        self.eyebrow = eyebrow
        self.title = title
        self.meta = meta
        self.titleLineLimit = 2
        self.subtitle = { EmptyView() }
        self.actions = actions
        self.below = { EmptyView() }
    }

    /// The rich header: a `subtitle` row under the title (chips, author line) and `below` rows after the title/actions.
    init(eyebrow: String? = nil, title: String, titleLineLimit: Int = 2,
         @ViewBuilder subtitle: @escaping () -> Subtitle,
         @ViewBuilder actions: @escaping () -> Actions = { EmptyView() },
         @ViewBuilder below: @escaping () -> Below = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.meta = nil
        self.titleLineLimit = titleLineLimit
        self.subtitle = subtitle
        self.actions = actions
        self.below = below
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                        .lineLimit(titleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    subtitle()
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) { actions() }
                    .padding(.top, 2)
            }
            below()
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
