import Foundation
import Observation
import ThubanCanvasCore

/// The Canvas conversation scopes (`GET /conversations?scope=`).
enum InboxScope: String, CaseIterable, Hashable {
    case all, unread, starred, sent, archived

    var label: String {
        switch self {
        case .all: return "Inbox"
        case .unread: return "Unread"
        case .starred: return "Starred"
        case .sent: return "Sent"
        case .archived: return "Archived"
        }
    }

    /// The API `scope` value; the inbox itself has none.
    var apiScope: String? { self == .all ? nil : rawValue }
}

/// Owns one `Resource<[Conversation]>` per scope plus a cache of full conversations (with their messages).
/// Writes (reply, mark read, star) update the caches locally after the confirmed call succeeds.
@MainActor
@Observable
final class InboxModel {
    private(set) var scopes: [InboxScope: Resource<[Conversation]>] = [:]
    /// Full conversations from `GET /conversations/:id`, keyed by id.
    private(set) var details: [CanvasID: Conversation] = [:]
    private(set) var loadingDetails: Set<CanvasID> = []
    private(set) var detailErrors: [CanvasID: String] = [:]

    func resource(for scope: InboxScope) -> Resource<[Conversation]> {
        if let existing = scopes[scope] { return existing }
        let created = Resource<[Conversation]>(key: "inbox/conversations/\(scope.rawValue)", ttl: 180)
        scopes[scope] = created
        return created
    }

    /// Loads a scope (cache first) and refreshes the title-bar unread badge.
    func load(scope: InboxScope, app: AppModel, force: Bool = false) async {
        let apiScope = scope.apiScope
        await resource(for: scope).load(app: app, force: force) { try await $0.conversations(scope: apiScope) }
        await app.refreshUnreadCount()
    }

    /// Fetches the full conversation (messages, attachments) unless it is already cached.
    func loadDetail(_ id: CanvasID, app: AppModel, force: Bool = false) async {
        guard force || details[id] == nil, !loadingDetails.contains(id) else { return }
        guard let client = app.client else { return }
        loadingDetails.insert(id)
        defer { loadingDetails.remove(id) }
        do {
            let conversation = try await client.conversation(id)
            details[id] = conversation
            detailErrors[id] = nil
        } catch let error as ThubanError {
            if case .unauthorized = error { app.noteUnauthorized() }
            detailErrors[id] = error.localizedDescription
        } catch {
            detailErrors[id] = error.localizedDescription
        }
    }

    /// Replaces a conversation everywhere it is cached (after a confirmed write).
    func apply(_ updated: Conversation, app: AppModel) {
        if updated.messages != nil {
            details[updated.id] = updated
        } else if var existing = details[updated.id] {
            existing.workflowState = updated.workflowState
            existing.starred = updated.starred
            existing.lastMessage = updated.lastMessage
            existing.lastMessageAt = updated.lastMessageAt
            existing.messageCount = updated.messageCount
            details[updated.id] = existing
        }
        for (_, resource) in scopes {
            guard var list = resource.value, let index = list.firstIndex(where: { $0.id == updated.id }) else { continue }
            var row = list[index]
            row.workflowState = updated.workflowState
            row.starred = updated.starred
            row.lastMessage = updated.lastMessage ?? row.lastMessage
            row.lastMessageAt = updated.lastMessageAt ?? row.lastMessageAt
            row.messageCount = updated.messageCount ?? row.messageCount
            list[index] = row
            resource.replace(list, app: app)
        }
    }

    /// Local read/starred change after `markConversation` / `starConversation` succeed (those calls return nothing).
    func update(_ id: CanvasID, app: AppModel, change: (inout Conversation) -> Void) {
        if var detail = details[id] {
            change(&detail)
            details[id] = detail
        }
        for (_, resource) in scopes {
            guard var list = resource.value, let index = list.firstIndex(where: { $0.id == id }) else { continue }
            change(&list[index])
            resource.replace(list, app: app)
        }
    }
}

// MARK: - Presentation helpers

extension Conversation {
    /// The other people in the thread (never the signed-in user), in the audience's order.
    func others(excluding me: CanvasID?) -> [ConversationParticipant] {
        let people = (participants ?? []).filter { $0.id != me }
        guard let audience, !audience.isEmpty else { return people }
        let byId = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered = audience.compactMap { byId[$0] }
        let seen = Set(ordered.map(\.id))
        ordered += people.filter { !seen.contains($0.id) }
        return ordered
    }

    /// "Daniel Ortiz", "Ana Ruiz, Ben Pokroy" or "Daniel Ortiz, Sam Fischer +53".
    func participantSummary(excluding me: CanvasID?) -> String {
        let names = others(excluding: me).map(\.name)
        if names.isEmpty { return "Just you" }
        if names.count <= 2 { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)"
    }

    /// The subject for display: "(No subject)" when empty; SIS-style course names (Zoom notices use them) shortened.
    var displaySubject: String {
        let text = (subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "(No subject)" }
        return CourseNaming.shorten(text) ?? text
    }

    /// True when any cached message carries an attachment (list rows use the core `hasAttachments`, from `properties`).
    var hasCachedAttachments: Bool { messages?.contains { !($0.attachments ?? []).isEmpty } ?? false }

    /// Messages newest first.
    var messagesNewestFirst: [ConversationMessage] {
        (messages ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func participant(_ id: CanvasID?) -> ConversationParticipant? {
        guard let id else { return nil }
        return participants?.first { $0.id == id }
    }
}

/// The course a conversation belongs to: the tab's name when it is starred, else the code pulled out of Canvas's
/// long context name ("202680-Fall 2026-MATH-2171-005-Differential Equations" → "MATH 2171 · Differential Equations").
@MainActor
func conversationCourseName(_ conversation: Conversation, app: AppModel) -> String? {
    if let code = conversation.contextCode, code.hasPrefix("course_"), let id = CanvasID(code.dropFirst("course_".count)),
       let session = app.sessions[id] {
        return session.displayName
    }
    guard let raw = conversation.contextName, !raw.isEmpty else { return nil }
    return CourseNaming.shorten(raw) ?? raw
}

/// Compact list date: time today, weekday this week, else "Sep 3" (with the year when it is not this year).
func inboxDate(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "" }
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
    if abs(date.timeIntervalSince(now)) < 6 * 86_400 { return date.formatted(.dateTime.weekday(.wide)) }
    if calendar.component(.year, from: date) == calendar.component(.year, from: now) { return date.formatted(.dateTime.month(.abbreviated).day()) }
    return date.formatted(.dateTime.year().month(.abbreviated).day())
}
