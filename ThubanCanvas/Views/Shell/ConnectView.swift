import SwiftUI
import ThubanCanvasCore

/// First-run screen: paste the Canvas address and an access token. The token is stored in a private file under
/// Application Support (mode 0600), never in the Keychain, so launching the app never prompts.
struct ConnectView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var host = ""
    @State private var token = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    ThubanMarkView(size: 36, color: theme.brassInkColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect to Canvas")
                            .font(ThubanFont.display(28))
                            .foregroundStyle(theme.inkColor)
                        Text("Every starred course becomes a tab. Grades, due dates, modules, files and messages load here, in one consistent layout.")
                            .font(ThubanFont.body(15))
                            .foregroundStyle(theme.inkDimColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Rectangle().fill(theme.lineColor).frame(height: 1)
                VStack(alignment: .leading, spacing: 14) {
                    LabeledField(label: "Canvas address", placeholder: "school.instructure.com", text: $host)
                    LabeledField(label: "Access token", placeholder: "Paste a token from Canvas → Account → Settings → New Access Token", text: $token, secure: true)
                    Text("Tokens are kept in a private file on this Mac (not the Keychain), so opening the app never asks for a password.")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkFaintColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = app.connectionError {
                        Text(error)
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.negTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(app.isConnecting ? "Connecting…" : "Connect") {
                            Task { await app.connect(host: host, token: token) }
                        }
                        .buttonStyle(.thubanPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(app.isConnecting || host.isEmpty || token.isEmpty)
                        if app.isConnecting { ProgressView().controlSize(.small) }
                    }
                }
            }
            .thubanPanel(padding: 24)
            .frame(maxWidth: 720)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

/// Eyebrow label + text field in the Thuban style.
struct LabeledField: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var placeholder: String
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(ThubanFont.micro)
                .kerning(0.5)
                .foregroundStyle(theme.inkDimColor)
                .accessibilityHidden(true)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .accessibilityLabel(label)
            .font(ThubanFont.body(14))
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline)
            )
        }
    }
}
