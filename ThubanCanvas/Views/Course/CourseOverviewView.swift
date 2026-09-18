import SwiftUI
import ThubanCanvasCore

/// The course front door — the same shape for every course: header (image, name, code, term, teachers, quick
/// links), then three columns: what is due in the next two weeks, the latest announcements, and the grade with
/// its group breakdown.
struct CourseOverviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OverviewHeader(session: session)
                HStack(alignment: .top, spacing: 16) {
                    UpNextColumn(session: session)
                    AnnouncementsColumn(session: session)
                    GradeColumn(session: session)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: session.id) {
            CourseContentSmoke.registerIfNeeded(app: app)
            async let groups: Void = session.loadGroups()
            async let announcements: Void = session.loadAnnouncements()
            _ = await (groups, announcements)
        }
    }
}

// MARK: - Header

private struct OverviewHeader: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession

    private var course: Course { session.course }

    private var metaLine: String {
        var parts: [String] = []
        let code = session.shortCode
        if !code.isEmpty { parts.append(code) }
        if let term = course.term?.name, term != "Default Term" { parts.append(term) }
        return parts.joined(separator: " · ")
    }

    private var quickLinks: [CourseSection] {
        [.modules, .files, .syllabus, .people].filter { session.availableSections.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let raw = course.imageDownloadUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        theme.panel2Color
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.displayName)
                        .font(ThubanFont.display(28))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(2)
                    if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(ThubanFont.body(14))
                            .foregroundStyle(theme.inkDimColor)
                    }
                    if !session.teachers.isEmpty {
                        TeacherLine(teachers: session.teachers)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 12)
                if !quickLinks.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(quickLinks, id: \.self) { section in
                            Button {
                                session.path = []
                                session.section = section
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: section.symbol).font(.system(size: 13, weight: .semibold))
                                    Text(section.label)
                                }
                            }
                            .buttonStyle(GhostButtonStyle(height: 32, tinted: true, horizontalPadding: 10))
                            .accessibilityLabel("Open \(section.label)")
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

/// Up to four teachers with avatars, then "and N more".
private struct TeacherLine: View {
    @Environment(\.thubanTheme) private var theme
    var teachers: [Teacher]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(teachers.prefix(4)) { teacher in
                HStack(spacing: 7) {
                    AvatarView(name: teacher.displayName, url: teacher.avatarImageUrl, size: 26)
                    Text(teacher.displayName)
                        .font(ThubanFont.body(13, weight: .medium))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Teacher \(teacher.displayName)")
            }
            if teachers.count > 4 {
                Text("and \(teachers.count - 4) more")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
            }
        }
    }
}

// MARK: - Columns

/// A titled column card shared by the three overview columns.
private struct OverviewColumn<Accessory: View, Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var count: Int?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, count: Int? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, count: count, accessory: accessory)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .thubanPanel(padding: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ColumnNote: View {
    @Environment(\.thubanTheme) private var theme
    var text: String

    var body: some View {
        Text(text)
            .font(ThubanFont.body(14))
            .foregroundStyle(theme.inkDimColor)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ColumnSpinner: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading…").font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Due in the next 14 days, soonest first, at most six.
private struct UpNextColumn: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var scale
    @Bindable var session: CourseSession

    private var items: [WorkItem] { Array(WorkItemBuilder.upcoming(session.workItems, within: 14).prefix(6)) }

    var body: some View {
        OverviewColumn("Up next", count: items.isEmpty ? nil : items.count, accessory: {
            Button("All assignments") { session.path = []; session.section = .assignments }
                .buttonStyle(GhostButtonStyle(height: 22, tinted: true, horizontalPadding: 6))
                .font(ThubanFont.small)
                .accessibilityLabel("Open Assignments")
        }) {
            if session.groups.isLoading && !session.groups.hasValue {
                ColumnSpinner()
            } else if let error = session.groups.error, !session.groups.hasValue {
                ColumnNote(text: error.localizedDescription)
            } else if items.isEmpty {
                ColumnNote(text: "Nothing due in the next two weeks.")
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    CardRow(isFirst: index == 0, action: { open(item) }) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(for: item))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.brassInkColor)
                                .frame(width: 18)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(ThubanFont.scaled(14, scale: scale, weight: .medium))
                                    .foregroundStyle(theme.inkColor)
                                    .lineLimit(2)
                                MetaText(metaLine(for: item))
                            }
                            Spacer(minLength: 0)
                            if let chip = Chip.status(item) { chip }
                        }
                    }
                    .accessibilityLabel(accessibilityLabel(for: item))
                }
            }
        }
    }

    /// "Tomorrow · 11:59 PM · in 1 d · 20 pts"
    private func metaLine(for item: WorkItem) -> String {
        var parts: [String] = []
        if let due = item.dueAt { parts += [DueFormatter.relative(due), DueFormatter.countdown(due)] }
        if let points = item.pointsPossible, points > 0 { parts.append("\(DueFormatter.points(points)) pts") }
        return parts.joined(separator: " · ")
    }

    private func symbol(for item: WorkItem) -> String {
        switch item.kind {
        case .quiz: return "questionmark.circle"
        case .discussion: return "bubble.left"
        case .event: return "calendar"
        default: return "checklist"
        }
    }

    private func accessibilityLabel(for item: WorkItem) -> String {
        var text = item.title
        if let due = item.dueAt { text += ", due \(DueFormatter.relative(due))" }
        return text
    }

    private func open(_ item: WorkItem) {
        if let assignment = item.assignmentId {
            session.path.append(.assignment(assignment))
        } else if let quiz = item.quizId {
            session.path.append(.quiz(quiz))
        }
    }
}

/// The three most recent announcements with a plain-text preview.
private struct AnnouncementsColumn: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var scale
    @Bindable var session: CourseSession

    private var items: [DiscussionTopic] {
        Array((session.announcements.value ?? []).sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }.prefix(3))
    }

    var body: some View {
        OverviewColumn("Latest announcements", accessory: {
            if session.availableSections.contains(.announcements) {
                Button("All") { session.path = []; session.section = .announcements }
                    .buttonStyle(GhostButtonStyle(height: 22, tinted: true, horizontalPadding: 6))
                    .font(ThubanFont.small)
                    .accessibilityLabel("Open Announcements")
            }
        }) {
            if session.announcements.isLoading && !session.announcements.hasValue {
                ColumnSpinner()
            } else if session.announcements.unavailable {
                ColumnNote(text: "Announcements are not available in this course.")
            } else if let error = session.announcements.error, !session.announcements.hasValue {
                ColumnNote(text: error.localizedDescription)
            } else if items.isEmpty {
                ColumnNote(text: "No announcements yet.")
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, topic in
                    CardRow(isFirst: index == 0, action: { session.path.append(.discussion(topic.id)) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if topic.readState == "unread" {
                                    Circle().fill(theme.accentColor).frame(width: 6, height: 6)
                                        .accessibilityLabel("Unread")
                                }
                                Text(topic.title)
                                    .font(ThubanFont.scaled(14, scale: scale, weight: .medium))
                                    .foregroundStyle(theme.inkColor)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                if let posted = topic.postedAt { MetaText(ContentDates.short(posted), faint: true) }
                            }
                            let preview = CanvasHTML.plainText(topic.message, limit: 140)
                            if !preview.isEmpty {
                                Text(preview)
                                    .font(ThubanFont.scaled(13, scale: scale))
                                    .foregroundStyle(theme.inkDimColor)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .accessibilityLabel("Announcement: \(topic.title)")
                }
            }
        }
    }
}

/// The current score and letter, then each assignment group's weight and percent.
private struct GradeColumn: View {
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession

    var body: some View {
        OverviewColumn("Grade", accessory: {
            Button("Details") { session.path = []; session.section = .grades }
                .buttonStyle(GhostButtonStyle(height: 22, tinted: true, horizontalPadding: 6))
                .font(ThubanFont.small)
                .accessibilityLabel("Open Grades")
        }) {
            if session.groups.isLoading && !session.groups.hasValue && session.displayScore == nil {
                ColumnSpinner()
            } else if session.course.hideFinalGrades == true && session.displayScore == nil {
                ColumnNote(text: "Your instructor hides the course total.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(session.displayScore.map { DueFormatter.percent($0) } ?? "—")
                            .font(ThubanFont.display(34))
                            .foregroundStyle(session.displayScore == nil ? theme.inkFaintColor : theme.inkColor)
                            .monospacedDigit()
                        if let letter = session.displayLetter { Chip.letter(letter) }
                        if !session.whatIf.isEmpty { Chip("What-if", kind: .warn) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, session.displayScore == nil ? 6 : 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(session.displayScore.map { "Current grade \(DueFormatter.percent($0))" } ?? "No grade yet")
                    if session.displayScore == nil {
                        Text("No graded work yet.")
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.inkDimColor)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                    let groups = (session.computedGrade?.groups ?? []).filter { $0.possible > 0 || ($0.weight ?? 0) > 0 }
                    if !groups.isEmpty {
                        let weighted = session.computedGrade?.weighted ?? false
                        ForEach(groups) { group in
                            GroupRow(group: group, weighted: weighted)
                        }
                    }
                }
            }
        }
    }

    private struct GroupRow: View {
        @Environment(\.thubanTheme) private var theme
        var group: CourseGrade.GroupResult
        var weighted: Bool

        var body: some View {
            HStack(spacing: 10) {
                Text(group.name)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if weighted, let weight = group.weight {
                    MetaText("\(DueFormatter.points(weight))%", faint: true)
                        .frame(width: 44, alignment: .trailing)
                }
                Text(group.percent.map { DueFormatter.percent($0) } ?? "—")
                    .font(ThubanFont.small.weight(.medium))
                    .foregroundStyle(group.percent == nil ? theme.inkFaintColor : theme.inkColor)
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline).padding(.leading, 14) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group.name): \(group.percent.map { DueFormatter.percent($0) } ?? "no score")\(weighted && group.weight != nil ? ", weight \(DueFormatter.points(group.weight)) percent" : "")")
        }
    }
}
