import SwiftUI
import ThubanCanvasCore

/// Every file in the course as one flat, searchable, sortable list (kind, name, folder, size, date), optionally
/// grouped by folder. Files that are only reachable through modules (the Files tab is disabled in several of the
/// user's courses) are listed under "Files in modules".
struct FilesView: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var scale
    @Bindable var session: CourseSession
    @State private var query = ""
    @State private var sort: FileSort = .recent
    @State private var groupByFolder = false

    enum FileSort: String, CaseIterable, Hashable {
        case recent, name, size, folder
        var label: String {
            switch self {
            case .recent: return "Recent"
            case .name: return "Name"
            case .size: return "Size"
            case .folder: return "Folder"
            }
        }
    }

    private var folders: [CanvasID: Folder] {
        Dictionary((session.folders.value ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var files: [CanvasFile] { session.files.value ?? [] }

    /// Module file items not already in the files list.
    private var moduleOnly: [ModuleItem] {
        let known = Set(files.map(\.id))
        return session.moduleFileItems.filter { !known.contains($0.contentId ?? -1) }
    }

    private var hasNothing: Bool {
        files.isEmpty && moduleOnly.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.files.isLoading && !session.files.hasValue && !session.files.hasAttempted {
                LoadingView()
            } else if hasNothing {
                if session.files.unavailable {
                    EmptyState(title: "Files are not available", message: "Your instructor has not enabled the Files tab for this course, and no module links to a file.")
                } else if let error = session.files.error, !session.files.hasValue {
                    EmptyState(title: "Couldn’t load files", message: error.localizedDescription) {
                        Button("Try again") { Task { await session.loadFiles(force: true) } }.buttonStyle(.thubanSecondary)
                    }
                } else if session.files.hasAttempted || session.modules.hasAttempted {
                    EmptyState(title: "No files", message: "Nothing has been uploaded to this course yet.")
                } else {
                    LoadingView()
                }
            } else {
                if let error = session.files.error, session.files.hasValue {
                    OfflineBanner(text: "Showing saved data — \(error.localizedDescription)", retry: { await session.loadFiles(force: true) })
                }
                toolbar
                list
            }
        }
        .task(id: session.id) {
            async let files: Void = session.loadFiles()
            async let modules: Void = loadModuleFiles()
            _ = await (files, modules)
        }
    }

    /// Modules are the only route to files in courses whose Files tab is off.
    private func loadModuleFiles() async {
        guard session.course.hasTab("modules") else { return }
        await session.loadModules()
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            SearchField(text: $query, placeholder: "Search files")
                .frame(maxWidth: 300)
                .accessibilityLabel("Search files")
            Text(countLabel)
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
                .monospacedDigit()
            Spacer()
            SegmentedPicker(selection: $sort, options: FileSort.allCases.map { SegmentOption($0, $0.label) }, segmentHeight: 24)
                .accessibilityLabel("Sort files")
            SymbolToggleChip(label: "Group by folder", symbol: "folder", isOn: $groupByFolder)
                .disabled(files.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: 1240, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countLabel: String {
        let total = files.count + moduleOnly.count
        let size = files.compactMap(\.size).reduce(0, +)
        var text = total == 1 ? "1 file" : "\(total) files"
        if size > 0 { text += " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
        return text
    }

    private var list: some View {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let visible = sorted(needle.isEmpty ? files : files.filter { matches($0, needle) })
        let moduleFiles = needle.isEmpty ? moduleOnly : moduleOnly.filter { ($0.contentDetails?.displayName ?? $0.title).localizedCaseInsensitiveContains(needle) }
        return Group {
            if visible.isEmpty && moduleFiles.isEmpty {
                EmptyState(title: "No matches", message: "No file name contains “\(needle)”.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if groupByFolder {
                            ForEach(grouped(visible), id: \.path) { group in
                                SectionHeader(group.path, count: group.files.count)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 8)
                                ForEach(group.files) { file in row(file) }
                            }
                        } else {
                            ForEach(visible) { file in row(file) }
                        }
                        if !moduleFiles.isEmpty {
                            SectionHeader("Files in modules", count: moduleFiles.count)
                                .padding(.horizontal, 4)
                                .padding(.top, visible.isEmpty ? 0 : 12)
                            ForEach(moduleFiles) { item in
                                ModuleFileRow(item: item, scale: scale) {
                                    if let id = item.contentId { session.path.append(.file(id)) }
                                }
                            }
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

    private func row(_ file: CanvasFile) -> some View {
        FileRow(file: file, folderPath: groupByFolder ? nil : folderPath(for: file), scale: scale) {
            session.path.append(.file(file.id))
        }
    }

    private func folderPath(for file: CanvasFile) -> String? {
        guard let id = file.folderId, let folder = folders[id] else { return nil }
        let path = folder.displayPath
        return path == "Course files" ? nil : path
    }

    private func matches(_ file: CanvasFile, _ needle: String) -> Bool {
        file.displayName.localizedCaseInsensitiveContains(needle)
            || (file.filename?.localizedCaseInsensitiveContains(needle) ?? false)
            || (folderPath(for: file)?.localizedCaseInsensitiveContains(needle) ?? false)
    }

    private func sorted(_ list: [CanvasFile]) -> [CanvasFile] {
        switch sort {
        case .recent:
            return list.sorted { ($0.displayDate ?? .distantPast) > ($1.displayDate ?? .distantPast) }
        case .name:
            return list.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .size:
            return list.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .folder:
            return list.sorted { a, b in
                let pa = folderPath(for: a) ?? "", pb = folderPath(for: b) ?? ""
                if pa != pb { return pa.localizedStandardCompare(pb) == .orderedAscending }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            }
        }
    }

    private func grouped(_ list: [CanvasFile]) -> [(path: String, files: [CanvasFile])] {
        var order: [String] = []
        var buckets: [String: [CanvasFile]] = [:]
        for file in list {
            let path = folderPath(for: file) ?? "Course files"
            if buckets[path] == nil { order.append(path) }
            buckets[path, default: []].append(file)
        }
        return order.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { ($0, buckets[$0] ?? []) }
    }
}

// MARK: - Rows

private struct FileRow: View {
    @Environment(\.thubanTheme) private var theme
    var file: CanvasFile
    var folderPath: String?
    var scale: Double
    var action: () -> Void

    var body: some View {
        ListRowCard(action: action) {
            HStack(spacing: 12) {
                Image(systemName: file.kindSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(file.lockedForUser == true ? theme.inkFaintColor : theme.brassInkColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayName)
                        .font(ThubanFont.scaled(14, scale: scale, weight: .medium))
                        .foregroundStyle(file.lockedForUser == true ? theme.inkDimColor : theme.inkColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let folderPath {
                        HStack(spacing: 4) {
                            Image(systemName: "folder").font(.system(size: 10, weight: .semibold))
                            Text(folderPath).lineLimit(1).truncationMode(.middle)
                        }
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkFaintColor)
                    }
                }
                Spacer(minLength: 12)
                if file.lockedForUser == true {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                        .help(file.lockExplanation ?? "Locked")
                        .accessibilityLabel(file.lockExplanation ?? "Locked")
                }
                MetaText(file.sizeLabel ?? "—", faint: true)
                    .frame(width: 64, alignment: .trailing)
                MetaText(file.displayDate.map { ContentDates.short($0) } ?? "")
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .accessibilityLabel("\(file.displayName), \(file.sizeLabel ?? "unknown size")\(file.lockedForUser == true ? ", locked" : "")")
    }
}

/// A file that is only known through a module item.
private struct ModuleFileRow: View {
    @Environment(\.thubanTheme) private var theme
    var item: ModuleItem
    var scale: Double
    var action: () -> Void

    private var name: String { item.contentDetails?.displayName ?? item.title }

    var body: some View {
        ListRowCard(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isLocked ? theme.inkFaintColor : theme.brassInkColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(ThubanFont.scaled(14, scale: scale, weight: .medium))
                        .foregroundStyle(item.isLocked ? theme.inkDimColor : theme.inkColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.title != name {
                        Text(item.title).font(ThubanFont.small).foregroundStyle(theme.inkFaintColor).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if item.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                        .help(item.contentDetails?.lockExplanation ?? "Locked")
                        .accessibilityLabel(item.contentDetails?.lockExplanation ?? "Locked")
                }
                if let unlock = item.contentDetails?.unlockAt, unlock > Date() {
                    MetaText("Unlocks \(DueFormatter.relative(unlock))")
                }
            }
        }
        .accessibilityLabel(name)
    }
}
