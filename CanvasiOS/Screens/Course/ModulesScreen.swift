import SwiftUI
import ThubanCanvasCore

struct ModulesScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen("Modules", back: back) {
                ModulesContent(session: session)
            }
            .refreshable { await session.loadModules(force: true); await session.loadGroups(force: true) }
        }
    }
}

/// Modules: the current week first (open, with progress), the previous and next weeks, then the rest. Items show
/// their completion requirement ("Viewed", "Must submit", "Must score 8") and done / not done / locked.
struct ModulesContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    @State private var query = ""
    @State private var expanded: Set<CanvasID> = []
    @State private var seeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchBar(text: $query, placeholder: "Search modules").padding(.top, 6)
            content
        }
        .gutter()
        .task(id: session.id) {
            await session.loadModules()
            await session.loadGroups()
            seedExpansion()
        }
    }

    @ViewBuilder
    private var content: some View {
        let resource = session.modules
        if let modules = resource.value {
            if modules.isEmpty {
                Card { EmptyNote(systemName: "list.bullet.rectangle", text: "No modules have been published.") }
            } else {
                let ordered = focusOrder(modules)
                let text = query.trimmingCharacters(in: .whitespaces)
                let visible = text.isEmpty ? ordered : ordered.filter { module in
                    module.name.localizedCaseInsensitiveContains(text) || (module.items ?? []).contains { $0.title.localizedCaseInsensitiveContains(text) }
                }
                if visible.isEmpty {
                    Card { EmptyNote(systemName: "magnifyingglass", text: "Nothing matches “\(text)”.") }
                }
                ForEach(visible) { module in
                    ModuleCard(session: session, module: module, isCurrent: module.id == currentId(modules),
                               isOpen: !text.isEmpty || expanded.contains(module.id), query: text) {
                        if expanded.contains(module.id) { expanded.remove(module.id) } else { expanded.insert(module.id) }
                    }
                }
            }
        } else if resource.isLoading || !resource.hasAttempted {
            LoadingCard(text: "Loading modules…")
        } else if resource.unavailable {
            Card { EmptyNote(systemName: "lock", text: "Modules are turned off in this course.") }
        } else if let error = resource.error {
            Card { EmptyNote(systemName: "wifi.exclamationmark", text: error.localizedDescription, tint: theme.negTextColor) }
        }
    }

    private func currentId(_ modules: [Module]) -> CanvasID? {
        session.currentModuleIndex.map { modules[$0].id }
    }

    /// Current, previous, next, then earlier (most recent first) and later modules.
    private func focusOrder(_ modules: [Module]) -> [Module] {
        guard let index = session.currentModuleIndex else { return modules }
        var order = [index]
        if index > 0 { order.append(index - 1) }
        if index + 1 < modules.count { order.append(index + 1) }
        order += (0..<max(0, index - 1)).reversed()
        if index + 2 < modules.count { order += (index + 2)..<modules.count }
        return order.map { modules[$0] }
    }

    private func seedExpansion() {
        guard !seeded, let modules = session.modules.value, let index = session.currentModuleIndex else { return }
        seeded = true
        expanded.insert(modules[index].id)
    }
}

private struct ModuleCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    var module: Module
    var isCurrent: Bool
    var isOpen: Bool
    var query: String
    var toggle: () -> Void

    var body: some View {
        let items = (module.items ?? []).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || module.name.localizedCaseInsensitiveContains(query) }
        Card(border: isCurrent ? theme.line2Color : nil) {
            if isCurrent { currentHeader } else { collapsedHeader }
            if isOpen || isCurrent {
                ForEach(items) { item in
                    Rectangle().fill(theme.lineColor).frame(height: 1)
                    ModuleItemRow(session: session, item: item, moduleLocked: module.state == "locked")
                }
            }
        }
    }

    private var split: (eyebrow: String?, title: String) { ModuleName.split(module.name) }
    private var locked: Bool { module.state == "locked" }

    private var progress: (done: Int, total: Int) {
        let required = (module.items ?? []).filter { $0.completionRequirement != nil }
        return (required.filter { $0.completionRequirement?.completed == true }.count, required.count)
    }

    private var currentHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text([split.eyebrow, "This week"].compactMap { $0 }.joined(separator: " · "))
                    .tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.inkDimColor)
                Spacer(minLength: 4)
                if progress.total > 0 {
                    (Text("\(progress.done)").font(.system(size: 13, design: .monospaced)) + Text(" of ") + Text("\(progress.total)").font(.system(size: 13, design: .monospaced)) + Text(" done"))
                        .tFont(.footnote).foregroundStyle(theme.inkDimColor)
                }
            }
            Text(split.title).tFont(.display(20)).foregroundStyle(theme.inkColor)
            if progress.total > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.lineColor)
                        Capsule().fill(theme.signalColor).frame(width: proxy.size.width * CGFloat(progress.done) / CGFloat(max(progress.total, 1)))
                    }
                }
                .frame(height: 4)
                .padding(.top, 6)
                .accessibilityLabel("\(progress.done) of \(progress.total) requirements done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var collapsedHeader: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    if let eyebrow = split.eyebrow {
                        Text(eyebrow).tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9)
                            .foregroundStyle(locked ? theme.inkFaintColor : theme.inkDimColor)
                    }
                    Text(split.title).tFont(.display(18)).foregroundStyle(locked ? theme.inkDimColor : theme.inkColor).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if locked {
                    if let unlock = module.unlockAt { Text("Opens \(DueFormatter.compactDay(unlock))").tFont(.footnote).foregroundStyle(theme.inkFaintColor) }
                    Image(systemName: "lock").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.inkFaintColor).accessibilityLabel("Locked")
                } else if progress.total > 0 {
                    ChipView("\(progress.done) of \(progress.total)", kind: progress.done == progress.total ? .pos : .neutral)
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
    }
}

/// One module item: type tile, title, requirement chip + detail, trailing state.
struct ModuleItemRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    var item: ModuleItem
    var moduleLocked: Bool

    var body: some View {
        if item.type == "SubHeader" {
            Text(item.title).tFont(.micro).foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        } else {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(highlight ? theme.brassInkColor : theme.inkDimColor)
                        .frame(width: 28, height: 28)
                        .background(highlight ? theme.accentTintColor : theme.panel2Color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).tFont(.text(16, .semibold)).foregroundStyle(isLocked ? theme.inkDimColor : theme.inkColor)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let chip = requirementChip { ChipView(chip.text, kind: chip.kind) }
                            detail
                        }
                    }
                    Spacer(minLength: 8)
                    trailing
                }
                .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 8)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(isLocked && item.type != "Assignment")
            .accessibilityElement(children: .combine)
        }
    }

    private var assignment: Assignment? {
        switch item.type {
        case "Assignment": return item.contentId.flatMap { session.assignment($0) }
        case "Quiz": return session.assignments.first { $0.quizId == item.contentId }
        default: return nil
        }
    }

    private var isDone: Bool { item.completionRequirement?.completed == true }
    private var isLocked: Bool { item.contentDetails?.lockedForUser == true || (moduleLocked && !isDone) }
    private var highlight: Bool { item.completionRequirement?.type == "must_submit" && !isDone && !isLocked }

    private var symbol: String {
        switch item.type {
        case "Page": return "doc.text"
        case "File": return "doc"
        case "Assignment": return "checklist"
        case "Quiz": return "questionmark.circle"
        case "Discussion": return "bubble.left.and.bubble.right"
        case "ExternalUrl", "ExternalTool": return "link"
        default: return "circle"
        }
    }

    private var requirementChip: (text: String, kind: ChipKind)? {
        guard let requirement = item.completionRequirement else { return nil }
        switch requirement.type {
        case "must_view": return isDone ? ("Viewed", .pos) : ("Must view", .neutral)
        case "must_submit": return isDone ? ("Submitted", .pos) : ("Must submit", isLocked ? .neutral : .warn)
        case "must_contribute": return isDone ? ("Contributed", .pos) : ("Must contribute", .neutral)
        case "min_score": return isDone ? ("Score met", .pos) : ("Must score \(PointsText.short(requirement.minScore))", .neutral)
        case "must_mark_done": return isDone ? ("Done", .pos) : ("Mark done in Canvas", .neutral)
        default: return nil
        }
    }

    @ViewBuilder
    private var detail: some View {
        let text: String? = {
            if let assignment, let submission = assignment.submission, submission.isGraded {
                let graded = (submission.gradedAt ?? submission.postedAt).map { " · graded \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
                return "\(PointsText.short(submission.score)) / \(PointsText.short(assignment.pointsPossible))\(graded)"
            }
            if isLocked, let unlock = item.contentDetails?.unlockAt { return "Locked until \(DueFormatter.compactDay(unlock))" }
            switch item.type {
            case "Page": return "Page"
            case "File":
                let saved = item.contentId.map { AppModel.isSavedOffline(fileId: $0) } ?? false
                let kind = (item.title as NSString).pathExtension.uppercased()
                return [kind.isEmpty ? "File" : kind, saved ? "saved offline" : nil].compactMap { $0 }.joined(separator: " · ")
            case "ExternalUrl", "ExternalTool": return "Opens in Safari"
            case "Discussion": return "Discussion"
            default: return nil
            }
        }()
        if let due = item.contentDetails?.dueAt ?? assignment?.dueAt, !isLocked, !isDone, assignment?.submission?.isGraded != true, due > Date() {
            Text(DueFormatter.compact(due)).tFont(.text(13, .semibold)).foregroundStyle(theme.brassInkColor).lineLimit(1)
        } else if let text {
            Text(text).tFont(.footnote).foregroundStyle(theme.inkFaintColor).lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isDone {
            Image(systemName: "checkmark.circle").font(.system(size: 20, weight: .regular)).foregroundStyle(theme.posTextColor).accessibilityLabel("Done")
        } else if isLocked {
            Image(systemName: "lock").font(.system(size: 17, weight: .regular)).foregroundStyle(theme.inkFaintColor).accessibilityLabel("Locked")
        } else if item.completionRequirement != nil {
            Image(systemName: "circle").font(.system(size: 20, weight: .regular)).foregroundStyle(theme.line2Color).accessibilityLabel("Not done")
        } else if app.downloadingFile == item.contentId, item.type == "File" {
            ProgressView().tint(theme.brassInkColor)
        } else {
            RowChevron()
        }
    }

    private func open() {
        switch item.type {
        case "Assignment":
            if let id = item.contentId { app.push(.assignment(course: session.id, id: id)) }
        case "Quiz":
            if let assignment { app.push(.assignment(course: session.id, id: assignment.id)) }
            else if let raw = item.htmlUrl, let url = URL(string: raw) { app.openInSafari(url) }
        case "Page":
            if let slug = item.pageUrl { app.push(.page(course: session.id, slug: slug)) }
        case "File":
            if let id = item.contentId { Task { await app.openFile(course: session.id, id: id) } }
        case "Discussion":
            if let id = item.contentId { app.push(.discussion(course: session.id, id: id)) }
        case "ExternalUrl":
            if let raw = item.externalUrl, let url = URL(string: raw) { app.openInSafari(url) }
        default:
            if let raw = item.htmlUrl, let url = URL(string: raw) { app.openInSafari(url) }
        }
    }
}
