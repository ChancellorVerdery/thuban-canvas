import AppKit
import SwiftUI
import ThubanCanvasCore

/// A link the app cannot show itself (an external tool, a YouTube page …): the address, where it goes, and one
/// button that opens it in the browser. Nothing loads until the user asks.
struct ExternalLinkView: View {
    @Environment(\.thubanTheme) private var theme
    var url: URL
    var title: String?

    private var host: String { url.host ?? url.absoluteString }
    private var isCanvasTool: Bool { url.path.contains("/external_tools/") || url.path.contains("/modules/items/") }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(eyebrow: isCanvasTool ? "External tool" : "Link", title: title ?? host, meta: title == nil ? nil : host) {
                HeaderAction(symbol: "doc.on.doc", label: "Copy link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
            VStack(spacing: 18) {
                Image(systemName: isCanvasTool ? "app.badge" : "link")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                Text(isCanvasTool ? "This opens in your browser" : "This link leaves Thuban Canvas")
                    .font(ThubanFont.display(20))
                    .foregroundStyle(theme.inkColor)
                Text(isCanvasTool
                     ? "External tools sign you in through Canvas, so they run in the browser rather than here."
                     : "The page is not part of Canvas, so it opens in your default browser.")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Text(url.absoluteString)
                    .font(ThubanFont.mono(12))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 560)
                    .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari").font(.system(size: 13, weight: .semibold))
                        Text("Open in browser")
                    }
                }
                .buttonStyle(.thubanPrimary)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Open \(host) in the browser")
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
