import Foundation

/// A URL-loading guard for read-only clients (the iOS app): any request that is not GET or HEAD is failed locally
/// before it reaches the network, so no code path can post, submit, delete or mark anything in Canvas. GETs are
/// not intercepted and load normally.
public final class ReadOnlyGuard: URLProtocol {
    /// Error the blocked request fails with.
    public static let blockedCode = -1_000_001

    /// Methods that may pass.
    public static func isAllowed(_ request: URLRequest) -> Bool {
        let method = (request.httpMethod ?? "GET").uppercased()
        return method == "GET" || method == "HEAD"
    }

    override public class func canInit(with request: URLRequest) -> Bool { !isAllowed(request) }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        let method = request.httpMethod ?? "?"
        let error = NSError(domain: "ThubanCanvas.ReadOnly", code: Self.blockedCode, userInfo: [
            NSLocalizedDescriptionKey: "Thuban Canvas is read-only on this device; \(method) was not sent.",
        ])
        client?.urlProtocol(self, didFailWithError: error)
    }

    override public func stopLoading() {}

    /// The session `CanvasClient` uses by default, with this guard in front of every request.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.protocolClasses = [ReadOnlyGuard.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }
}
