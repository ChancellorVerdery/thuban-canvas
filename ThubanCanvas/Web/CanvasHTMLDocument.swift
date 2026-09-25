import Foundation
import ThubanCanvasCore

/// The themed HTML document every Canvas fragment renders in (page bodies, descriptions, syllabus, announcements):
/// theme variables, typography, link colours, and the sanitized fragment. Shared by the Mac `CanvasHTMLView` and the
/// iOS `HTMLContentView`.
enum CanvasHTMLDocument {
    /// Full HTML document: theme variables, typography, and the sanitized fragment.
    static func build(html: String, title: String?, theme: ResolvedTheme, textScale: Double, host: String, dyslexia: Bool, reduceMotion: Bool,
                      bodyPadding: String = "20px 28px 40px", baseSize: Double = 15, maxWidth: String = "860px") -> String {
        let body = CanvasHTML.sanitize(html, host: host)
        let heading = title.map { "<h1 class=\"thuban-title\">\(escape($0))</h1>" } ?? ""
        let fontStack = dyslexia
            ? "\"OpenDyslexic\", \"Comic Sans MS\", \"Atkinson Hyperlegible\", -apple-system, sans-serif"
            : "-apple-system, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(theme.cssVariables)
        html { background: transparent; }
        body { margin: 0; padding: \(bodyPadding); color: var(--ink); font: \(baseSize * textScale)px/1.55 \(fontStack);
               -webkit-font-smoothing: antialiased; max-width: \(maxWidth); word-wrap: break-word; -webkit-text-size-adjust: 100%; }
        .thuban-title { font-family: "New York", "Iowan Old Style", Georgia, serif; font-weight: 600; font-size: \(26 * textScale)px; line-height: 1.2; margin: 0 0 16px; }
        h1, h2, h3, h4 { font-family: "New York", "Iowan Old Style", Georgia, serif; font-weight: 600; line-height: 1.25; color: var(--ink); margin: 1.4em 0 .5em; }
        h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.15em; } h4 { font-size: 1em; }
        p { margin: 0 0 .9em; }
        /* Links: the AAA-contrast accent, weight 600 and a real underline, so they read inside long passages. */
        a { color: var(--accent-strong); font-weight: 600; text-decoration: underline; text-decoration-thickness: 1px;
            text-underline-offset: 2px; text-decoration-color: var(--accent-strong); }
        a:hover { text-decoration-thickness: 2px; }
        a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 2px; }
        img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
        iframe { min-height: 320px; width: 100%; border: 1px solid var(--line); }
        table { border-collapse: collapse; margin: 1em 0; max-width: 100%; }
        th, td { border: 1px solid var(--line-2); padding: 6px 10px; text-align: left; vertical-align: top; }
        th { background: var(--panel-2); font-weight: 600; }
        pre, code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .92em; }
        pre { background: var(--panel-2); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px; overflow: auto; }
        blockquote { margin: 1em 0; padding: 4px 0 4px 16px; border-left: 2px solid var(--line-2); color: var(--ink-dim); }
        hr { border: 0; border-top: 1px solid var(--line); margin: 1.5em 0; }
        ul, ol { padding-left: 1.4em; }
        li { margin: .25em 0; }
        [style*="background"] { background-image: none !important; }
        [style*="color"] { color: inherit !important; }
        [style*="font-family"] { font-family: inherit !important; }
        [style*="font-size"] { font-size: inherit !important; }
        [style*="width"] { max-width: 100% !important; }
        .dp-wrapper, [class^="dp-"] { background: transparent !important; box-shadow: none !important; }
        \(reduceMotion ? "*, *::before, *::after { animation: none !important; transition: none !important; }" : "")
        /* Find matches and text selection: the scheme's accent fill with its on-accent ink, so a match stands out in
           every scheme and in both modes (the tint was too close to the page). */
        ::selection { background: var(--accent); color: var(--on-accent); }
        a::selection, a *::selection { color: var(--on-accent); text-decoration-color: var(--on-accent); }
        img::selection { background: var(--accent); }
        </style></head><body>\(heading)\(body)</body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

}
