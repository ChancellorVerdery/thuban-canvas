import Foundation

/// Every error the core throws. `parse` is shared with the theme code copied from Thuban Study.
public enum ThubanError: Error, LocalizedError, Equatable, Sendable {
    case parse(String)
    case store(String)
    /// The app has no host/token yet.
    case notConnected
    /// Canvas rejected the token (401).
    case unauthorized
    /// Canvas said the feature is disabled for this course or the user may not see it (403 / 404 with a message).
    case unavailable(String)
    /// Any other HTTP failure.
    case http(status: Int, message: String)
    case network(String)
    case decoding(String)
    case invalidHost(String)

    public var errorDescription: String? {
        switch self {
        case .parse(let message), .store(let message), .network(let message), .decoding(let message), .invalidHost(let message):
            return message
        case .notConnected: return "Not connected to Canvas."
        case .unauthorized: return "Canvas rejected the access token. Paste a new one in Settings."
        case .unavailable(let message): return message
        case .http(let status, let message): return "Canvas returned \(status): \(message)"
        }
    }
}
