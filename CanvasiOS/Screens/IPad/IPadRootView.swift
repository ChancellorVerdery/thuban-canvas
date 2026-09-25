import SwiftUI
import ThubanCanvasCore

/// iPad: a sidebar (Home, Calendar, Inbox, the starred courses, Settings) and a detail stack. A course shows its
/// header, a section bar, and for Assignments a list beside the selected assignment.
struct IPadRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: .constant(.all)) {
            IPadSidebar()
                .navigationSplitViewColumnWidth(300)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NavigationStack(path: $app.ipadPath) {
                detailRoot.routeDestinations()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: app.sidebar) { _, _ in app.ipadPath = [] }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch app.sidebar ?? .home {
        case .home: HomeScreen()
        case .calendar: CalendarScreen()
        case .inbox: InboxScreen()
        case .course(let id):
            if let session = app.sessions[id] { IPadCourseView(session: session) } else { HomeScreen() }
        }
    }
}

extension AppModel {
    /// Title of the iPad detail root (the back title of the first pushed screen).
    var ipadRootTitle: String {
        switch sidebar ?? .home {
        case .home: return "Home"
        case .calendar: return "Calendar"
        case .inbox: return "Inbox"
        case .course(let id): return sessions[id]?.shortTitle ?? "Course"
        }
    }

    /// Switches to a top-level place on either idiom.
    func show(_ tab: MainTab) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            switch tab {
            case .home: sidebar = .home
            case .calendar: sidebar = .calendar
            case .inbox: sidebar = .inbox
            case .courses: if let first = orderedSessions.first { sidebar = .course(first.id) }
            }
            return
        }
        selectedTab = tab
        switch tab {
        case .home: homePath = []
        case .courses: coursesPath = []
        case .calendar: calendarPath = []
        case .inbox: inboxPath = []
        }
    }
}

private struct IPadSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AppArtView(size: 28, theme: theme, ground: theme.panelColor)
                Text("Thuban Canvas").tFont(.display(22)).foregroundStyle(theme.inkColor)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    item(.home, symbol: "house", title: "Home")
                    item(.calendar, symbol: "calendar", title: "Calendar") {
                        let due = WorkItemBuilder.upcoming(app.allWorkItems, within: 7).count
                        if due > 0 { Text("\(due) due").tFont(.mono(13)).foregroundStyle(theme.inkDimColor) }
                    }
                    item(.inbox, symbol: "tray", title: "Inbox") {
                        if app.unreadInbox > 0 {
                            Text("\(app.unreadInbox)").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.onAccentColor)
                                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22).background(theme.accentColor, in: Capsule())
                        }
                    }
                    Eyebrow(["Courses", app.termName].compactMap { $0 }.joined(separator: " · ")).padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 6)
                    ForEach(app.orderedSessions) { session in courseItem(session) }
                }
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(theme.lineColor).frame(height: 1)
            Button { app.showingSettings = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 22)
                    Text("Settings").tFont(.text(16))
                    Spacer()
                    Circle().fill(app.isConnected ? theme.signalColor : theme.negColor).frame(width: 7, height: 7)
                    Text(app.isConnected ? "Connected" : "Offline").tFont(.footnote)
                }
                .foregroundStyle(theme.inkDimColor)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor.ignoresSafeArea())
    }

    private func item<Trailing: View>(_ selection: SidebarItem, symbol: String, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        let selected = app.sidebar == selection
        return Button { app.sidebar = selection } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(theme.brassInkColor).frame(width: 22)
                Text(title).tFont(.text(16, selected ? .semibold : .regular)).foregroundStyle(theme.inkColor)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(selected ? theme.accentTintColor : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func courseItem(_ session: CourseSession) -> some View {
        let selected = app.sidebar == .course(session.id)
        return Button { app.sidebar = .course(session.id) } label: {
            HStack(spacing: 12) {
                CourseDot(color: app.tint(for: session.id), size: 9)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.shortTitle).tFont(.mono(12, .semibold)).foregroundStyle(selected ? theme.brassInkColor : theme.inkDimColor)
                    Text(session.course.name).tFont(.text(16, selected ? .semibold : .regular)).foregroundStyle(theme.inkColor).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(session.displayScore.map { String(format: "%.1f", $0) } ?? "—").tFont(.mono(14)).foregroundStyle(selected ? theme.inkColor : theme.inkDimColor)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(selected ? theme.accentTintColor : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A course on iPad: header with the grade, the uniform section bar, and the section's content.
struct IPadCourseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var session: CourseSession

    private var section: HubSection { app.ipadSections[session.id] ?? .overview }

    var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: session.id) { await session.loadHub() }
    }

    private var sections: [HubSection] { [.overview] + session.hubSections }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow([session.shortTitle, session.sectionLabel, session.teacherName].compactMap { $0 }.joined(separator: " · "))
                    Text(session.course.name).tFont(.display(30)).foregroundStyle(theme.inkColor).lineLimit(1).accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 12)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.displayScore.map { DueFormatter.percent($0) } ?? "—").tFont(.display(26)).foregroundStyle(theme.inkColor)
                    if let letter = session.displayLetter { LetterChip(letter: letter) }
                }
                CourseOptionsMenu(session: session)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Segmented(options: sections.map { ($0, $0.label) }, selection: Binding(get: { section }, set: { app.ipadSections[session.id] = $0 }))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.lineColor).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .assignments:
            assignmentsSplit
        case .overview:
            scroll { CourseHubContent(session: session, showsHeader: false) }
        case .modules:
            scroll { ModulesContent(session: session) }
        case .grades:
            scroll { GradesContent(session: session) }
        case .announcements:
            scroll { TopicListContent(session: session, announcements: true).padding(.top, 16) }
        case .discussions:
            scroll { TopicListContent(session: session, announcements: false).padding(.top, 16) }
        case .syllabus:
            scroll { SyllabusContent(courseId: session.id).padding(.top, 16) }
        case .people:
            scroll { PeopleContent(session: session).padding(.top, 16) }
        case .files:
            scroll { FilesContent(session: session).padding(.top, 16) }
        case .pages:
            scroll { Text("Open Pages from the course overview.").tFont(.secondary).foregroundStyle(theme.inkDimColor).padding(24) }
        }
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .refreshable { await session.refreshLoaded() }
    }

    private var assignmentsSplit: some View {
        let selection = Binding<CanvasID?>(
            get: { app.ipadAssignment[session.id] ?? session.nextUp?.assignmentId },
            set: { app.ipadAssignment[session.id] = $0 }
        )
        return GeometryReader { proxy in
            if proxy.size.width < 700 {
                // Too narrow for two columns (portrait, Split View): the list pushes the assignment instead.
                ScrollView {
                    AssignmentsContent(session: session).padding(.top, 16).padding(.bottom, 24)
                        .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            } else {
                split(selection: selection, listWidth: min(380, proxy.size.width * 0.42))
            }
        }
    }

    private func split(selection: Binding<CanvasID?>, listWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ScrollView {
                AssignmentsContent(session: session, selection: selection).padding(.top, 16).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .frame(width: listWidth)
            Rectangle().fill(theme.lineColor).frame(width: 1)
            if let id = selection.wrappedValue, let assignment = session.assignment(id) {
                ScrollView {
                    AssignmentContent(session: session, assignmentId: id)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) { SubmitInCanvasBar(assignment: assignment, compact: true) }
                .frame(maxWidth: .infinity)
            } else {
                ScreenMessage(systemName: "checklist", title: "Choose an assignment").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
