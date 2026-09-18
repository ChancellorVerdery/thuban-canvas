import SwiftUI
import ThubanCanvasCore

/// The editable what-if cell in the Grades table: a small numeric field (tabular digits) that commits on Return or
/// blur, plus an × that pretends the assignment is ungraded. An accent border marks an active override.
struct WhatIfField: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var assignment: Assignment
    var override: WhatIfScore?
    /// `.score` / `.ungraded` to set, nil to clear the override.
    var onCommit: (WhatIfScore?) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(ThubanFont.mono(12.5 * textScale))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isActive ? theme.brassInkColor : theme.inkColor)
                .padding(.horizontal, 8)
                .frame(width: 66, height: 28)
                .background(isActive ? theme.accentTintColor : theme.bgColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isActive || focused ? theme.accentColor : theme.line2Color, lineWidth: ThubanMetrics.hairline)
                )
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onKeyPress(.escape) { sync(); focused = false; return .handled }
                .onChange(of: override) { _, _ in sync() }
                .onAppear(perform: sync)
                .accessibilityLabel("What-if score for \(assignment.name)")
                .accessibilityValue(spokenValue)
                .help("Type a hypothetical score out of \(DueFormatter.points(assignment.pointsPossible)); Return or Tab applies it")
            if case .ungraded = override {
                IconButton(glyph: .reset, label: "Use the real score for \(assignment.name)", size: 24, iconSize: 12, tinted: true) {
                    onCommit(nil)
                }
            } else {
                IconButton(glyph: .close, label: "Pretend \(assignment.name) is ungraded", size: 24, iconSize: 10) {
                    text = ""
                    onCommit(.ungraded)
                }
                .opacity(canUngrade ? 1 : 0)
                .disabled(!canUngrade)
            }
        }
    }

    private var isActive: Bool { override != nil }

    /// × only makes sense when there is a real or hypothetical score to take away.
    private var canUngrade: Bool {
        if override != nil { return true }
        return assignment.submission?.isGraded == true
    }

    private var placeholder: String {
        if case .ungraded = override { return "—" }
        if let score = assignment.submission?.score, assignment.submission?.isGraded == true { return DueFormatter.points(score) }
        return "—"
    }

    /// VoiceOver never hears the "—" glyph: it gets the hypothetical, "pretending ungraded", the real score or "no score".
    private var spokenValue: String {
        if !text.isEmpty { return "hypothetical \(text)" }
        if case .ungraded = override { return "pretending ungraded" }
        if let score = assignment.submission?.score, assignment.submission?.isGraded == true {
            return "real score \(DueFormatter.points(score))"
        }
        return "no score"
    }

    private func sync() {
        if case .score(let value) = override { text = DueFormatter.points(value) } else { text = "" }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty {
            if case .score = override { onCommit(nil) }
            return
        }
        if let value = Double(trimmed), value >= 0, value.isFinite {
            let cap = max((assignment.pointsPossible ?? 0) * 10, 1000)
            let clamped = min(value, cap)
            if case .score(let current) = override, current == clamped { sync(); return }
            onCommit(.score(clamped))
        } else {
            sync()
        }
    }
}
