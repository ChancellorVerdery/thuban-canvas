import SwiftUI
import ThubanCanvasCore

/// Every published assignment, quiz and graded discussion in the course, bucketed by date (Overdue / This week /
/// Upcoming / Past & graded / Undated) or listed by assignment group with weights. Click a row to open its detail.
struct AssignmentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var session: CourseSession
    @State private var grouping: Grouping = .date
    @State private var query = ""

    enum Grouping: Hashable { case date, group }

    var body: some View {
        ResourceStateView(resource: session.groups, emptyTitle: "No assignments yet",
                          emptyMessage: "Nothing has been published for this course.", isEmpty: { groups in
            groups.allSatisfy { ($0.assignments ?? []).isEmpty }
        }, retry: { await session.loadGroups(force: true) }) { groups in
            SectionPage {
                toolbar
                if filtered.isEmpty {
                    EmptyState(title: "No matches", message: "Nothing matches “\(query)”.")
                        .frame(minHeight: 240)
                } else if grouping == .date {
                    ForEach(dateBuckets(filtered), id: \.title) { bucket in
                        section(bucket.title, count: bucket.items.count, items: bucket.items)
                    }
                } else {
                    ForEach(groupBuckets(groups, items: filtered), id: \.id) { bucket in
                        section(bucket.name, count: bucket.items.count, weight: bucket.weight, items: bucket.items)
                    }
                }
            }
        }
        .task(id: session.id) {
            await session.loadGroups()
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            SegmentedPicker(selection: $grouping, options: [SegmentOption(.date, "By date"), SegmentOption(.group, "By group")], segmentHeight: SegmentedPickerHeight.toolbar)
                .accessibilityLabel("Grouping")
            Spacer()
            SearchField(text: $query, placeholder: "Search assignments")
                .frame(width: 240)
                .accessibilityLabel("Search assignments")
        }
    }

    // MARK: Data

    private var filtered: [WorkItem] {
        let items = session.workItems
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private struct DateBucket { var title: String; var items: [WorkItem] }
    private struct GroupBucket { var id: CanvasID; var name: String; var weight: Double?; var items: [WorkItem] }

    /// Overdue → This week → Upcoming → Past & graded → Undated. Future items sort soonest first, past ones most recent first.
    private func dateBuckets(_ items: [WorkItem], now: Date = Date()) -> [DateBucket] {
        let weekEnd = now.addingTimeInterval(7 * 86_400)
        var overdue: [WorkItem] = [], week: [WorkItem] = [], upcoming: [WorkItem] = [], past: [WorkItem] = [], undated: [WorkItem] = []
        for item in items {
            if item.status == .overdue { overdue.append(item); continue }
            guard let due = item.dueAt else { undated.append(item); continue }
            if due <= now { past.append(item) } else if due <= weekEnd { week.append(item) } else { upcoming.append(item) }
        }
        let soonest: (WorkItem, WorkItem) -> Bool = { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let latest: (WorkItem, WorkItem) -> Bool = { ($0.dueAt ?? .distantPast) > ($1.dueAt ?? .distantPast) }
        return [
            DateBucket(title: "Overdue", items: overdue.sorted(by: latest)),
            DateBucket(title: "This week", items: week.sorted(by: soonest)),
            DateBucket(title: "Upcoming", items: upcoming.sorted(by: soonest)),
            DateBucket(title: "Past & graded", items: past.sorted(by: latest)),
            DateBucket(title: "Undated", items: undated.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }),
        ].filter { !$0.items.isEmpty }
    }

    /// Assignment groups in position order; assignments keep Canvas's position within each group.
    private func groupBuckets(_ groups: [AssignmentGroup], items: [WorkItem]) -> [GroupBucket] {
        let byId = Dictionary(items.map { ($0.assignmentId ?? 0, $0) }, uniquingKeysWith: { first, _ in first })
        return groups
            .sorted { ($0.position ?? 0, $0.id) < ($1.position ?? 0, $1.id) }
            .map { group in
                let ordered = (group.assignments ?? [])
                    .sorted { ($0.position ?? 0, $0.dueAt ?? .distantFuture) < ($1.position ?? 0, $1.dueAt ?? .distantFuture) }
                    .compactMap { byId[$0.id] }
                return GroupBucket(id: group.id, name: group.name, weight: group.groupWeight, items: ordered)
            }
            .filter { !$0.items.isEmpty }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(_ title: String, count: Int, weight: Double? = nil, items: [WorkItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title, count: count) {
                if let weight = WorkText.weight(weight) {
                    Chip(weight, kind: .neutral).accessibilityLabel("Weight \(weight)")
                }
            }
            ForEach(items) { item in
                AssignmentRow(item: item) { open(item) }
            }
        }
    }

    private func open(_ item: WorkItem) {
        if let id = item.assignmentId { session.path.append(.assignment(id)) }
        else if let quiz = item.quizId { session.path.append(.quiz(quiz)) }
    }
}
