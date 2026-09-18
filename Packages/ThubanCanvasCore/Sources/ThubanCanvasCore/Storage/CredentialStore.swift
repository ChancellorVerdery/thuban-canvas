import Foundation

/// The Canvas host and access token.
public struct CanvasCredentials: Codable, Equatable, Sendable {
    /// `https://instructure.charlotte.edu` (scheme + host, no path, no trailing slash).
    public var host: String
    public var token: String

    public init(host: String, token: String) {
        self.host = host
        self.token = token
    }

    public var baseURL: URL? { URL(string: host) }

    /// Accepts "school.instructure.com", "https://school.instructure.com/", "instructure.school.edu" and returns the
    /// canonical `https://host` form. Rejects anything with a path, credentials or a non-https scheme.
    public static func normalizeHost(_ raw: String) throws -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ThubanError.invalidHost("Enter your Canvas address, e.g. school.instructure.com.") }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text), let host = components.host?.lowercased(), !host.isEmpty else {
            throw ThubanError.invalidHost("'\(raw)' is not a valid Canvas address.")
        }
        guard components.scheme == "https" else { throw ThubanError.invalidHost("Canvas addresses must use https.") }
        guard components.user == nil, components.password == nil else { throw ThubanError.invalidHost("Remove the user name from the address.") }
        guard components.path.isEmpty || components.path == "/" else { throw ThubanError.invalidHost("Use only the host name, e.g. school.instructure.com.") }
        guard host.contains(".") else { throw ThubanError.invalidHost("'\(host)' does not look like a Canvas host.") }
        var result = "https://" + host
        if let port = components.port { result += ":\(port)" }
        return result
    }

    public static func normalizeToken(_ raw: String) throws -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 20, !token.contains(" ") else { throw ThubanError.invalidHost("That does not look like a Canvas access token.") }
        return token
    }
}

/// Plain-file credential storage (mode 0600 under the app home). No Keychain by design — see `AppPaths.credentialsFile`.
public enum CredentialStore {
    public static func load() throws -> CanvasCredentials? {
        try JSONFile.read(CanvasCredentials.self, from: AppPaths.credentialsFile)
    }

    public static func save(_ credentials: CanvasCredentials) throws {
        try AppPaths.ensureDirectories()
        try JSONFile.write(credentials, to: AppPaths.credentialsFile, permissions: 0o600)
    }

    public static func clear() throws {
        try JSONFile.remove(AppPaths.credentialsFile)
    }
}
