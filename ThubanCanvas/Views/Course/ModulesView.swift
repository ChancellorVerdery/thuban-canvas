import AppKit
import SwiftUI
import ThubanCanvasCore

/// Modules as collapsible cards: name, state (completed / locked until …), item count, then the items indented as
/// the instructor arranged them. Every item is a button that opens the matching detail in the app; plain web
/// links open in the browser. The search field filters items across all modules.
struct ModulesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    @State private var query = ""
    @State private var collapsed: Set<CanvasID> = []

    var body: some View {
        VStack(spacing: 0) {
            ResourceStateView(resource: session.modules, emptyTitle: "No modules", emptyMessage: "This course has no modules yet.", isEmpty: { $0.isEmpty },
                              retry: { await session.loadModules(force: true) }) { modules in
                let visible = filtered(modules)
                VStack(spacing: 0) {
                    toolbar(modules: modules)
                    if visible.isEmpty {
                        EmptyState(title: "No matches", message: "Nothing in the modules matches “\(query)”.")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(visible, id: \.module.id) { entry in
                                    ModuleCard(session: session, module: entry.module, items: entry.items,
                                               isCollapsed: query.isEmpty && collapsed.contains(entry.module.id),
                                               toggle: { toggle(entry.module.id) })
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
        }
        .task(id: session.id) { await session.loadModules() }
    }

    private func toolbar(modules: [Module]) -> some View {
        let itemCount = modules.reduce(0) { $0 + ($1.items?.count ?? $1.itemsCount ?? 0) }
        let allCollapsed = collapsed.count >= modules.count
        return HStack(spacing: 12) {
            SearchField(text: $query, placeholder: "Search modules")
                .frame(maxWidth: 320)
                .accessibilityLabel("Search modules")
            Text("\(modules.count) modules · \(itemCount) items")
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
                .monospacedDigit()
            Spacer()
            Button(allCollapsed ? "Expand all" : "Collapse all") {
                collapsed = allCollapsed ? [] : Set(modules.map(\.id))
            }
            .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 8))
            .disabled(!query.isEmpty)
            .accessibilityLabel(allCollapsed ? "Expand all modules" : "Collapse all modules")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: 1240, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filtered(_ modules: [Module]) -> [(module: Module, items: [ModuleItem])] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return modules.compactMap { module in
            let items = module.items ?? []
            guard !needle.isEmpty else { return (module, items) }
            if module.name.localizedCaseInsensitiveContains(needle) { return (module, items) }
            let matches = items.filter { !$0.isSubHeader && $0.title.localizedCaseInsensitiveContains(needle) }
            return matches.isEmpty ? nil : (module, matches)
        }
    }

    private func toggle(_ id: CanvasID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }
}

// MARK: - Module card

private struct ModuleCard: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    var module: Module
    var items: [ModuleItem]
    var isCollapsed: Bool
    var toggle: () -> Void
    @State private var hovering = false

    private var count: Int { module.items?.count ?? module.itemsCount ?? items.count }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Glyph(isCollapsed ? .chevronRight : .chevronDown, size: 14)
                        .foregroundStyle(theme.inkDimColor)
                    Text(module.name)
                        .font(ThubanFont.body(15, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    stateChip
                    Spacer(minLength: 8)
                    Text(count == 1 ? "1 item" : "\(count) items")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkFaintColor)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? theme.panel2Color : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel("\(module.name), \(count) items\(module.isCompleted ? ", completed" : module.isLocked ? ", locked" : "")")
            .accessibilityAddTraits(isCollapsed ? [] : [.isSelected])
            .accessibilityHint(isCollapsed ? "Expands the module" : "Collapses the module")
            if !isCollapsed {
                if items.isEmpty {
                    Text("Nothing in this module.")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .thubanHairline(.top, color: theme.lineColor)
                } else {
                    ForEach(items) { item in
                        ModuleItemRow(session: session, item: item)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .thubanPanel(padding: 0)
    }

    @ViewBuilder
    private var stateChip: some View {
        if module.isCompleted {
            Chip("Completed", kind: .pos)
        } else if module.isLocked {
            if let unlock = module.unlockAt, unlock > Date() {
                Chip("Locked until \(DueFormatter.relative(unlock))", kind: .neutral)
            } else {
                Chip("Locked", kind: .neutral)
            }
        } else if module.state == "started" {
            Chip("In progress", kind: .signal)
        }
    }
}

// MARK: - Item row

/// One module item: indent, type symbol, title, then due date / points / lock / requirement on the right.
struct ModuleItemRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var scale
    @Bindable var session: CourseSession
    var item: ModuleItem

    private var indent: CGFloat { CGFloat(min(item.indent ?? 0, 5)) * 18 }
    private var details: ModuleItem.ContentDetails? { item.contentDetails }
    private var dimmed: Bool { item.isLocked || item.published == false }

    var body: some View {
        if item.isSubHeader {
            Text(item.title.uppercased())
                .font(ThubanFont.micro)
                .kerning(0.5)
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
                .padding(.leading, 14 + indent)
                .padding(.trailing, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .thubanHairline(.top, color: theme.lineColor)
                .accessibilityAddTraits(.isHeader)
        } else {
            CardRow(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(dimmed ? theme.inkFaintColor : theme.brassInkColor)
                        .frame(width: 18)
                    Text(item.title.trimmingCharacters(in: .whitespaces))
                        .font(ThubanFont.scaled(14, scale: scale))
                        .foregroundStyle(dimmed ? theme.inkDimColor : theme.inkColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if item.published == false { Chip("Unpublished", kind: .neutral) }
                    Spacer(minLength: 12)
                    trailing
                }
                .padding(.leading, indent)
            }
            .accessibilityLabel(accessibilityLabel)
            .help(details?.lockExplanation ?? "")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 10) {
            if let due = details?.dueAt {
                MetaText("Due \(DueFormatter.relative(due))")
            }
            if let points = details?.pointsPossible, points > 0 {
                MetaText("\(DueFormatter.points(points)) pts", faint: true)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            if item.type == "ExternalUrl" || item.type == "ExternalTool" {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.inkFaintColor)
                    .accessibilityHidden(true)
            }
            if item.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                    .accessibilityLabel(details?.lockExplanation ?? "Locked")
            }
            if let requirement = item.completionRequirement {
                let done = requirement.completed == true
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(done ? theme.posTextColor : theme.inkFaintColor)
                    .help(item.requirementLabel ?? "Required")
                    .accessibilityLabel(done ? "Completed" : (item.requirementLabel ?? "Required"))
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.type == "ExternalUrl" ? "Link" : item.type, item.title]
        if let due = details?.dueAt { parts.append("due \(DueFormatter.relative(due))") }
        if let points = details?.pointsPossible, points > 0 { parts.append("\(DueFormatter.points(points)) points") }
        if item.isLocked { parts.append("locked") }
        return parts.joined(separator: ", ")
    }

    private func open() {
        if let link = item.externalLink {
            NSWorkspace.shared.open(link)
        } else if let route = item.route {
            session.path.append(route)
        } else if let raw = item.htmlUrl, let url = URL(string: raw) {
            app.openLink(url)
        }
    }
}
