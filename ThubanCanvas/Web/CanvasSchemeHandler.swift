import Foundation
import ThubanCanvasCore
import WebKit

/// Serves `thubancanvas://host/...` requests from Canvas HTML (inline images, file previews, embedded media) by
/// fetching the real `https://` URL with the bearer token. WKWebView cannot attach headers to subresource loads.
///
/// Only passive media is proxied: Canvas HTML (e.g. a peer-uploaded .html file in an iframe) must never run as a
/// document inside this origin, because relative fetches from it would come back here carrying the user's token.
/// Everything runs on the main actor so `stop` can never interleave with the task callbacks (WebKit throws when a
/// stopped task is driven) and `tasks` is never touched from two threads.
@MainActor
final class CanvasSchemeHandler: NSObject, WKURLSchemeHandler {
    private let client: CanvasClient
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(client: CanvasClient) {
        self.client = client
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requested = urlSchemeTask.request.url, let original = CanvasHTML.original(requested) else {
            urlSchemeTask.didFailWithError(ThubanError.network("Bad proxied URL"))
            return
        }
        let id = ObjectIdentifier(urlSchemeTask)
        let client = client
        tasks[id] = Task { @MainActor [weak self] in
            defer { self?.tasks[id] = nil }
            do {
                let (data, response) = try await client.data(for: original)
                guard !Task.isCancelled else { return }
                let mime = (response.mimeType ?? "application/octet-stream").lowercased()
                guard Self.isPassiveMedia(mime) else {
                    urlSchemeTask.didFailWithError(ThubanError.network("Refusing to proxy \(mime)"))
                    return
                }
                let headers = ["Content-Type": mime, "Content-Length": String(data.count)]
                guard let http = HTTPURLResponse(url: requested, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
                    urlSchemeTask.didFailWithError(ThubanError.network("Bad response"))
                    return
                }
                urlSchemeTask.didReceive(http)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    /// Images (not SVG, which can carry scripts), video, audio, fonts and PDFs; never HTML or scripts.
    nonisolated static func isPassiveMedia(_ mime: String) -> Bool {
        if mime.hasPrefix("image/") { return mime != "image/svg+xml" }
        return mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime.hasPrefix("font/")
            || mime == "application/pdf" || mime == "application/octet-stream"
    }
}
