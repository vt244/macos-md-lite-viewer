import Foundation
import JavaScriptCore

enum HTMLRenderer {
    static func body(for html: String, document: URL?, bundle: Bundle, markdown: Bool = false) throws -> String {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let context = try makeContext(bundle: bundle)
        let image = imageResolver(document: document, allowsSVG: !markdown)
        let link: @convention(block) (String) -> String? = { target in
            URL(string: target.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { linkTarget($0, document: document) }
        }
        guard let value = context.objectForKeyedSubscript("sanitizeHTML")?.call(withArguments: [
            html, image, link, markdown
        ]), value.isString, let body = value.toString() else { throw RenderError.sanitizerUnavailable }
        return body
    }

    static func makeContext(bundle: Bundle) throws -> JSContext {
        guard let context = JSContext() else { throw RenderError.sanitizerUnavailable }
        for name in ["asciidoc-engine.min", "SanitizeHTML"] {
            guard let script = bundle.url(forResource: name, withExtension: "js") else {
                throw RenderError.sanitizerUnavailable
            }
            context.evaluateScript(try String(contentsOf: script, encoding: .utf8), withSourceURL: script)
            if context.exception != nil { throw RenderError.sanitizerUnavailable }
        }
        return context
    }

    static func imageResolver(document: URL?, allowsSVG: Bool) -> @convention(block) (String) -> String? {
        var budget = MarkdownDocument.fileSizeLimit
        return { target in
            let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
            if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
               let host = url.host, !host.isEmpty, url.user == nil, url.password == nil {
                return url.absoluteString
            }
            return localImage(url, document: document, budget: &budget, allowsSVG: allowsSVG)
        }
    }

    static func linkTarget(_ url: URL, document: URL?) -> String? {
        if url.relativeString.hasPrefix("#") { return url.relativeString }
        if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            return url.absoluteString
        }
        guard let resolved = URL(string: url.relativeString, relativeTo: document)?.absoluteURL,
              MarkdownDocument.supports(resolved)
        else { return nil }

        var target = URLComponents()
        target.scheme = "markdown-file"
        target.host = "document"
        target.queryItems = [URLQueryItem(name: "url", value: resolved.absoluteString)]
        return target.string
    }

    private static func localImage(_ image: URL, document: URL?, budget: inout Int, allowsSVG: Bool) -> String? {
        let formats = ["png": "png", "jpg": "jpeg", "jpeg": "jpeg", "gif": "gif", "webp": "webp"]
        guard let file = MarkdownDocument.localResource(image, in: document) else { return nil }
        let ext = file.pathExtension.lowercased()
        // SVG is embedded as an image resource, with no access to the document DOM.
        guard let format = allowsSVG && ext == "svg" ? "svg+xml" : formats[ext],
              let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              info.isRegularFile == true, let size = info.fileSize, size <= budget,
              let data = try? Data(contentsOf: file), data.count <= budget
        else { return nil }
        budget -= data.count
        return "data:image/\(format);base64,\(data.base64EncodedString())"
    }

    private enum RenderError: LocalizedError {
        case sanitizerUnavailable

        var errorDescription: String? { L10n.text("error.htmlRender") }
    }
}
