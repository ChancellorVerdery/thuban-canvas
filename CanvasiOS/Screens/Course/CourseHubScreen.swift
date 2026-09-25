import SwiftUI
import ThubanCanvasCore

/// The course hub: header, current grade, next up, and the same section list for every course.
struct CourseHubScreen: View {
    @Environment(AppModel.self) private var app
    var courseId: CanvasID
    var back: String

    var body: some View {
        if let session = app.sessions[courseId] {
            PushedScreen(session.shortTitle, back: back) {
                CourseOptionsMenu(session: session)
            } content: {
                CourseHubContent(session: session, showsHeader: true)
            }
            .refreshable { await session.refreshLoaded(); await session.loadHub() }
        } else {
            PushedScreen("Course", back: back) { ScreenMessage(systemName: "questionmark.folder", title: "Course not available") }
        }
    }
}

/// Nickname / hide / open in Canvas (all local except the Safari link).
struct CourseOptionsMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    @State private var renaming = false
    @State private var nickname = ""

    var body: some View {
        Menu {
            Button { nickname = session.preferences.nickname ?? ""; renaming = true } label: { Label("Nickname…", systemImage: "pencil") }
            Button { app.setHidden(true, course: session.id); app.coursesPath.removeAll() } label: { Label("Hide on this device", systemImage: "eye.slash") }
            if let url = URL(string: "\(app.host)/courses/\(session.id)") {
                Button { app.openInSafari(url) } label: { Label("Open in Canvas", systemImage: "safari") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Course options: nickname, hide, open in Canvas")
        .alert("Nickname", isPresented: $renaming) {
            TextField("Nickname", text: $nickname)
            Button("Save") {
                let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                app.updatePreferences(for: session.id) { $0.nickname = trimmed.isEmpty ? nil : trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct CourseHubContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession
    var showsHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader { header }
            gradeCard
            if let next = session.nextUp { nextUp(next) }
            sections
        }
        .padding(.top, showsHeader ? 8 : 16)
        .gutter()
        .task(id: session.id) { await session.loadHub() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow([session.shortTitle, session.sectionLabel, session.course.term?.name].compactMap { $0 }.joined(separator: " · "))
            Text(session.course.name).tFont(.display(28)).foregroundStyle(theme.inkColor).padding(.top, 2).accessibilityAddTraits(.isHeader)
            if let teacher = session.teacherName { Text(teacher).tFont(.secondary).foregroundStyle(theme.inkDimColor) }
        }
    }

    private var gradeCard: some View {
        Button { app.push(.grades(session.id)) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current grade").tFont(.text(11, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(theme.inkDimColor)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(session.displayScore.map { DueFormatter.percent($0) } ?? "—")
                            .tFont(.display(34)).foregroundStyle(session.displayScore == nil ? theme.inkFaintColor : theme.inkColor).monospacedDigit()
                        if let letter = session.displayLetter { LetterChip(letter: letter) }
                    }
                    Text(gradeNote).tFont(.footnote).foregroundStyle(theme.inkDimColor).padding(.top, 2)
                }
                Spacer(minLength: 8)
                RowChevron()
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 14)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens grades")
    }

    private var gradeNote: String {
        guard session.groups.hasValue else { return "Loading assignments…" }
        var parts = ["\(session.gradedCount) of \(session.countedAssignments.count) graded"]
        if let note = session.cutoffNote { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private func nextUp(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Next up")
            Button {
                if let id = item.assignmentId { app.push(.assignment(course: session.id, id: id)) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).tFont(.bodyStrong).foregroundStyle(theme.inkColor).multilineTextAlignment(.leading)
                        if let due = item.dueAt {
                            Text("\(DueFormatter.compact(due)) · \(DueFormatter.friendlyCountdown(due))")
                                .tFont(.text(13, .semibold)).foregroundStyle(theme.brassInkColor)
                        }
                    }
                    Spacer(minLength: 8)
                    if let points = item.pointsPossible { Text("\(PointsText.short(points)) pts").tFont(.mono(13)).foregroundStyle(theme.inkDimColor) }
                }
                .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous).strokeBorder(theme.accentColor, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFadeStyle())
            .accessibilityElement(children: .combine)
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Sections") {
                if let note = session.missingSectionsNote { Text(note).tFont(.footnote).foregroundStyle(theme.inkFaintColor).lineLimit(1) }
            }
            Card {
                ForEach(Array(session.hubSections.enumerated()), id: \.element) { index, section in
                    if index > 0 { RowDivider(inset: 56) }
                    Button { app.push(section.route(session.id)) } label: { sectionRow(section) }
                        .buttonStyle(RowPressStyle())
                }
            }
        }
    }

    private func sectionRow(_ section: HubSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
                .frame(width: 28, height: 28)
                .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(section.label).tFont(.body).foregroundStyle(theme.inkColor)
            Spacer(minLength: 8)
            summary(section)
            RowChevron()
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(minHeight: IOSMetrics.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func summary(_ section: HubSection) -> some View {
        switch section {
        case .modules:
            if let text = session.moduleSummary { value(text) }
        case .assignments:
            if session.groups.hasValue { value(session.dueThisWeekCount == 0 ? "Nothing due this week" : "\(session.dueThisWeekCount) due this week") }
        case .grades:
            if session.newGradeCount > 0 { value("\(session.newGradeCount) new") }
        case .announcements:
            if session.unreadAnnouncementCount > 0 { ChipView("\(session.unreadAnnouncementCount) unread", kind: .warn) }
        case .discussions:
            if let count = session.discussions.value?.count { value("\(count)") }
        case .people:
            if let count = session.people.value?.count { value("\(count)") }
        case .files:
            if let count = session.files.value?.count { value("\(count)") }
        case .pages:
            if let count = session.pages.value?.count { value("\(count)") }
        case .overview, .syllabus:
            EmptyView()
        }
    }

    private func value(_ text: String) -> some View {
        Text(text).tFont(.secondary).foregroundStyle(theme.inkDimColor).lineLimit(1)
    }
}
