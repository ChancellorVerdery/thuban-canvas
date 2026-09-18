import AppKit
import SwiftUI
import ThubanCanvasCore

/// One file: metadata (course scope first, then the global endpoint), a cached download under the app's files
/// folder, then the right preview — PDFKit, native images, mono text, Quick Look for the rest. Actions: Open,
/// Save to Downloads (then reveal), Show in Finder.
struct FileDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var fileId: CanvasID
    @State private var file: CanvasFile?
    @State private var localURL: URL?
    @State private var error: ThubanError?
    @State private var phase: Phase = .metadata
    @State private var savedURL: URL?

    enum Phase { case metadata, downloading, ready, failed }

    /// The list / module entry, for an instant title while metadata loads.
    private var listedName: String? {
        session.files.value?.first { $0.id == fileId }?.displayName
            ?? session.moduleFileItems.first { $0.contentId == fileId }.map { $0.contentDetails?.displayName ?? $0.title }
    }

    private var title: String { file?.displayName ?? listedName ?? "File" }

    private var meta: String? {
        guard let file else { return nil }
        var parts: [String] = []
        if let size = file.sizeLabel { parts.append(size) }
        if let folder = file.folderId.flatMap({ id in session.folders.value?.first { $0.id == id } })?.displayPath, folder != "Course files" { parts.append(folder) }
        if let updated = ContentDates.updated(file.displayDate) { parts.append(updated) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(eyebrow: file?.kindLabel ?? "File", title: title, meta: meta) {
                if savedURL != nil { Chip("Saved", kind: .pos).padding(.trailing, 4) }
                if localURL != nil {
                    HeaderAction(symbol: "arrow.up.forward.app", label: "Open") { open() }
                    HeaderAction(symbol: "arrow.down.circle", label: "Save to Downloads") { saveToDownloads() }
                    HeaderAction(symbol: "folder", label: "Show in Finder") { showInFinder() }
                } else if let raw = file?.url, let url = URL(string: raw) {
                    HeaderAction(symbol: "safari", label: "Open in browser") { NSWorkspace.shared.open(url) }
                }
            }
            content
        }
        .task(id: fileId) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .metadata:
            LoadingView(text: "Loading file details…")
        case .downloading:
            LoadingView(text: file?.sizeLabel.map { "Downloading \($0)…" } ?? "Downloading…")
        case .failed:
            if let file, file.lockedForUser == true {
                EmptyState(title: "This file is locked", message: file.lockExplanation ?? "Your instructor has not made it available yet.") {
                    if let raw = file.url, let url = URL(string: raw) {
                        Button("Open in Canvas") { NSWorkspace.shared.open(url) }.buttonStyle(.thubanSecondary)
                    }
                }
            } else {
                EmptyState(title: "Couldn’t load the file", message: error?.localizedDescription ?? "Unknown error") {
                    HStack(spacing: 8) {
                        Button("Try again") { Task { await load(force: true) } }.buttonStyle(.thubanSecondary)
                        if let url = session.canvasURL("files/\(fileId)") {
                            Button("Open in Canvas") { NSWorkspace.shared.open(url) }.buttonStyle(.thubanGhostTinted)
                        }
                    }
                }
            }
        case .ready:
            if let localURL, let file {
                preview(for: file, at: localURL)
            } else {
                LoadingView()
            }
        }
    }

    @ViewBuilder
    private func preview(for file: CanvasFile, at url: URL) -> some View {
        switch file.resolvedKind {
        case "pdf":
            PDFPreview(url: url)
        case "image":
            ImagePreview(url: url, name: file.displayName)
        case "text", "code":
            TextPreview(url: url)
        default:
            ZStack(alignment: .bottom) {
                QuickLookPreview(url: url)
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold))
                    Text("Preview by Quick Look. If it stays blank, use Open to view the file in its app.")
                        .font(ThubanFont.small)
                    Spacer()
                    Button("Open") { open() }.buttonStyle(GhostButtonStyle(height: 24, tinted: true, horizontalPadding: 8))
                }
                .foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(theme.panelColor)
                .thubanHairline(.top, color: theme.lineColor)
            }
        }
    }

    // MARK: Loading

    private func load(force: Bool = false) async {
        guard let client = app.client else { error = .notConnected; phase = .failed; return }
        phase = .metadata
        error = nil
        do {
            let fetched: CanvasFile
            do {
                fetched = try await client.courseFile(course: session.id, id: fileId)
            } catch {
                fetched = try await client.file(fileId)
            }
            file = fetched
            guard fetched.lockedForUser != true, let raw = fetched.url, let remote = URL(string: raw) else {
                error = .unavailable(fetched.lockExplanation ?? "This file is locked.")
                phase = .failed
                return
            }
            let destination = Self.cachePath(for: fetched)
            let cached = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            if force || cached == 0 {
                phase = .downloading
                try await client.download(remote, to: destination)
            }
            localURL = destination
            phase = .ready
        } catch let thrown as ThubanError {
            error = thrown
            if case .unauthorized = thrown { app.noteUnauthorized() }
            phase = .failed
        } catch {
            self.error = .network(error.localizedDescription)
            phase = .failed
        }
    }

    /// `<files dir>/<id>-<display name>` with path separators removed from the name.
    static func cachePath(for file: CanvasFile) -> URL {
        let safe = file.displayName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return AppPaths.downloadsDirectory.appendingPathComponent("\(file.id)-\(safe)")
    }

    // MARK: Actions

    private func open() {
        guard let localURL else { return }
        NSWorkspace.shared.open(localURL)
    }

    private func showInFinder() {
        guard let localURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([localURL])
    }

    /// Copies into the user's download folder (Settings → Data, else ~/Downloads), avoiding name clashes, then reveals it.
    private func saveToDownloads() {
        guard let localURL, let file else { return }
        let folder: URL
        if let custom = app.settings.downloadFolder, !custom.isEmpty {
            folder = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        }
        let name = file.displayName.replacingOccurrences(of: "/", with: "-")
        var target = folder.appendingPathComponent(name)
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            target = folder.appendingPathComponent(candidate)
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: localURL, to: target)
            savedURL = target
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            self.error = .store("Could not save: \(error.localizedDescription)")
            phase = .failed
        }
    }
}
