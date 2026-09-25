import SwiftUI
import ThubanCanvasCore
import UIKit

/// First run: Canvas address (UNC Charlotte prefilled) + access token, "Save & test" validates with a read and
/// stores the pair in the protected file.
struct ConnectScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var host = "https://instructure.charlotte.edu"
    @State private var token = ""
    @FocusState private var focus: Field?

    private enum Field { case host, token }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    AppArtView(size: 56, theme: theme, ground: theme.panelColor)
                        .frame(width: 84, height: 84)
                        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
                    Eyebrow("Thuban Canvas").padding(.top, 18)
                    Text("Connect to Canvas").tFont(.display(30)).foregroundStyle(theme.inkColor).padding(.top, 6).padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    Text("Every starred course gets the same layout. Grades, due dates, modules, files and messages load here.")
                        .tFont(.text(16)).foregroundStyle(theme.inkDimColor).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Canvas address").tFont(.text(13, .semibold)).foregroundStyle(theme.inkDimColor)
                            TextField("", text: $host, prompt: Text("school.instructure.com").foregroundStyle(theme.inkFaintColor))
                                .tFont(.body).foregroundStyle(theme.inkColor)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focus, equals: .host)
                                .submitLabel(.next)
                                .onSubmit { focus = .token }
                                .accessibilityLabel("Canvas address")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        RowDivider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Access token").tFont(.text(13, .semibold)).foregroundStyle(theme.inkDimColor)
                            HStack(spacing: 8) {
                                SecureField("", text: $token, prompt: Text("Paste your token").foregroundStyle(theme.inkFaintColor))
                                    .tFont(.body).foregroundStyle(theme.inkColor)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($focus, equals: .token)
                                    .submitLabel(.go)
                                    .onSubmit(save)
                                    .accessibilityLabel("Access token")
                                Button {
                                    if let text = UIPasteboard.general.string { token = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                                } label: {
                                    Text("Paste").tFont(.text(13, .semibold)).foregroundStyle(theme.inkDimColor)
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Paste token")
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Getting a token").tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.inkDimColor)
                            step(1, Text("In Canvas, open Account, then Settings."))
                            step(2, Text("Choose ") + Text("New Access Token").fontWeight(.semibold) + Text(", name it “Thuban”."))
                            step(3, Text("Copy the token and paste it above."))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }

                    if let error = app.connectionError {
                        Text(error).tFont(.footnote).foregroundStyle(theme.negTextColor).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, IOSMetrics.gutter)
                .padding(.top, 22)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                PrimaryButton(title: "Save & test", busy: app.isConnecting, action: save)
                    .disabled(app.isConnecting || token.trimmingCharacters(in: .whitespaces).isEmpty || host.trimmingCharacters(in: .whitespaces).isEmpty)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.inkDimColor).padding(.top, 1)
                    Text("The token stays in a private file inside the app on this iPhone, not the Keychain. Thuban Canvas only reads from your account.")
                        .tFont(.footnote).foregroundStyle(theme.inkDimColor)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, IOSMetrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(theme.bgColor)
        }
        .background(theme.bgColor.ignoresSafeArea())
    }

    private func step(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.brassInkColor)
                .frame(width: 24, height: 24).background(theme.accentTintColor, in: Circle())
            text.tFont(.secondary).foregroundStyle(theme.inkColor)
        }
    }

    private func save() {
        focus = nil
        Task { await app.connect(host: host, token: token) }
    }
}
