import Foundation

enum MarkdownDocument {
    static let asciiDocExtensions = ["asciidoc", "asc", "ad", "adoc"]
    static let extensions = ["md", "markdown", "mdown"] + asciiDocExtensions
    static let fileSizeLimit = 16 * 1024 * 1024

    static func supports(_ url: URL) -> Bool {
        url.isFileURL && url.host?.isEmpty != false && extensions.contains(url.pathExtension.lowercased())
    }

    static func fileURL(for url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        return (components?.url ?? url).standardizedFileURL
    }

    static func render(_ url: URL, bundle: Bundle = .main) throws -> String {
        let isAsciiDoc = asciiDocExtensions.contains(url.pathExtension.lowercased())
        let url = url.resolvingSymlinksInPath()
        let (source, _) = try readText(at: url, limit: fileSizeLimit)
        if isAsciiDoc {
            return try AsciiDocRenderer.body(for: source, document: url, bundle: bundle)
        }
        return try MarkdownRenderer.body(for: source, document: url)
    }

    static func readText(at url: URL, limit: Int) throws -> (text: String, size: Int) {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ReadError.notRegularFile }
        guard let size = values.fileSize, size <= limit else { throw ReadError.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ReadError.tooLarge }

        let source: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            source = String(data: data, encoding: .utf16)
        } else if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            source = String(data: data.dropFirst(3), encoding: .utf8)
        } else {
            source = String(data: data, encoding: .utf8)
        }
        guard let source else { throw ReadError.unsupportedEncoding }
        return (source, data.count)
    }

    static func localResource(_ reference: URL, in document: URL?) -> URL? {
        guard let folder = document?.deletingLastPathComponent().resolvingSymlinksInPath(),
              let resolved = URL(string: reference.relativeString, relativeTo: document)?.absoluteURL,
              resolved.isFileURL, resolved.host?.isEmpty != false
        else { return nil }
        let file = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard file.pathComponents.starts(with: folder.pathComponents) else { return nil }
        return file
    }

    private enum ReadError: LocalizedError {
        case notRegularFile, tooLarge, unsupportedEncoding

        var errorDescription: String? {
            switch self {
            case .notRegularFile: return L10n.text("error.notRegularFile")
            case .tooLarge: return L10n.text("error.tooLarge")
            case .unsupportedEncoding: return L10n.text("error.unsupportedEncoding")
            }
        }
    }
}
