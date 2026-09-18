import Foundation
import ThubanCanvasCore

/// Extra smoke screens for the course-content views the standard walk never reaches or reaches too early (page
/// detail, PDF and Quick Look previews, a module-item redirect, the external-link screen, Pages, People once it
/// has loaded, and two dark-mode shots). Registered once, only when the smoke harness is on; every scene picks
/// real items from whatever the account has. Read-only throughout.
@MainActor
enum CourseContentSmoke {
    private static var registered = false

    static func registerIfNeeded(app: AppModel) {
        guard SmokeHarness.isEnabled, !registered else { return }
        registered = true

        SmokeHarness.extraScenes.append(("pages", { app in
            guard let session = app.orderedSessions.first(where: { $0.availableSections.contains(.pages) }) else { return }
            app.open(course: session.id, section: .pages)
            await session.loadPages()
        }))

        SmokeHarness.extraScenes.append(("people", { app in
            guard let session = app.orderedSessions.first(where: { $0.availableSections.contains(.people) }) else { return }
            app.open(course: session.id, section: .people)
            await session.loadPeople()
        }))

        // Prefers a course whose Pages tab is disabled (the page is still reachable through its modules).
        SmokeHarness.extraScenes.append(("page-detail", { app in
            let candidates = app.orderedSessions.filter { $0.availableSections.contains(.modules) }
                .sorted { !$0.availableSections.contains(.pages) && $1.availableSections.contains(.pages) }
            for session in candidates {
                await session.loadModules()
                if let slug = (session.modules.value ?? []).flatMap({ $0.items ?? [] }).first(where: { $0.type == "Page" })?.pageUrl {
                    app.open(course: session.id, section: .modules, route: .page(slug: slug))
                    return
                }
            }
        }))

        SmokeHarness.extraScenes.append(("module-item", { app in
            for session in app.orderedSessions where session.availableSections.contains(.modules) {
                await session.loadModules()
                if let item = (session.modules.value ?? []).flatMap({ $0.items ?? [] }).first(where: { $0.type == "Page" }) {
                    app.open(course: session.id, section: .modules, route: .module(item.id))
                    return
                }
            }
        }))

        // The smallest PDF linked from a module, downloaded before the screen opens so the capture shows pages.
        SmokeHarness.extraScenes.append(("file-pdf", { app in
            guard let client = app.client else { return }
            var best: (session: CourseSession, file: CanvasFile)?
            for session in app.orderedSessions where session.availableSections.contains(.modules) {
                await session.loadModules()
                for item in session.moduleFileItems.prefix(12) {
                    guard let id = item.contentId, (item.contentDetails?.displayName ?? item.title).lowercased().hasSuffix(".pdf"),
                          let file = try? await client.courseFile(course: session.id, id: id) else { continue }
                    if best == nil || (file.size ?? .max) < (best?.file.size ?? .max) { best = (session, file) }
                }
                if best != nil { break }
            }
            guard let best, let raw = best.file.url, let url = URL(string: raw) else { return }
            try? await client.download(url, to: FileDetailView.cachePath(for: best.file))
            app.open(course: best.session.id, section: .modules, route: .file(best.file.id))
        }))

        SmokeHarness.extraScenes.append(("file-quicklook", { app in
            guard let client = app.client else { return }
            for session in app.orderedSessions where session.availableSections.contains(.files) {
                await session.loadFiles()
                let candidates = (session.files.value ?? []).filter { ["ppt", "doc", "xls"].contains($0.resolvedKind) }
                guard let file = candidates.min(by: { ($0.size ?? .max) < ($1.size ?? .max) }), let raw = file.url, let url = URL(string: raw) else { continue }
                try? await client.download(url, to: FileDetailView.cachePath(for: file))
                app.open(course: session.id, section: .files, route: .file(file.id))
                return
            }
        }))

        SmokeHarness.extraScenes.append(("external-link", { app in
            guard let session = app.orderedSessions.first(where: { $0.availableSections.contains(.modules) }) ?? app.orderedSessions.first else { return }
            await session.loadModules()
            let url = (session.modules.value ?? []).flatMap { $0.items ?? [] }.compactMap(\.externalLink).first
                ?? URL(string: "https://www.charlotte.edu/")!
            app.open(course: session.id, section: .modules, route: .externalURL(url))
        }))

        SmokeHarness.extraScenes.append(("overview-dark", { app in
            guard let session = app.orderedSessions.first(where: { $0.course.imageDownloadUrl != nil }) ?? app.orderedSessions.first else { return }
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
            app.open(course: session.id, section: .overview)
        }))

        SmokeHarness.extraScenes.append(("modules-dark", { app in
            guard let session = app.orderedSessions.first(where: { $0.availableSections.contains(.modules) }) else { return }
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
            app.open(course: session.id, section: .modules)
            await session.loadModules()
        }))
    }
}
