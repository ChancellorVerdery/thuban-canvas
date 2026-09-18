import AppKit
import Foundation
import ThubanCanvasCore
import WebKit
import os

/// Visual smoke test driven by `THUBAN_CANVAS_SMOKE=<output dir>` (see `scripts/smoke.sh`). With real (read-only)
/// credentials in the temporary home, walks Home, every course section, Calendar, Inbox and Settings, writes
/// composited PNGs (native chrome + every WKWebView) and terminates. Never calls a write endpoint.
@MainActor
enum SmokeHarness {
    static let variable = "THUBAN_CANVAS_SMOKE"
    private static let logger = Logger(subsystem: "com.thuban.canvas", category: "smoke")

    static var outputDirectory: URL? {
        guard let raw = ProcessInfo.processInfo.environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var isEnabled: Bool { outputDirectory != nil }

    /// Extra screens registered by feature implementers: name → action that puts the app in that state.
    /// Each runs after the standard walk, with a settle delay before capture.
    static var extraScenes: [(name: String, prepare: (AppModel) async -> Void)] = []

    static func startIfEnabled(app: AppModel) {
        guard let directory = outputDirectory else { return }
        Task { await run(app: app, directory: directory) }
    }

    private static func run(app: AppModel, directory: URL) async {
        var status: Int32 = 0
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let window = try await waitForMainWindow()
            window.setContentSize(NSSize(width: 1400, height: 880))
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            await sleep(0.5)

            if app.client == nil {
                _ = try await capture(window: window, name: "00-connect", in: directory)
            } else {
                app.select(.home)
                await app.loadHomeResources()
                await sleep(1.5)
                _ = try await capture(window: window, name: "01-home", in: directory)

                for (index, session) in app.orderedSessions.prefix(3).enumerated() {
                    app.select(.course(session.id))
                    await session.loadGroups()
                    await sleep(0.8)
                    for section in session.availableSections {
                        session.section = section
                        session.path = []
                        await sleep(section == .overview ? 1.0 : 2.5)
                        let name = String(format: "%02d-course%d-%@", 10 + index * 12 + (CourseSection.allCases.firstIndex(of: section) ?? 0), index + 1, section.rawValue)
                        _ = try await capture(window: window, name: name, in: directory)
                    }
                }

                app.panel = .calendar
                await sleep(2.5)
                _ = try await capture(window: window, name: "50-calendar", in: directory)
                app.panel = .inbox
                await sleep(2.5)
                _ = try await capture(window: window, name: "51-inbox", in: directory)
                app.panel = nil

                for scene in extraScenes {
                    await scene.prepare(app)
                    await sleep(2.0)
                    _ = try await capture(window: window, name: "60-\(scene.name)", in: directory)
                }

                app.select(.home)
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                await sleep(1.0)
                _ = try await capture(window: window, name: "70-home-dark", in: directory)
            }
            NSApp.activate(ignoringOtherApps: false)
            app.settingsRequest += 1
            let settings = try await waitForWindow(timeout: 5) { $0.title == "Settings" }
            await sleep(1.0)
            _ = try await capture(window: settings, name: "80-settings", in: directory)
            // Grades & GPA pane with a seeded transcript semester (the first row expands in smoke mode).
            app.settings.pastSemesters = [
                PastSemester(name: "Spring 2026", classes: [
                    PastClass(name: "Physics II", credits: 4, letter: "A-"),
                    PastClass(name: "Technical Writing", credits: 3, letter: "B+"),
                    PastClass(name: "Statics Lab", credits: 1, letter: ""),
                ], scale: .plusMinus),
                PastSemester(name: "Fall 2025", gpa: 3.62, credits: 16),
            ]
            app.openSettings(pane: "Grades & GPA")
            settings.setContentSize(NSSize(width: 880, height: 1200))
            await sleep(0.8)
            app.settingsScrollAnchor = SettingsAnchor.pastSemesters
            await sleep(1.0)
            _ = try await capture(window: settings, name: "81-settings-grades", in: directory)
        } catch {
            logger.error("smoke failed: \(error.localizedDescription, privacy: .public)")
            fputs("smoke: FAILED: \(error.localizedDescription)\n", stderr)
            status = 1
        }
        print("smoke: done")
        exit(status)
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func waitForMainWindow() async throws -> NSWindow {
        try await waitForWindow(timeout: 10) { $0.isVisible && $0.title != "Settings" && $0.contentView != nil }
    }

    private static func waitForWindow(timeout: Double, _ predicate: (NSWindow) -> Bool) async throws -> NSWindow {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let window = NSApp.windows.first(where: predicate) { return window }
            await sleep(0.1)
        }
        throw ThubanError.store("smoke: window did not appear within \(Int(timeout)) s")
    }

    /// Renders the window's native content (`cacheDisplay`) and composites every visible `WKWebView` snapshot at
    /// its window position. No screen-recording permission involved.
    private static func capture(window: NSWindow, name: String, in directory: URL) async throws -> URL {
        guard let content = window.contentView else { throw ThubanError.store("smoke: window has no content view") }
        let bounds = content.bounds
        guard let nativeRep = content.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw ThubanError.store("smoke: could not create a bitmap for \(name)")
        }
        content.cacheDisplay(in: bounds, to: nativeRep)
        let native = NSImage(size: bounds.size)
        native.addRepresentation(nativeRep)

        let contentOrigin = content.convert(content.bounds, to: nil).origin
        var overlays: [(rect: NSRect, image: NSImage, source: NSRect)] = []
        for webView in subviews(of: content).compactMap({ $0 as? WKWebView }) {
            let visible = webView.visibleRect
            guard !webView.isHiddenOrHasHiddenAncestor, webView.window === window, visible.width > 1, visible.height > 1 else { continue }
            var rect = webView.convert(visible, to: nil)
            rect.origin.x -= contentOrigin.x
            rect.origin.y -= contentOrigin.y
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            do {
                let image = try await webView.takeSnapshot(configuration: configuration)
                let sourceY = webView.isFlipped ? webView.bounds.height - visible.maxY : visible.minY
                overlays.append((rect, image, NSRect(x: visible.minX, y: sourceY, width: visible.width, height: visible.height)))
            } catch {
                logger.error("snapshot failed in \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let scale = window.backingScaleFactor
        guard let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ThubanError.store("smoke: could not allocate the output bitmap")
        }
        output.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: output) else { throw ThubanError.store("smoke: no graphics context") }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        native.draw(in: NSRect(origin: .zero, size: bounds.size))
        for overlay in overlays {
            overlay.image.draw(in: overlay.rect, from: overlay.source, operation: .sourceOver, fraction: 1)
        }
        context.flushGraphics()
        guard let png = output.representation(using: .png, properties: [:]) else { throw ThubanError.store("smoke: PNG encoding failed for \(name)") }
        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("smoke: \(name): \(overlays.count) web view(s) composited")
        return url
    }

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + subviews(of: $0) }
    }
}
