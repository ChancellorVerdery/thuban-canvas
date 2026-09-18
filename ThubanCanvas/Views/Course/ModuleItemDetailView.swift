import AppKit
import SwiftUI
import ThubanCanvasCore

/// Target of a Canvas `/modules/items/:id` link: loads the modules if needed, finds the item and swaps this route
/// for the one clicking the item would open (page, file, assignment …). External links stay here as the
/// external-link screen; sub-headers and unknown ids explain themselves.
struct ModuleItemDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var itemId: CanvasID
    @State private var resolved = false

    private var item: ModuleItem? {
        (session.modules.value ?? []).flatMap { $0.items ?? [] }.first { $0.id == itemId }
    }

    var body: some View {
        Group {
            if let item, resolved {
                if let link = item.externalLink {
                    ExternalLinkView(url: link, title: item.title)
                } else {
                    VStack(spacing: 0) {
                        DetailHeader(eyebrow: "Module item", title: item.title, meta: item.type) {
                            if let raw = item.htmlUrl, let url = URL(string: raw) {
                                HeaderAction(symbol: "safari", label: "Open in Canvas") { NSWorkspace.shared.open(url) }
                            }
                        }
                        EmptyState(title: item.isSubHeader ? "This is a heading" : "Nothing to open",
                                   message: item.isSubHeader ? "Headings only group the items below them in the module." : "This item has no content the app can show.") {
                            Button("Back to Modules") { session.path = []; session.section = .modules }.buttonStyle(.thubanSecondary)
                        }
                    }
                }
            } else if resolved {
                EmptyState(title: "Item not found", message: "This module item is not in the course any more, or it is hidden from you.") {
                    HStack(spacing: 8) {
                        Button("Back to Modules") { session.path = []; session.section = .modules }.buttonStyle(.thubanSecondary)
                        if let url = session.canvasURL("modules/items/\(itemId)") {
                            Button("Open in Canvas") { NSWorkspace.shared.open(url) }.buttonStyle(.thubanGhostTinted)
                        }
                    }
                }
            } else {
                LoadingView(text: "Finding the module item…")
            }
        }
        .task(id: itemId) {
            if session.modules.value == nil { await session.loadModules() }
            if let route = item?.route, let index = session.path.lastIndex(of: .module(itemId)) {
                session.path[index] = route
                return
            }
            resolved = true
        }
    }
}
