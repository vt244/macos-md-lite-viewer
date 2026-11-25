import Foundation

enum MarkdownRenderer {
    static func body(for source: String, document: URL? = nil, bundle: Bundle = .main) throws -> String {
        let hasTaskMarkers = source.contains("[ ]") || source.contains("[x]") || source.contains("[X]")
        let options = AttributedString.MarkdownParsingOptions(appliesSourcePositionAttributes: hasTaskMarkers)
        let markdown = try AttributedString(markdown: source, options: options)
        let sourceLines = hasTaskMarkers
            ? source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            : []
        let runs = markdown.runs
        var headings = [Int: String]()
        var explicitAnchors = [Int: [String]]()
        var usedAnchors = Set<String>()
        for (offset, run) in runs.enumerated() {
            let block = run.presentationIntent?.components.first
            if containsHTML(run) {
                if let anchors = anchorIDs(in: String(markdown[run.range].characters)) {
                    explicitAnchors[offset] = anchors.filter { usedAnchors.insert($0).inserted }
                }
            } else if let block, case .header = block.kind {
                headings[block.identity, default: ""] += String(markdown[run.range].characters)
            }
        }

        var html = ""
        var stack = [PresentationIntent.IntentType]()
        var codeSource = ""
        var nextColumn = 0

        func closeBlocks(after shared: Int) {
            for block in stack[shared...].reversed() {
                switch block.kind {
                case let .codeBlock(language):
                    let isMermaid = language?.trimmingCharacters(in: .whitespaces).lowercased() == "mermaid"
                    html += isMermaid ? "<pre data-mermaid>" : "<pre>"
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

        for (offset, runIndex) in runs.indices.enumerated() {
            let run = runs[runIndex]
            let anchors = explicitAnchors[offset]
            var path = Array((run.presentationIntent?.components ?? []).reversed())
            if anchors != nil, let paragraph = path.last, paragraph.kind == .paragraph,
               stack.last?.identity != paragraph.identity {
                let next = runs.index(after: runIndex)
                if next == runs.endIndex || runs[next].presentationIntent?.components.first?.identity != paragraph.identity {
                    path.removeLast()
                }
            }
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

            if let anchors {
                for id in anchors {
                    html += "<span id=\"\(escape(id))\"></span>"
                }
                continue
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
                if containsHTML(run) {
                    html += value
                } else {
                    html += inline(value, run: run)
                }
            }
        }
        closeBlocks(after: 0)
        return try HTMLRenderer.body(for: html, document: document, bundle: bundle, markdown: true)
    }

    private static func containsHTML(_ run: AttributedString.Runs.Run) -> Bool {
        !(run.inlinePresentationIntent ?? []).intersection([.inlineHTML, .blockHTML]).isEmpty
    }

    private static let anchorTag: NSRegularExpression = {
        let attribute = #"(id|name)\s*=\s*(['"]?)([^\s"'<>\x60=&]+)"#
        return try! NSRegularExpression(
            pattern: #"\A<a\s+"# + attribute + #"\2(?:\s+"# + attribute + #"\5)?\s*>\s*</a\s*>\z"#,
            options: .caseInsensitive
        )
    }()

    private static func anchorIDs(in html: String) -> [String]? {
        guard let match = anchorTag.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let first = Range(match.range(at: 3), in: html)
        else { return nil }
        guard let second = Range(match.range(at: 6), in: html) else { return [String(html[first])] }
        let firstAttribute = (html as NSString).substring(with: match.range(at: 1)).lowercased()
        let secondAttribute = (html as NSString).substring(with: match.range(at: 4)).lowercased()
        guard firstAttribute != secondAttribute else { return nil }
        return [String(html[first]), String(html[second])]
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

    private static func inline(_ value: String, run: AttributedString.Runs.Run) -> String {
        let intent = run.inlinePresentationIntent ?? []
        if intent.contains(.lineBreak) { return "<br>" }
        if intent.contains(.softBreak) { return " " }

        var result = escape(value)
        if let image = run.imageURL {
            let description = value == "\u{FFFC}" ? "" : result
            return "<img src=\"\(escape(image.relativeString))\" alt=\"\(description)\">"
        }

        if intent.contains(.code) { result = "<code>\(result)</code>" }
        if intent.contains(.strikethrough) { result = "<del>\(result)</del>" }
        if intent.contains(.stronglyEmphasized) { result = "<strong>\(result)</strong>" }
        if intent.contains(.emphasized) { result = "<em>\(result)</em>" }
        if let link = run.link {
            result = "<a href=\"\(escape(link.relativeString))\">\(result)</a>"
        }
        return result
    }
}
