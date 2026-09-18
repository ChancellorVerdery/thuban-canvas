import Foundation
import ThubanCanvasCore
import WebKit

/// Serves `thubancanvas://host/...` requests from Canvas HTML (inline images, file previews, embedded media) by
/// fetching the real `https://` URL with the bearer token. WKWebView cannot attach headers to subresource loads.
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
        tasks[id] = Task { [weak self] in
            do {
                let (data, response) = try await client.data(for: original)
                guard !Task.isCancelled else { return }
                let mime = response.mimeType ?? "application/octet-stream"
                let headers = ["Content-Type": mime, "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*"]
                let http = HTTPURLResponse(url: requested, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
                urlSchemeTask.didReceive(http)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled else { return }
                urlSchemeTask.didFailWithError(error)
            }
            self?.tasks[id] = nil
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id]?.cancel()
        tasks[id] = nil
    }
}
