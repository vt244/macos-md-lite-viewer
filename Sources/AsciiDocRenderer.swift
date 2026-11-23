import Foundation
import JavaScriptCore

enum AsciiDocRenderer {
    private static let includeRoot = "/__markdown_viewer_document__"
    private static let crossReferenceSuffix = "asciidoc-xref"

    static func body(for source: String, document: URL, bundle: Bundle) throws -> String {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard let engine = bundle.url(forResource: "asciidoc-engine.min", withExtension: "js"),
              let bridge = bundle.url(forResource: "RenderAsciiDoc", withExtension: "js"),
              let context = JSContext()
        else { throw RenderError.engineUnavailable }

        var output: Result<String, RenderError>?
        let finish: @convention(block) (String) -> Void = { output = .success($0) }
        let fail: @convention(block) (String) -> Void = { output = .failure(.conversion($0)) }
        var includeBudget = MarkdownDocument.fileSizeLimit
        let include: @convention(block) (String) -> String? = { target in
            guard let reference = includeReference(target),
                  let file = MarkdownDocument.localResource(reference, in: document),
                  let included = try? MarkdownDocument.readText(at: file, limit: includeBudget)
            else { return nil }
            includeBudget -= max(1, included.size)
            return included.text
        }
        var imageBudget = MarkdownDocument.fileSizeLimit
        let image: @convention(block) (String) -> String? = { target in
            guard let reference = URL(string: target) else { return nil }
            return MarkdownRenderer.localImage(reference, document: document, budget: &imageBudget, allowsSVG: true)
        }
        let link: @convention(block) (String) -> String? = { target in
            linkTarget(target, document: document)
        }

        context.exceptionHandler = { _, error in
            output = .failure(.conversion(error?.toString() ?? ""))
        }
        for script in [engine, bridge] {
            context.evaluateScript(try String(contentsOf: script, encoding: .utf8), withSourceURL: script)
            if let output { return try output.get() }
        }
        context.objectForKeyedSubscript("renderAsciiDoc")?.call(withArguments: [
            source, includeRoot, crossReferenceSuffix, include, image, link, finish, fail
        ])
        // The converter's promises use only synchronous native resource callbacks.
        // JavaScriptCore drains their microtasks before returning to Swift.
        guard let output else { throw RenderError.engineUnavailable }
        return try output.get()
    }

    private static func includeReference(_ target: String) -> URL? {
        let path = target.hasPrefix("file://") ? String(target.dropFirst("file://".count)) : target
        let prefix = includeRoot + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let relative = String(path.dropFirst(prefix.count))
        guard let reference = URL(string: relative), reference.scheme == nil, reference.host == nil,
              !relative.hasPrefix("/")
        else { return nil }
        return reference
    }

    private static func linkTarget(_ target: String, document: URL) -> String? {
        guard let reference = URL(string: target) else { return nil }
        guard reference.pathExtension == crossReferenceSuffix,
              reference.scheme == nil, reference.host == nil
        else { return MarkdownRenderer.linkTarget(reference, document: document) }

        guard let resolved = URL(string: target, relativeTo: document)?.absoluteURL,
              var link = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
        else { return nil }
        let stem = resolved.deletingPathExtension()
        for ext in [document.pathExtension] + MarkdownDocument.asciiDocExtensions {
            let candidate = stem.appendingPathExtension(ext)
            if (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                link.path = candidate.path
                return link.url.flatMap { MarkdownRenderer.linkTarget($0, document: document) }
            }
        }
        return nil
    }

    private enum RenderError: LocalizedError {
        case engineUnavailable, conversion(String)

        var errorDescription: String? {
            switch self {
            case .engineUnavailable:
                return L10n.text("error.asciiDocEngine")
            case .conversion(let details):
                return L10n.text("error.asciiDocConversion") + (details.isEmpty ? "" : " " + details)
            }
        }
    }
}
