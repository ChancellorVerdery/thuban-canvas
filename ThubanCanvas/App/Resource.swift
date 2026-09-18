import Foundation
import Observation
import ThubanCanvasCore

/// One remote collection with cache-first loading. Views read `value`, `isLoading`, `error`, `unavailable`.
///
/// Loading order: cached bytes (instant, marked `fromCache`) → network when stale or forced → cache updated.
/// A `ThubanError.unavailable` (403/404: the instructor disabled the feature) sets `unavailable` so the section can
/// be hidden instead of showing an error.
@MainActor
@Observable
final class Resource<Value: Codable & Sendable> {
    let key: String
    let ttl: TimeInterval
    private(set) var value: Value?
    private(set) var loadedAt: Date?
    private(set) var fromCache = false
    private(set) var isLoading = false
    private(set) var error: ThubanError?
    private(set) var unavailable = false
    private(set) var hasAttempted = false
    @ObservationIgnored private var inflight: Task<Void, Never>?

    init(key: String, ttl: TimeInterval = 300) {
        self.key = key
        self.ttl = ttl
    }

    var isStale: Bool {
        guard let loadedAt, !fromCache else { return true }
        return Date().timeIntervalSince(loadedAt) > ttl
    }

    /// Cached or loaded value is present.
    var hasValue: Bool { value != nil }

    /// Reads the cache once (no network). Safe to call repeatedly.
    func prime(cache: DiskCache) async {
        guard value == nil else { return }
        if let entry = await cache.entry(for: key), let decoded = try? CanvasClient.decoder.decode(Value.self, from: entry.data) {
            value = decoded
            loadedAt = entry.storedAt
            fromCache = true
        }
    }

    /// Loads (cache first, then network when stale or `force`). Concurrent calls share one request.
    func load(app: AppModel, force: Bool = false, fetch: @escaping @Sendable (CanvasClient) async throws -> Value) async {
        if let inflight { await inflight.value; return }
        await prime(cache: app.cache)
        // 403/404 (`unavailable`) is not retried on every visit; only `force` (Retry / refresh) re-asks Canvas.
        guard force || (!unavailable && (isStale || value == nil)) else { return }
        guard let client = app.client else {
            error = .notConnected
            hasAttempted = true
            return
        }
        let task = Task { @MainActor in
            isLoading = true
            defer { isLoading = false; inflight = nil; hasAttempted = true }
            do {
                let fetched = try await fetch(client)
                value = fetched
                loadedAt = Date()
                fromCache = false
                error = nil
                unavailable = false
                if let data = try? Self.cacheEncoder.encode(fetched) { await app.cache.store(data, for: key) }
            } catch let thrown as ThubanError {
                if case .unavailable = thrown { unavailable = true } else { error = thrown }
                if case .unauthorized = thrown { app.noteUnauthorized() }
            } catch {
                self.error = .network(error.localizedDescription)
            }
        }
        inflight = task
        await task.value
    }

    /// Replaces the value locally (after a write) and refreshes the cache.
    func replace(_ newValue: Value, app: AppModel) {
        value = newValue
        loadedAt = Date()
        fromCache = false
        if let data = try? Self.cacheEncoder.encode(newValue) { Task { await app.cache.store(data, for: key) } }
    }

    /// Encoder whose output the `CanvasClient.decoder` (snake_case → camelCase, ISO dates) reads back.
    nonisolated static var cacheEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
