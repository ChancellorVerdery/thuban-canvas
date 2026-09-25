import SwiftUI
import ThubanCanvasCore

/// Courses tab: starred courses with score + letter and what's next, search, a Grades & GPA group (past semesters,
/// credits and scale) and local nickname/hide via long press.
struct CoursesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var query = ""
    @State private var organizing = false
    @State private var renaming: CourseSession?
    @State private var nickname = ""

    var body: some View {
        RootScreen("Courses", eyebrow: eyebrow) {
            EmptyView()
        } trailing: {
            IconButton(systemName: "line.3.horizontal.decrease", label: "Sort and hide courses") { organizing = true }
        } content: {
            VStack(alignment: .leading, spacing: IOSMetrics.sectionGap) {
                SearchBar(text: $query, placeholder: "Search courses").padding(.top, 14)
                courseList
                gradesGroup
                if !app.hiddenSessions.isEmpty { hiddenGroup }
            }
            .gutter()
        }
        .refreshable { await app.refreshAll() }
        .sheet(isPresented: $organizing) { CourseOrganizerSheet() }
        .alert("Nickname", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nickname", text: $nickname)
            Button("Save") {
                if let session = renaming {
                    let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                    app.updatePreferences(for: session.id) { $0.nickname = trimmed.isEmpty ? nil : trimmed }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Shown in place of the course code on this device only.")
        }
        .task(id: app.courses.map(\.id)) { await app.loadHomeResources() }
    }

    private var eyebrow: String {
        let count = app.courses.count
        let starred = "\(count) starred in Canvas"
        if let term = app.termName { return "\(term) · \(starred)" }
        return starred
    }

    private var filtered: [CourseSession] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return app.orderedSessions }
        return app.orderedSessions.filter {
            $0.displayName.localizedCaseInsensitiveContains(text) || $0.shortTitle.localizedCaseInsensitiveContains(text)
                || ($0.teacherName ?? "").localizedCaseInsensitiveContains(text)
        }
    }

    @ViewBuilder
    private var courseList: some View {
        if app.orderedSessions.isEmpty {
            if app.isLoadingCourses { LoadingCard(text: "Loading your courses…") }
            else { Card { EmptyNote(systemName: "star", text: "Star courses in Canvas to see them here.") } }
        } else if filtered.isEmpty {
            Card { EmptyNote(systemName: "magnifyingglass", text: "No course matches “\(query)”.") }
        } else {
            Card {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { RowDivider(inset: 38) }
                    Button { app.push(.course(session.id)) } label: { CourseRow(session: session) }
                        .buttonStyle(RowPressStyle())
                        .contextMenu {
                            Button { nickname = session.preferences.nickname ?? ""; renaming = session } label: { Label("Nickname…", systemImage: "pencil") }
                            Button { app.setHidden(true, course: session.id) } label: { Label("Hide on this device", systemImage: "eye.slash") }
                            if let url = URL(string: "\(app.host)/courses/\(session.id)") {
                                Button { app.openInSafari(url) } label: { Label("Open in Canvas", systemImage: "safari") }
                            }
                        }
                }
            }
        }
    }

    private var gradesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Grades & GPA")
            Card {
                Button { app.push(.pastSemesters) } label: {
                    settingsRow("Past semesters", value: pastSummary)
                }
                .buttonStyle(RowPressStyle())
                RowDivider()
                Button { app.settingsPage = .grades; app.showingSettings = true } label: {
                    settingsRow("Credits & letter scale", value: scaleSummary)
                }
                .buttonStyle(RowPressStyle())
            }
            Text("Star a course in Canvas to add it here. Long-press a course to give it a nickname or hide it.")
                .tFont(.footnote)
                .foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    private var hiddenGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Hidden on this device")
            Card {
                ForEach(Array(app.hiddenSessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Text(session.displayName).tFont(.body).foregroundStyle(theme.inkDimColor).lineLimit(1)
                        Spacer()
                        Button("Show") { app.setHidden(false, course: session.id) }
                            .tFont(.text(15, .semibold)).foregroundStyle(theme.brassInkColor).frame(minHeight: 44)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: IOSMetrics.rowHeight)
                }
            }
        }
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).tFont(.body).foregroundStyle(theme.inkColor)
            Spacer(minLength: 8)
            Text(value).tFont(.secondary).foregroundStyle(theme.inkDimColor).lineLimit(1)
            RowChevron()
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(minHeight: IOSMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private var pastSummary: String {
        let past = app.settings.pastSemesters
        guard !past.isEmpty else { return "None yet" }
        let gpa = GPACalculator.compute(courses: [], past: past).cumulative
        return "\(past.count) term\(past.count == 1 ? "" : "s") · \(GPACalculator.format(gpa))"
    }

    private var scaleSummary: String {
        app.settings.letterScale.scheme.cutoffs.filter { $0.minimum > 0 }.prefix(3)
            .map { "\($0.letter) \(PointsText.short($0.minimum))" }.joined(separator: " · ")
    }
}

/// One course: dot, code, name, "Next: … · Tomorrow", score + letter.
struct CourseRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession

    var body: some View {
        HStack(spacing: 12) {
            CourseDot(color: app.tint(for: session.id), size: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.shortTitle).tFont(.mono(12, .semibold)).foregroundStyle(theme.inkDimColor)
                Text(session.course.name).tFont(.bodyStrong).foregroundStyle(theme.inkColor).lineLimit(2).multilineTextAlignment(.leading)
                nextLine.tFont(.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.displayScore.map { String(format: "%.1f", $0) } ?? "—")
                    .tFont(.display(20)).foregroundStyle(session.displayScore == nil ? theme.inkFaintColor : theme.inkColor).monospacedDigit()
                if let letter = session.displayLetter { LetterChip(letter: letter) }
            }
            RowChevron()
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 78)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var nextLine: Text {
        let items = session.workItems
        let overdue = WorkItemBuilder.overdue(items, dismissed: app.settings.dismissedOverdue).count
        let next = WorkItemBuilder.upcoming(items).first
        var text = Text("")
        if overdue > 0 {
            text = Text("\(overdue) overdue").fontWeight(.semibold).foregroundColor(theme.negTextColor)
            if let next, let due = next.dueAt { text = text + Text(" · \(next.title) \(DueFormatter.compactDay(due))") }
            return text
        }
        guard let next, let due = next.dueAt else {
            return session.groups.hasValue ? Text("Nothing due soon") : Text(session.teacherName ?? " ")
        }
        let day = DueFormatter.compactDay(due)
        let soon = due.timeIntervalSinceNow < 48 * 3_600
        return Text("Next: \(next.title) · ") + Text(day).fontWeight(soon ? .semibold : .regular).foregroundColor(soon ? theme.brassInkColor : theme.inkDimColor)
    }
}

/// Reorder and hide courses (local only; the Canvas star is untouched).
struct CourseOrganizerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.allOrderedSessions) { session in
                        HStack(spacing: 12) {
                            CourseDot(color: app.tint(for: session.id), size: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.shortTitle).tFont(.mono(12, .semibold)).foregroundStyle(theme.inkDimColor)
                                Text(session.course.name).tFont(.body).foregroundStyle(session.preferences.hidden ? theme.inkFaintColor : theme.inkColor).lineLimit(1)
                            }
                            Spacer()
                            ThubanSwitch(isOn: Binding(get: { !session.preferences.hidden }, set: { app.setHidden(!$0, course: session.id) }),
                                         label: "Show \(session.shortTitle)")
                        }
                        .listRowBackground(theme.panelColor)
                    }
                    .onMove { app.moveCourses(from: $0, to: $1) }
                } footer: {
                    Text("Drag to reorder. Hidden courses keep their star in Canvas but leave Home, Calendar and reminders on this device.")
                        .tFont(.footnote).foregroundStyle(theme.inkDimColor)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(theme.bgColor)
            .navigationTitle("Sort and hide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold).foregroundStyle(theme.brassInkColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
