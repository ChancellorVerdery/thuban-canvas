import AppKit
import PDFKit
import Quartz
import SwiftUI
import ThubanCanvasCore

/// A PDF on disk, rendered with PDFKit: continuous single pages, fit to width, theme background.
struct PDFPreview: NSViewRepresentable {
    @Environment(\.thubanTheme) private var theme
    var url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        view.backgroundColor = NSColor(hex: theme.bg)
        view.setAccessibilityLabel("PDF preview")
        load(into: view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.backgroundColor = NSColor(hex: theme.bg)
        load(into: view, context: context)
    }

    private func load(into view: PDFView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        view.document = PDFDocument(url: url)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var url: URL?
    }
}

/// Quick Look for everything PDFKit and NSImage cannot open natively (slides, Word, Excel, archives …).
struct QuickLookPreview: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        view.setAccessibilityLabel("Preview")
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}

/// An image file at its natural size (scaled down to fit the width), scrollable.
struct ImagePreview: View {
    @Environment(\.thubanTheme) private var theme
    var url: URL
    var name: String
    @State private var image: NSImage?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: max(image.size.width, 1))
                    .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                    .padding(24)
                    .accessibilityLabel(name)
            } else {
                Text("This image could not be decoded.")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                    .padding(24)
            }
        }
        .task(id: url) {
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            if !Task.isCancelled { image = loaded }
        }
    }
}

/// Plain text, Markdown and source files in the mono font (capped so a giant log cannot stall the view).
struct TextPreview: View {
    @Environment(\.thubanTheme) private var theme
    var url: URL
    @State private var text = ""
    @State private var truncated = false

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                    .font(ThubanFont.mono(13))
                    .foregroundStyle(theme.inkColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                if truncated {
                    Text("Showing the first 200 KB. Open the file to read the rest.")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: url) {
            let limit = 200 * 1024
            let result: (text: String, truncated: Bool)? = await Task.detached(priority: .userInitiated) {
                guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                defer { try? handle.close() }
                guard let head = try? handle.read(upToCount: limit + 1) else { return nil }
                let truncated = head.count > limit
                return (String(decoding: head.prefix(limit), as: UTF8.self), truncated)
            }.value
            guard let result else { text = "This file could not be read."; return }
            text = result.text
            truncated = result.truncated
        }
    }
}
