import Foundation

/// HTTP method for write calls.
public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

/// A request body: JSON or form-encoded pairs (Canvas accepts both; arrays use `key[]`).
public enum RequestBody: Sendable {
    case json(Data)
    case form([(String, String)])
}

/// Talks to one Canvas instance with a bearer token: JSON decoding, `Link`-header pagination, rate-limit backoff
/// and error mapping. Read calls are all the app exercises live; write calls are wired through `CanvasWrites`.
public actor CanvasClient {
    public let credentials: CanvasCredentials
    private let session: URLSession
    private let baseURL: URL

    /// Pages fetched per paginated call before stopping (100 items each).
    public static let maxPages = 30
    public static let perPage = 100

    public init(credentials: CanvasCredentials, session: URLSession? = nil) throws {
        self.credentials = credentials
        guard let url = credentials.baseURL else { throw ThubanError.invalidHost("Invalid Canvas host '\(credentials.host)'.") }
        baseURL = url
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 300
            configuration.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: configuration)
        }
    }

    public var host: String { credentials.host }

    // MARK: Decoding

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = CanvasClient.parseDate(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date '\(text)'")
        }
        return decoder
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func parseDate(_ text: String) -> Date? {
        iso.date(from: text) ?? isoFractional.date(from: text) ?? dateOnly.date(from: text)
    }

    // MARK: Requests

    /// `GET /api/v1/<path>` decoded as `T`.
    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send(method: .get, path: path, query: query, body: nil)
        return try decode(T.self, from: data)
    }

    /// `GET` following `Link: rel="next"` until exhausted (or `maxPages`), concatenating the arrays.
    public func getAll<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> [T] {
        var items: [T] = []
        var query = query
        if !query.contains(where: { $0.name == "per_page" }) {
            query.append(URLQueryItem(name: "per_page", value: String(Self.perPage)))
        }
        var next: URL? = try makeURL(path: path, query: query)
        var pages = 0
        while let url = next, pages < Self.maxPages {
            let (data, response) = try await send(request: makeRequest(url: url, method: .get, body: nil))
            items.append(contentsOf: try decode([T].self, from: data))
            next = Self.nextLink(from: response)
            pages += 1
        }
        return items
    }

    /// A write call. Returns the decoded response.
    @discardableResult
    public func send<T: Decodable>(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], body: RequestBody?, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send(method: method, path: path, query: query, body: body)
        return try decode(T.self, from: data)
    }

    /// A write call whose response we ignore.
    public func sendIgnoringResponse(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], body: RequestBody?) async throws {
        _ = try await send(method: method, path: path, query: query, body: body)
    }

    /// Raw bytes for any URL on this host (file downloads carry a verifier but still accept the bearer token).
    /// Follows redirects to the file store; the bearer header is dropped automatically on cross-host redirects.
    public func data(for url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        if url.host == baseURL.host {
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(nil, forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw ThubanError.http(status: http.statusCode, message: "Download failed")
            }
            return (data, response)
        } catch let error as ThubanError {
            throw error
        } catch {
            throw ThubanError.network(error.localizedDescription)
        }
    }

    /// Download to a file, streaming (large lecture PDFs / slide decks).
    public func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        if url.host == baseURL.host {
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (temporary, response) = try await session.download(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw ThubanError.http(status: http.statusCode, message: "Download failed")
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch let error as ThubanError {
            throw error
        } catch {
            throw ThubanError.network(error.localizedDescription)
        }
    }

    // MARK: Internals

    func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/" + trimmed), resolvingAgainstBaseURL: false) else {
            throw ThubanError.network("Bad request path '\(path)'")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw ThubanError.network("Bad request path '\(path)'") }
        return url
    }

    private func makeRequest(url: URL, method: HTTPMethod, body: RequestBody?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        switch body {
        case .json(let data):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        case .form(let pairs):
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(Self.formEncode(pairs).utf8)
        case nil:
            break
        }
        return request
    }

    private func send(method: HTTPMethod, path: String, query: [URLQueryItem], body: RequestBody?) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(path: path, query: query)
        return try await send(request: makeRequest(url: url, method: method, body: body))
    }

    private func send(request: URLRequest, attempt: Int = 0) async throws -> (Data, HTTPURLResponse) {
        // Only GETs are retried after a dropped connection or a 5xx: Canvas may already have committed a write
        // (a 502 from the edge after the POST was processed), and a re-send would double-post / double-submit.
        let isIdempotentRead = (request.httpMethod ?? "GET") == "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if attempt < 1, isIdempotentRead, (error as? URLError)?.code == .networkConnectionLost {
                return try await send(request: request, attempt: attempt + 1)
            }
            throw ThubanError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ThubanError.network("No HTTP response") }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401:
            throw ThubanError.unauthorized
        case 403 where Self.isRateLimited(http, data: data) && attempt < 3:
            try await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
            return try await send(request: request, attempt: attempt + 1)
        case 403, 404:
            throw ThubanError.unavailable(Self.message(from: data) ?? (http.statusCode == 404 ? "Not found" : "Not available to you"))
        case 500..<600 where attempt < 1 && isIdempotentRead:
            try await Task.sleep(nanoseconds: 800_000_000)
            return try await send(request: request, attempt: attempt + 1)
        default:
            throw ThubanError.http(status: http.statusCode, message: Self.message(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw ThubanError.decoding("\(T.self): \(Self.describe(error))")
        }
    }

    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .keyNotFound(let key, let context): return "missing '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(let type, let context): return "expected \(type) at \(path(context))"
        case .valueNotFound(let type, let context): return "null \(type) at \(path(context))"
        case .dataCorrupted(let context): return "corrupt data at \(path(context)): \(context.debugDescription)"
        @unknown default: return error.localizedDescription
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }

    static func isRateLimited(_ response: HTTPURLResponse, data: Data) -> Bool {
        if let remaining = response.value(forHTTPHeaderField: "X-Rate-Limit-Remaining"), Double(remaining) ?? 1 <= 0 { return true }
        return (String(data: data, encoding: .utf8) ?? "").localizedCaseInsensitiveContains("rate limit")
    }

    static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = object["message"] as? String { return message }
        if let errors = object["errors"] as? [[String: Any]], let first = errors.first?["message"] as? String { return first }
        if let errors = object["errors"] as? [String: Any], let first = errors.values.first {
            if let text = first as? String { return text }
            if let list = first as? [[String: Any]], let message = list.first?["message"] as? String { return message }
        }
        return nil
    }

    /// The `rel="next"` URL from a `Link` header, if any.
    static func nextLink(from response: HTTPURLResponse) -> URL? {
        guard let header = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces[1] == "rel=\"next\"" else { continue }
            let raw = pieces[0].trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            return URL(string: raw)
        }
        return nil
    }

    static func formEncode(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}
