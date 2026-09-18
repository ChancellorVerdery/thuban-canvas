import Foundation

/// Where the app keeps its files. `THUBAN_CANVAS_HOME` overrides the root (the smoke test points it at a temp dir).
public enum AppPaths {
    public static let homeVariable = "THUBAN_CANVAS_HOME"

    /// `~/Library/Application Support/Thuban Canvas` unless overridden.
    public static var home: URL {
        if let raw = ProcessInfo.processInfo.environment[homeVariable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Thuban Canvas", isDirectory: true)
    }

    public static var settingsFile: URL { home.appendingPathComponent("settings.json") }
    /// Host + token, mode 0600. Deliberately a file rather than the Keychain: an ad-hoc-signed build would trigger a
    /// Keychain prompt on every launch.
    public static var credentialsFile: URL { home.appendingPathComponent("credentials.json") }
    public static var cacheDirectory: URL { home.appendingPathComponent("cache", isDirectory: true) }
    public static var downloadsDirectory: URL { home.appendingPathComponent("files", isDirectory: true) }

    /// Creates the home tree (idempotent).
    public static func ensureDirectories() throws {
        for url in [home, cacheDirectory, downloadsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}
