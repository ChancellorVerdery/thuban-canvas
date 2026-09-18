import SwiftUI
import ThubanCanvasCore

/// A course tab: section bar (the same sections for every course), then the section — or the pushed detail.
struct CourseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession

    var body: some View {
        VStack(spacing: 0) {
            CourseSectionBar(session: session)
            if let route = session.path.last {
                CourseDetailHost(session: session, route: route)
                    .id(route)
            } else {
                sectionContent
                    .id(session.section)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: session.id) {
            await session.loadGroups()
            await session.loadGradingStandards()
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch session.section {
        case .overview: CourseOverviewView(session: session)
        case .modules: ModulesView(session: session)
        case .assignments: AssignmentsView(session: session)
        case .grades: GradesView(session: session)
        case .files: FilesView(session: session)
        case .announcements: AnnouncementsView(session: session)
        case .discussions: DiscussionsView(session: session)
        case .pages: PagesView(session: session)
        case .syllabus: SyllabusView(session: session)
        case .people: PeopleView(session: session)
        }
    }
}

/// 44 pt: course code + name on the left, the section segmented control, and a back button when a detail is open.
struct CourseSectionBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession

    var body: some View {
        HStack(spacing: 10) {
            if !session.path.isEmpty {
                Button {
                    session.path.removeLast()
                } label: {
                    HStack(spacing: 4) {
                        Glyph(.chevronLeft, size: 14)
                        Text(session.section.label)
                    }
                }
                .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 8))
                .keyboardShortcut("[", modifiers: .command)
            }
            SegmentedPicker(
                selection: Binding(get: { session.section }, set: { session.section = $0; session.path = [] }),
                options: session.availableSections.map { SegmentOption($0, $0.label) }
            )
            Spacer()
            if let score = session.displayScore {
                HStack(spacing: 6) {
                    Text(DueFormatter.percent(score))
                        .font(ThubanFont.display(15))
                        .foregroundStyle(theme.inkColor)
                        .monospacedDigit()
                    if let letter = session.displayLetter { Chip(letter, kind: .accent) }
                    if !session.whatIf.isEmpty { Chip("What-if", kind: .warn) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current grade \(DueFormatter.percent(score))")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: ThubanMetrics.sectionBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }
}

/// Routes a pushed detail to its view.
struct CourseDetailHost: View {
    @Bindable var session: CourseSession
    var route: CourseRoute

    var body: some View {
        switch route {
        case .assignment(let id): AssignmentDetailView(session: session, assignmentId: id)
        case .page(let slug): PageDetailView(session: session, slug: slug)
        case .file(let id): FileDetailView(session: session, fileId: id)
        case .discussion(let id): DiscussionDetailView(session: session, topicId: id)
        case .quiz(let id): QuizDetailView(session: session, quizId: id)
        case .module(let id): ModuleItemDetailView(session: session, itemId: id)
        case .externalURL(let url): ExternalLinkView(url: url)
        }
    }
}
