import AppKit
import SwiftUI
import ThubanCanvasCore

/// Everyone in the course grouped by role (teachers, TAs, students …) with avatars, names and pronouns. A search
/// field filters by name; clicking a person opens a popover whose "Message" button only opens the Inbox.
struct PeopleView: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var scale
    @Bindable var session: CourseSession
    @State private var query = ""
    @State private var selected: CanvasID?

    private static let roleOrder = ["Teacher", "TA", "Designer", "Observer", "Student"]

    var body: some View {
        ResourceStateView(resource: session.people, emptyTitle: "No one here", emptyMessage: "Canvas did not list anyone for this course.", isEmpty: { $0.isEmpty },
                          retry: { await session.loadPeople(force: true) }) { people in
            let groups = grouped(people)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    SearchField(text: $query, placeholder: "Search people")
                        .frame(maxWidth: 320)
                        .accessibilityLabel("Search people")
                    Text(summary(people))
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if groups.isEmpty {
                    EmptyState(title: "No matches", message: "No one's name contains “\(query)”.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(groups, id: \.title) { group in
                                SectionHeader(group.title, count: group.people.count)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 8)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 600), spacing: 8)], alignment: .leading, spacing: 8) {
                                    ForEach(group.people) { person in
                                        PersonRow(person: person, scale: scale) { selected = person.id }
                                            .popover(isPresented: Binding(get: { selected == person.id }, set: { if !$0 { selected = nil } }), arrowEdge: .bottom) {
                                                PersonPopover(session: session, person: person)
                                            }
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
        .task(id: session.id) { await session.loadPeople() }
    }

    private func summary(_ people: [CourseUser]) -> String {
        let students = people.filter { $0.roleLabel == "Student" }.count
        let staff = people.count - students
        var parts: [String] = []
        if staff > 0 { parts.append(staff == 1 ? "1 instructor" : "\(staff) instructors") }
        parts.append(students == 1 ? "1 student" : "\(students) students")
        return parts.joined(separator: " · ")
    }

    private func grouped(_ people: [CourseUser]) -> [(title: String, people: [CourseUser])] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matching = needle.isEmpty ? people : people.filter { $0.name.localizedCaseInsensitiveContains(needle) || ($0.sortableName?.localizedCaseInsensitiveContains(needle) ?? false) }
        var buckets: [String: [CourseUser]] = [:]
        for person in matching { buckets[person.roleLabel, default: []].append(person) }
        let known = Self.roleOrder.filter { buckets[$0] != nil }
        let extra = buckets.keys.filter { !Self.roleOrder.contains($0) }.sorted()
        return (known + extra).map { role in
            let list = (buckets[role] ?? []).sorted { ($0.sortableName ?? $0.name).localizedStandardCompare($1.sortableName ?? $1.name) == .orderedAscending }
            return (Self.plural(role), list)
        }
    }

    private static func plural(_ role: String) -> String {
        switch role {
        case "Teacher": return "Teachers"
        case "TA": return "TAs"
        case "Designer": return "Designers"
        case "Observer": return "Observers"
        case "Student": return "Students"
        default: return role
        }
    }
}

private struct PersonRow: View {
    @Environment(\.thubanTheme) private var theme
    var person: CourseUser
    var scale: Double
    var action: () -> Void

    var body: some View {
        ListRowCard(action: action) {
            HStack(spacing: 12) {
                AvatarView(name: person.name, url: person.avatarUrl, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name)
                        .font(ThubanFont.scaled(14, scale: scale, weight: .medium))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                    if let pronouns = person.pronouns, !pronouns.isEmpty {
                        Text(pronouns).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if person.enrollments?.first?.enrollmentState == "inactive" { Chip("Inactive", kind: .neutral) }
            }
        }
        .accessibilityLabel("\(person.name), \(person.roleLabel)\(person.pronouns.map { ", \($0)" } ?? "")")
        .accessibilityHint("Shows contact options")
    }
}

/// Name, role, pronouns, email and a Message button that opens the Inbox (nothing is sent from here).
private struct PersonPopover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: CourseSession
    var person: CourseUser

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(name: person.name, url: person.avatarUrl, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(ThubanFont.display(17)).foregroundStyle(theme.inkColor)
                    Text([person.roleLabel, person.pronouns].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                }
            }
            if let email = person.email, !email.isEmpty {
                Text(email).font(ThubanFont.mono(12)).foregroundStyle(theme.inkDimColor).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button {
                    dismiss()
                    app.panel = .inbox
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray").font(.system(size: 13, weight: .semibold))
                        Text("Message")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 30))
                .accessibilityLabel("Message \(person.name) — opens the Inbox")
                .help("Opens the Inbox; nothing is sent from here")
                if let url = session.canvasURL("users/\(person.id)") {
                    Button("View in Canvas") { NSWorkspace.shared.open(url) }
                        .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 8))
                }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(theme.panelColor)
    }
}
