import SwiftUI
import ThubanCanvasCore

struct AboutSettings: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Thuban Canvas") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ThubanMarkView(size: 28, color: theme.brassInkColor)
                        Text("A calmer Canvas: the same layout for every course, grades and due dates in one place, files that open in the app.")
                            .font(ThubanFont.body(14))
                            .foregroundStyle(theme.inkDimColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Rectangle().fill(theme.lineColor).frame(height: 1)
                    Text("Reads your Canvas through its public REST API with your own access token. Anything that writes to Canvas (submitting, replying, messaging) asks for confirmation first. Nothing is sent anywhere but your school’s Canvas server.")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") · A sibling of Thuban Study")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkFaintColor)
                }
                .padding(14)
                .thubanPanel(padding: 0)
            }
        }
    }
}
