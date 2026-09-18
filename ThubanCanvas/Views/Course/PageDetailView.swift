import AppKit
import SwiftUI
import ThubanCanvasCore

/// One wiki page: header (title, updated date, Open in Canvas) and the body in the themed web view. Fetches the
/// page directly, so it works even when the Pages tab is disabled and the page is only reachable from a module.
struct PageDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var slug: String
    @State private var page: Page?
    @State private var error: ThubanError?

    /// The list entry, when the Pages list has it — gives an instant title while the body loads.
    private var listed: Page? { session.pages.value?.first { $0.url == slug } }

    private var title: String {
        page?.title ?? listed?.title ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var meta: String? {
        var parts: [String] = []
        if (page ?? listed)?.frontPage == true { parts.append("Front page") }
        if let updated = ContentDates.updated((page ?? listed)?.updatedAt) { parts.append(updated) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var canvasURL: URL? {
        if let raw = (page ?? listed)?.htmlUrl, let url = URL(string: raw) { return url }
        return session.canvasURL("pages/\(slug)")
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(eyebrow: "Page", title: title, meta: meta) {
                if let canvasURL {
                    HeaderAction(symbol: "safari", label: "Open in Canvas") { NSWorkspace.shared.open(canvasURL) }
                }
            }
            content
        }
        .task(id: slug) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let page {
            if page.lockedForUser == true, (page.body ?? "").isEmpty {
                EmptyState(title: "This page is locked", message: "Your instructor has not opened it yet.")
            } else if (page.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyState(title: "This page is empty", message: "Nothing has been written on it yet.")
            } else {
                CanvasHTMLView(html: page.body ?? "", title: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let error {
            EmptyState(title: "Couldn’t load the page", message: error.localizedDescription) {
                HStack(spacing: 8) {
                    Button("Try again") { Task { await load() } }.buttonStyle(.thubanSecondary)
                    if let canvasURL {
                        Button("Open in Canvas") { NSWorkspace.shared.open(canvasURL) }.buttonStyle(.thubanGhostTinted)
                    }
                }
            }
        } else {
            LoadingView()
        }
    }

    private func load() async {
        guard let client = app.client else { error = .notConnected; return }
        error = nil
        do {
            page = try await client.page(course: session.id, url: slug)
        } catch let thrown as ThubanError {
            error = thrown
            if case .unauthorized = thrown { app.noteUnauthorized() }
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }
}
