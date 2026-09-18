import SwiftUI
import ThubanCanvasCore

/// The course's wiki pages: front page first, then alphabetical, with the updated date. Click opens the page in
/// the app.
struct PagesView: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var scale
    @Bindable var session: CourseSession
    @State private var query = ""

    var body: some View {
        ResourceStateView(resource: session.pages, emptyTitle: "No pages", emptyMessage: "This course has no pages yet.", isEmpty: { $0.isEmpty },
                          retry: { await session.loadPages(force: true) }) { pages in
            let visible = sorted(pages)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    SearchField(text: $query, placeholder: "Search pages")
                        .frame(maxWidth: 320)
                        .accessibilityLabel("Search pages")
                    Text(pages.count == 1 ? "1 page" : "\(pages.count) pages")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if visible.isEmpty {
                    EmptyState(title: "No matches", message: "No page title contains “\(query)”.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(visible) { page in
                                PageRow(page: page, scale: scale) { session.path.append(.page(slug: page.url)) }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 1240, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .task(id: session.id) { await session.loadPages() }
    }

    private func sorted(_ pages: [Page]) -> [Page] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matching = needle.isEmpty ? pages : pages.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        return matching.sorted { a, b in
            if (a.frontPage ?? false) != (b.frontPage ?? false) { return a.frontPage ?? false }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

private struct PageRow: View {
    @Environment(\.thubanTheme) private var theme
    var page: Page
    var scale: Double
    var action: () -> Void

    var body: some View {
        ListRowCard(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.frontPage == true ? "house" : "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .frame(width: 20)
                Text(page.title.trimmingCharacters(in: .whitespaces))
                    .font(ThubanFont.scaled(14, scale: scale, weight: .medium))
                    .foregroundStyle(page.lockedForUser == true ? theme.inkDimColor : theme.inkColor)
                    .lineLimit(1)
                if page.frontPage == true { Chip("Front page", kind: .accent) }
                if page.published == false { Chip("Unpublished", kind: .neutral) }
                Spacer(minLength: 12)
                if page.lockedForUser == true {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                        .accessibilityLabel("Locked")
                }
                if let updated = ContentDates.updated(page.updatedAt) { MetaText(updated) }
            }
        }
        .accessibilityLabel("\(page.title)\(page.frontPage == true ? ", front page" : "")")
    }
}
