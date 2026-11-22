import Foundation

enum MarkdownDocument {
    static let extensions = ["md", "markdown", "mdown"]

    static func supports(_ url: URL) -> Bool {
        url.isFileURL && url.host?.isEmpty != false && extensions.contains(url.pathExtension.lowercased())
    }

    static func fileURL(for url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        return (components?.url ?? url).standardizedFileURL
    }

    static func render(_ url: URL) throws -> String {
        let url = url.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ReadError.notRegularFile }
        let limit = 16 * 1024 * 1024
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
        return try MarkdownRenderer.body(for: source, document: url)
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
