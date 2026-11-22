import Foundation

enum MarkdownRenderer {
    static func body(
        for source: String, document: URL? = nil
    ) throws -> String {
        let hasTaskMarkers = source.contains("[ ]") || source.contains("[x]") || source.contains("[X]")
        let options = AttributedString.MarkdownParsingOptions(appliesSourcePositionAttributes: hasTaskMarkers)
        let markdown = try AttributedString(markdown: source, options: options)
        let sourceLines = hasTaskMarkers
            ? source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            : []
        var headings = [Int: String]()
        for run in markdown.runs {
            if let block = run.presentationIntent?.components.first, case .header = block.kind {
                headings[block.identity, default: ""] += String(markdown[run.range].characters)
            }
        }

        var html = ""
        var stack = [PresentationIntent.IntentType]()
        var usedAnchors = Set<String>()
        var codeSource = ""
        var nextColumn = 0
        var imageBudget = 16 * 1024 * 1024

        func closeBlocks(after shared: Int) {
            for block in stack[shared...].reversed() {
                switch block.kind {
                case let .codeBlock(language):
                    html += "<pre>"
                    if let language, !language.isEmpty {
                        html += "<span class=\"code-language\">\(escape(language))</span>"
                    }
                    html += "<code>\(escape(codeSource))</code></pre>"
                case .table: html += "</table></div>"
                case .tableHeaderRow, .tableRow:
                    let columns = tableColumns(in: stack)
                    let cell = cellTag(in: stack)
                    while nextColumn < columns.count {
                        html += "<\(cell)></\(cell)>"
                        nextColumn += 1
                    }
                    html += "</tr>"
                case .thematicBreak: break
                default: html += "</\(tag(for: block.kind, in: stack))>"
                }
            }
            stack.removeLast(stack.count - shared)
        }

        for run in markdown.runs {
            let path = Array((run.presentationIntent?.components ?? []).reversed())
            var shared = 0
            while shared < min(path.count, stack.count), path[shared] == stack[shared] {
                shared += 1
            }
            closeBlocks(after: shared)

            for (index, block) in path.enumerated().dropFirst(shared) {
                switch block.kind {
                case .header:
                    let tag = tag(for: block.kind, in: path)
                    let anchor = headingAnchor(headings[block.identity] ?? "", used: &usedAnchors)
                    html += "<\(tag) id=\"\(escape(anchor))\">"
                case .orderedList:
                    if index + 1 < path.count, case let .listItem(ordinal) = path[index + 1].kind {
                        html += "<ol start=\"\(ordinal)\">"
                    } else {
                        html += "<ol>"
                    }
                case .codeBlock: codeSource = ""
                case .table: html += "<div class=\"table-wrap\"><table>"
                case .tableHeaderRow, .tableRow:
                    nextColumn = 0
                    html += "<tr>"
                case let .tableCell(column):
                    let cell = cellTag(in: path)
                    while nextColumn < column {
                        html += "<\(cell)></\(cell)>"
                        nextColumn += 1
                    }
                    let columns = tableColumns(in: path)
                    let alignment = columns.indices.contains(column) ? columns[column].alignment : .left
                    let alignmentClass: String
                    switch alignment {
                    case .left: alignmentClass = "left"
                    case .center: alignmentClass = "center"
                    case .right: alignmentClass = "right"
                    @unknown default: alignmentClass = "left"
                    }
                    html += "<\(cell) class=\"\(alignmentClass)\">"
                    nextColumn = column + 1
                case .thematicBreak: html += "<hr>"
                default: html += "<\(tag(for: block.kind, in: path))>"
                }
                stack.append(block)
            }

            var value = String(markdown[run.range].characters)
            if path.count >= 2, shared < path.count - 1,
               path.last?.kind == .paragraph, case .listItem = path[path.count - 2].kind,
               let checked = taskState(value, position: run.markdownSourcePosition, lines: sourceLines) {
                html += "<input class=\"task-checkbox\" type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                value = String(value.dropFirst(4))
            }
            switch path.last?.kind {
            case .thematicBreak: break
            case .codeBlock: codeSource += value
            default:
                if run.inlinePresentationIntent?.contains(.blockHTML) == true {
                    html += "<pre><code>\(escape(value))</code></pre>"
                } else {
                    html += inline(value, run: run, document: document, imageBudget: &imageBudget)
                }
            }
        }
        closeBlocks(after: 0)
        return html
    }

    private static func taskState(
        _ value: String, position: AttributedString.MarkdownSourcePosition?, lines: [Substring]
    ) -> Bool? {
        let marker = value.prefix(3).lowercased()
        guard marker == "[ ]" || marker == "[x]",
              value.dropFirst(3).first?.isWhitespace == true,
              let position, position.startLine > 0, position.startLine <= lines.count,
              position.startColumn > 0
        else { return nil }
        let original = lines[position.startLine - 1].dropFirst(position.startColumn - 1)
        guard original.prefix(3).lowercased() == marker else { return nil }
        return marker == "[x]"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func tag(for kind: PresentationIntent.Kind, in path: [PresentationIntent.IntentType]) -> String {
        switch kind {
        case .paragraph: return "p"
        case let .header(level): return "h\(level)"
        case .orderedList: return "ol"
        case .unorderedList: return "ul"
        case .listItem: return "li"
        case .blockQuote: return "blockquote"
        case .tableCell: return cellTag(in: path)
        default: return "div"
        }
    }

    private static func cellTag(in path: [PresentationIntent.IntentType]) -> String {
        path.contains { $0.kind == .tableHeaderRow } ? "th" : "td"
    }

    private static func tableColumns(in path: [PresentationIntent.IntentType]) -> [PresentationIntent.TableColumn] {
        for component in path {
            if case let .table(columns) = component.kind { return columns }
        }
        return []
    }

    private static func headingAnchor(_ heading: String, used: inout Set<String>) -> String {
        let base = heading.lowercased().reduce(into: "") { slug, character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                slug.append(character)
            } else if character.isWhitespace {
                slug.append("-")
            }
        }
        let stem = base.isEmpty ? "section" : base
        var anchor = stem
        var suffix = 1
        while !used.insert(anchor).inserted {
            anchor = "\(stem)-\(suffix)"
            suffix += 1
        }
        return anchor
    }

    private static func inline(
        _ value: String, run: AttributedString.Runs.Run, document: URL?, imageBudget: inout Int
    ) -> String {
        let intent = run.inlinePresentationIntent ?? []
        if intent.contains(.lineBreak) { return "<br>" }
        if intent.contains(.softBreak) { return " " }

        var result = escape(value)
        if let image = run.imageURL {
            let description = value == "\u{FFFC}" ? "" : result
            if let dataURL = localImage(image, document: document, budget: &imageBudget) {
                return "<img src=\"\(dataURL)\" alt=\"\(description)\">"
            }
            return description
        }

        if intent.contains(.code) { result = "<code>\(result)</code>" }
        if intent.contains(.strikethrough) { result = "<del>\(result)</del>" }
        if intent.contains(.stronglyEmphasized) { result = "<strong>\(result)</strong>" }
        if intent.contains(.emphasized) { result = "<em>\(result)</em>" }
        if let link = run.link, let href = linkTarget(link, document: document) {
            result = "<a href=\"\(escape(href))\">\(result)</a>"
        }
        return result
    }

    private static func linkTarget(_ url: URL, document: URL?) -> String? {
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

    private static func localImage(_ image: URL, document: URL?, budget: inout Int) -> String? {
        guard let folder = document?.deletingLastPathComponent().resolvingSymlinksInPath(),
              let resolved = URL(string: image.relativeString, relativeTo: document)?.absoluteURL,
              resolved.isFileURL, resolved.host?.isEmpty != false
        else { return nil }
        let file = resolved.resolvingSymlinksInPath().standardizedFileURL
        let formats = ["png": "png", "jpg": "jpeg", "jpeg": "jpeg", "gif": "gif", "webp": "webp"]
        guard file.pathComponents.starts(with: folder.pathComponents),
              let format = formats[file.pathExtension.lowercased()],
              let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              info.isRegularFile == true, let size = info.fileSize, size <= budget,
              let data = try? Data(contentsOf: file), data.count <= budget
        else { return nil }
        budget -= data.count
        return "data:image/\(format);base64,\(data.base64EncodedString())"
    }
}
