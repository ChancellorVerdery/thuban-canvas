import AppKit
import SwiftUI
import ThubanCanvasCore
import UniformTypeIdentifiers

/// Hand work in for an assignment: text entry, a URL, or files — whichever the assignment allows — plus an optional
/// comment. The primary button opens `ConfirmWriteSheet`; only a confirm there calls the Canvas submit endpoint.
struct SubmitSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    let session: CourseSession
    let assignment: Assignment
    /// Called with the new submission after Canvas accepts it.
    var onSubmitted: (Submission) -> Void
    var dismiss: () -> Void

    enum Method: Hashable {
        case text, url, upload
        var label: String {
            switch self {
            case .text: return "Text entry"
            case .url: return "Website URL"
            case .upload: return "File upload"
            }
        }
    }

    @State private var method: Method
    @State private var text = ""
    @State private var urlText = ""
    @State private var files: [URL] = []
    @State private var comment = ""
    @State private var confirming = false
    @State private var isSending = false
    @State private var sendError: String?

    init(session: CourseSession, assignment: Assignment, onSubmitted: @escaping (Submission) -> Void, dismiss: @escaping () -> Void) {
        self.session = session
        self.assignment = assignment
        self.onSubmitted = onSubmitted
        self.dismiss = dismiss
        _method = State(initialValue: Self.methods(for: assignment).first ?? .upload)
    }

    static func methods(for assignment: Assignment) -> [Method] {
        let types = assignment.submissionTypes ?? []
        var methods: [Method] = []
        if types.contains("online_upload") { methods.append(.upload) }
        if types.contains("online_text_entry") { methods.append(.text) }
        if types.contains("online_url") { methods.append(.url) }
        return methods
    }

    private var methods: [Method] { Self.methods(for: assignment) }
    private var allowedExtensions: [String] { (assignment.allowedExtensions ?? []).map { $0.lowercased() } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Submit").font(ThubanFont.display(22)).foregroundStyle(theme.inkColor)
                Text(assignment.name).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor).lineLimit(2)
            }
            if methods.count > 1 {
                SegmentedPicker(selection: $method, options: methods.map { SegmentOption($0, $0.label) })
                    .accessibilityLabel("Submission type")
            }
            editor
            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Comment (optional)")
                TextField("A note for your instructor", text: $comment)
                    .thubanField()
                    .accessibilityLabel("Comment")
            }
            if let due = assignment.dueAt, due < Date() {
                InlineNote(symbol: "clock.badge.exclamationmark", text: "This assignment was due \(WorkText.full(due)). Canvas will mark it late.", tone: .warn)
            }
            HStack {
                Text("You will confirm before anything is sent.")
                    .font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                Spacer()
                Button("Cancel", action: dismiss).buttonStyle(.thubanSecondary).keyboardShortcut(.cancelAction)
                Button("Submit…") { sendError = nil; confirming = true }
                    .buttonStyle(.thubanPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSending)
                    .accessibilityLabel("Submit to Canvas")
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(theme.panelColor)
        .sheet(isPresented: $confirming) {
            ConfirmWriteSheet(
                title: "Submit to Canvas?",
                message: "This sends your work to \(session.displayName) and cannot be undone here.",
                actionLabel: "Submit",
                isWorking: isSending,
                error: sendError,
                confirm: { Task { await perform() } },
                cancel: { if !isSending { confirming = false } }
            )
        }
    }

    // MARK: Editors

    @ViewBuilder
    private var editor: some View {
        switch method {
        case .text:
            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Your text")
                TextEditor(text: $text)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkColor)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 220)
                    .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                    .accessibilityLabel("Submission text")
            }
        case .url:
            VStack(alignment: .leading, spacing: 6) {
                eyebrow("Website URL")
                TextField("https://", text: $urlText)
                    .thubanField(invalid: !urlText.isEmpty && !urlIsValid, mono: true)
                    .accessibilityLabel("Website URL")
                if !urlText.isEmpty, !urlIsValid {
                    Text("Enter a full address starting with http:// or https://.").font(ThubanFont.small).foregroundStyle(theme.negTextColor)
                }
            }
        case .upload:
            VStack(alignment: .leading, spacing: 6) {
                eyebrow(allowedExtensions.isEmpty ? "Files" : "Files · " + allowedExtensions.map { $0.uppercased() }.joined(separator: ", "))
                VStack(spacing: 0) {
                    if files.isEmpty {
                        Text("No files chosen").font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    } else {
                        ForEach(files, id: \.self) { file in
                            fileRow(file)
                            if file != files.last { Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline) }
                        }
                    }
                }
                .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                HStack {
                    Button("Choose files…", action: chooseFiles).buttonStyle(.thubanSecondary)
                    if let bad = rejectedFiles.first {
                        Text("\(bad.lastPathComponent) is not an allowed type.").font(ThubanFont.small).foregroundStyle(theme.negTextColor)
                    }
                }
            }
        }
    }

    private func fileRow(_ file: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkDimColor)
            Text(file.lastPathComponent).font(ThubanFont.small).foregroundStyle(isAllowed(file) ? theme.inkColor : theme.negTextColor).lineLimit(1)
            Spacer()
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).font(ThubanFont.small).foregroundStyle(theme.inkFaintColor)
            }
            IconButton(glyph: .close, label: "Remove \(file.lastPathComponent)", size: 26, iconSize: 12) {
                files.removeAll { $0 == file }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased()).font(ThubanFont.micro).kerning(0.5).foregroundStyle(theme.inkDimColor)
    }

    // MARK: Validation

    private var urlIsValid: Bool {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func isAllowed(_ file: URL) -> Bool {
        allowedExtensions.isEmpty || allowedExtensions.contains(file.pathExtension.lowercased())
    }

    private var rejectedFiles: [URL] { files.filter { !isAllowed($0) } }

    private var isValid: Bool {
        switch method {
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url: return urlIsValid
        case .upload: return !files.isEmpty && rejectedFiles.isEmpty
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose the file(s) to submit for \(assignment.name)"
        if !allowedExtensions.isEmpty {
            let types = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
            if !types.isEmpty { panel.allowedContentTypes = types }
        }
        if panel.runModal() == .OK {
            for url in panel.urls where !files.contains(url) { files.append(url) }
        }
    }

    // MARK: Send (only after ConfirmWriteSheet)

    private func perform() async {
        guard let client = app.client, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let submission: Submission
            let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            switch method {
            case .text:
                submission = try await client.submitText(course: session.id, assignment: assignment.id, body: text, comment: note)
            case .url:
                submission = try await client.submitURL(course: session.id, assignment: assignment.id, url: urlText.trimmingCharacters(in: .whitespaces), comment: note)
            case .upload:
                submission = try await client.submitFiles(course: session.id, assignment: assignment.id, files: files, comment: note)
            }
            confirming = false
            onSubmitted(submission)
            await session.loadGroups(force: true)
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }
}
