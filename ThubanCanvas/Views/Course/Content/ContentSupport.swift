import AppKit
import SwiftUI
import ThubanCanvasCore

// MARK: - Dates

/// Short date strings for "updated" / "posted" meta lines (no time; the year only when it differs).
enum ContentDates {
    static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    static func updated(_ date: Date?) -> String? {
        date.map { "Updated \(short($0))" }
    }
}

// MARK: - Module items

extension ModuleItem {
    /// SF Symbol for the item type.
    var symbol: String {
        switch type {
        case "File": return "doc"
        case "Page": return "doc.text"
        case "Assignment": return "checklist"
        case "Quiz": return "questionmark.circle"
        case "Discussion": return "bubble.left"
        case "ExternalUrl": return "link"
        case "ExternalTool": return "app.badge"
        default: return "minus"
        }
    }

    var isSubHeader: Bool { type == "SubHeader" }
    var isLocked: Bool { contentDetails?.lockedForUser == true }

    /// "Must view", "Must submit", "Must score 8", "Must contribute", "Must mark done".
    var requirementLabel: String? {
        guard let requirement = completionRequirement else { return nil }
        switch requirement.type {
        case "must_view": return "Must view"
        case "must_submit": return "Must submit"
        case "must_contribute": return "Must contribute"
        case "must_mark_done": return "Must mark done"
        case "min_score": return "Must score \(DueFormatter.points(requirement.minScore))"
        default: return "Required"
        }
    }

    /// The in-app route a click produces; nil for sub-headers, plain external URLs (opened in the browser) and
    /// items missing their content id.
    var route: CourseRoute? {
        switch type {
        case "File": return contentId.map { .file($0) }
        case "Page": return pageUrl.map { .page(slug: $0) }
        case "Assignment": return contentId.map { .assignment($0) }
        case "Quiz": return contentId.map { .quiz($0) }
        case "Discussion": return contentId.map { .discussion($0) }
        case "ExternalTool": return (htmlUrl ?? url).flatMap { URL(string: $0) }.map { .externalURL($0) }
        default: return nil
        }
    }

    /// The browser URL for an `ExternalUrl` item.
    var externalLink: URL? {
        guard type == "ExternalUrl", let raw = externalUrl else { return nil }
        return URL(string: raw)
    }
}

extension Module {
    var isCompleted: Bool { state == "completed" }
    var isLocked: Bool { state == "locked" }
}

// MARK: - Files

extension CanvasFile {
    /// SF Symbol for the file kind (Canvas `mime_class`, else the content type / extension).
    var kindSymbol: String {
        switch resolvedKind {
        case "pdf": return "doc.richtext"
        case "image": return "photo"
        case "doc": return "doc.text"
        case "ppt": return "rectangle.stack"
        case "xls": return "tablecells"
        case "zip": return "doc.zipper"
        case "video": return "film"
        case "audio": return "waveform"
        case "text", "code": return "doc.plaintext"
        case "html": return "globe"
        default: return "doc"
        }
    }

    /// Normalized kind: Canvas's `mime_class` when present, else derived from the content type or extension.
    var resolvedKind: String {
        if let mimeClass, !mimeClass.isEmpty { return mimeClass }
        let type = (contentType ?? "").lowercased()
        if type == "application/pdf" { return "pdf" }
        if type.hasPrefix("image/") { return "image" }
        if type.hasPrefix("video/") { return "video" }
        if type.hasPrefix("audio/") { return "audio" }
        if type.hasPrefix("text/") { return "text" }
        switch (filename ?? displayName).split(separator: ".").last.map({ $0.lowercased() }) ?? "" {
        case "pdf": return "pdf"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tif", "tiff", "bmp": return "image"
        case "ppt", "pptx", "key": return "ppt"
        case "doc", "docx", "pages", "rtf": return "doc"
        case "xls", "xlsx", "csv", "numbers": return "xls"
        case "zip", "gz", "tar", "7z": return "zip"
        case "txt", "md", "markdown": return "text"
        case "swift", "py", "c", "cpp", "h", "m", "java", "js", "json", "xml", "yml", "yaml", "sh": return "code"
        default: return "file"
        }
    }

    /// "PDF", "Slides", "Document" … for eyebrows.
    var kindLabel: String {
        switch resolvedKind {
        case "pdf": return "PDF"
        case "image": return "Image"
        case "doc": return "Document"
        case "ppt": return "Slides"
        case "xls": return "Spreadsheet"
        case "zip": return "Archive"
        case "video": return "Video"
        case "audio": return "Audio"
        case "text": return "Text"
        case "code": return "Source"
        case "html": return "Web page"
        default: return "File"
        }
    }

    var sizeLabel: String? {
        size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }

    /// The date shown in lists: updated (what Canvas sorts by), else modified, else created.
    var displayDate: Date? { updatedAt ?? modifiedAt ?? createdAt }
}

extension Folder {
    /// "course files/Week 1" → "Week 1"; the root folder → "Course files".
    var displayPath: String {
        let path = fullName ?? name
        let trimmed = path.hasPrefix("course files") ? String(path.dropFirst("course files".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : path
        return trimmed.isEmpty ? "Course files" : trimmed
    }
}

// MARK: - Session helpers

extension CourseSession {
    /// File items referenced from modules (the only way to reach PDFs when the Files tab is disabled), one per file.
    var moduleFileItems: [ModuleItem] {
        var seen = Set<CanvasID>()
        return (modules.value ?? []).flatMap { $0.items ?? [] }.filter { item in
            guard item.type == "File", let id = item.contentId else { return false }
            return seen.insert(id).inserted
        }
    }

    /// `https://host/courses/<id>/<path>`
    func canvasURL(_ path: String) -> URL? {
        URL(string: "\(app.host)/courses/\(id)/\(path)")
    }

    /// Teachers as shown in the overview header.
    var teachers: [Teacher] { course.teachers ?? [] }
}

// MARK: - Small controls

/// A `ToggleChip` for SF Symbols (the icon set has no folder / list glyphs).
struct SymbolToggleChip: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var symbol: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(label)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? theme.brassInkColor : theme.inkDimColor)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                isOn ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear),
                in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(isOn ? theme.accentColor : theme.line2Color, lineWidth: ThubanMetrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .help(label)
    }
}

/// A row inside a grouped card: hover highlight, hairline above (except the first), keyboard-reachable Button.
struct CardRow<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var isFirst: Bool
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    init(isFirst: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.isFirst = isFirst
        self.action = action
        self.content = content
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .onHover { hovering = $0 }
    }

    private var row: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && action != nil ? theme.panel2Color : .clear)
            .overlay(alignment: .top) {
                if !isFirst { Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline).padding(.leading, 14) }
            }
            .contentShape(Rectangle())
    }
}

/// A subtle meta text used in dense rows.
struct MetaText: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var faint: Bool = false

    init(_ text: String, faint: Bool = false) {
        self.text = text
        self.faint = faint
    }

    var body: some View {
        Text(text)
            .font(ThubanFont.small)
            .foregroundStyle(faint ? theme.inkFaintColor : theme.inkDimColor)
            .lineLimit(1)
            .monospacedDigit()
    }
}
