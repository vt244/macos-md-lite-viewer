import Foundation

enum QuickLookDiagram {
    private struct Link {
        let from: String
        let to: String
        let label: String
        let dashed: Bool
        let arrow: Bool
    }

    static func render(_ source: String, id: Int) -> String? {
        guard source.utf8.count <= 12_000 else { return nil }
        let lines = source.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
        guard let header = lines.first, lines.count <= 85 else { return nil }
        if header == "sequenceDiagram" { return sequence(lines.dropFirst(), id: id) }
        let words = header.split(whereSeparator: \.isWhitespace)
        guard let kind = words.first, kind == "flowchart" || kind == "graph",
              words.count == 2 else { return nil }
        let direction = String(words[1]).replacingOccurrences(of: ";", with: "")
        guard ["TD", "TB", "BT", "LR", "RL"].contains(direction) else { return nil }
        return flowchart(lines.dropFirst(), direction: direction, id: id)
    }

    private static let nodePattern = #"[A-Za-z0-9_]+(?:\[[^\[\]]+\]|\([^()]+\)|\{[^{}]+\})?"#
    private static let node = try! NSRegularExpression(
        pattern: #"^([A-Za-z0-9_]+)(?:\[([^\[\]]+)\]|\(([^()]+)\)|\{([^{}]+)\})?"#
    )
    private static let flowLink = try! NSRegularExpression(
        pattern: #"^\s*(-->|---|-\.->|==>)\s*(?:\|([^|]*)\|\s*)?("# + nodePattern + ")"
    )
    private static let participant = try! NSRegularExpression(
        pattern: #"^(?:participant|actor)\s+([A-Za-z0-9_]+)(?:\s+as\s+(.+))?$"#
    )
    private static let message = try! NSRegularExpression(
        pattern: #"^([A-Za-z0-9_]+)\s*(-->>|->>|-->|->)\s*([A-Za-z0-9_]+)\s*:\s*(.+)$"#
    )

    private static func flowchart(_ lines: ArraySlice<String>, direction: String, id: Int) -> String? {
        var names = [String]()
        var labels = [String: String]()
        var links = [Link]()

        func readNode(_ text: String) -> (id: String, remainder: String)? {
            guard let parsed = match(node, text) else { return nil }
            let name = parsed[1]
            if labels[name] == nil {
                names.append(name)
                labels[name] = name
            }
            if let label = parsed.dropFirst(2).first(where: { !$0.isEmpty }) {
                labels[name] = unquote(label)
            }
            return (name, String(text.dropFirst(parsed[0].count)))
        }

        for statement in lines {
            let line = statement.last == ";" ? String(statement.dropLast()) : statement
            guard var current = readNode(line) else { return nil }
            while !current.remainder.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let edge = match(flowLink, current.remainder), let next = readNode(edge[3]) else {
                    return nil
                }
                links.append(Link(from: current.id, to: next.id, label: unquote(edge[2]),
                                  dashed: edge[1] == "-.->", arrow: edge[1] != "---"))
                current = (next.id, String(current.remainder.dropFirst(edge[0].count)))
            }
        }

        guard !names.isEmpty, names.count <= 24, links.count <= 45 else { return nil }
        var groups = [[String]]()
        var placed = Set<String>()
        var remaining = names
        while !remaining.isEmpty {
            var next = remaining.filter { name in
                links.allSatisfy { $0.to != name || $0.from == name || placed.contains($0.from) }
            }
            if next.isEmpty { next = [remaining[0]] }
            groups.append(next)
            placed.formUnion(next)
            remaining.removeAll { placed.contains($0) }
        }

        let horizontal = direction == "LR" || direction == "RL"
        if direction == "RL" || direction == "BT" { groups.reverse() }
        let breadth = groups.map(\.count).max() ?? 1
        let boxWidth = width(for: Array(labels.values))
        let boxHeight = 40
        let horizontalStep = boxWidth + 85
        let verticalStep = boxHeight + 56
        let width = 30 + (horizontal ? groups.count : breadth) * horizontalStep - 50
        let height = 30 + (horizontal ? breadth : groups.count) * verticalStep - 28
        var positions = [String: (x: Int, y: Int)]()
        for (rank, group) in groups.enumerated() {
            for (row, name) in group.enumerated() {
                let offset = breadth - group.count
                positions[name] = horizontal
                    ? (15 + boxWidth / 2 + rank * horizontalStep,
                       15 + boxHeight / 2 + offset * verticalStep / 2 + row * verticalStep)
                    : (15 + boxWidth / 2 + offset * horizontalStep / 2 + row * horizontalStep,
                       15 + boxHeight / 2 + rank * verticalStep)
            }
        }

        var drawing = ""
        for edge in links {
            guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
            let style = edge.dashed ? " stroke-dasharray=\"5 4\"" : ""
            let arrow = edge.arrow ? " marker-end=\"url(#arrow-\(id))\"" : ""
            if edge.from == edge.to {
                let start = a.x + boxWidth / 2
                drawing += "<path d=\"M \(start) \(a.y - 8) c 32 -24 32 40 0 16\"\(style)\(arrow)/>"
                continue
            }
            let x = b.x >= a.x ? 1 : -1
            let y = b.y >= a.y ? 1 : -1
            let useHorizontal = a.y == b.y || (a.x != b.x && horizontal)
            let startX = a.x + (useHorizontal ? x * boxWidth / 2 : 0)
            let endX = b.x - (useHorizontal ? x * boxWidth / 2 : 0)
            let startY = a.y + (useHorizontal ? 0 : y * boxHeight / 2)
            let endY = b.y - (useHorizontal ? 0 : y * boxHeight / 2)
            drawing += "<path d=\"M \(startX) \(startY) L \(endX) \(endY)\"\(style)\(arrow)/>"
            if !edge.label.isEmpty {
                drawing += text(edge.label, x: (startX + endX) / 2, y: (startY + endY) / 2 - 7)
            }
        }
        for name in names {
            guard let position = positions[name] else { continue }
            drawing += box(labels[name] ?? name, x: position.x, y: position.y, width: boxWidth)
        }
        return svg(width: width, height: height, drawing: drawing, id: id)
    }

    private static func sequence(_ lines: ArraySlice<String>, id: Int) -> String? {
        var names = [String]()
        var labels = [String: String]()
        var messages = [Link]()
        func add(_ id: String, label: String = "") {
            if labels[id] == nil { names.append(id) }
            if !label.isEmpty || labels[id] == nil { labels[id] = label.isEmpty ? id : label }
        }

        for line in lines {
            if let actor = match(participant, line) {
                add(actor[1], label: unquote(actor[2]))
            } else if let item = match(message, line), item[1] != item[3] {
                add(item[1])
                add(item[3])
                messages.append(Link(from: item[1], to: item[3], label: item[4],
                                     dashed: item[2].hasPrefix("--"), arrow: true))
            } else {
                return nil
            }
        }
        guard names.count >= 2, names.count <= 12, !messages.isEmpty else { return nil }
        let boxWidth = width(for: Array(labels.values))
        let spacing = max(boxWidth + 24, width(for: messages.map(\.label)) + 15)
        let height = 74 + messages.count * 38
        let length = 30 + boxWidth + (names.count - 1) * spacing
        let columns = Dictionary(uniqueKeysWithValues: names.enumerated().map {
            ($0.element, 15 + boxWidth / 2 + $0.offset * spacing)
        })
        var drawing = ""
        for name in names {
            guard let x = columns[name] else { continue }
            drawing += box(labels[name] ?? name, x: x, y: 31, width: boxWidth)
            drawing += "<path d=\"M \(x) 51 V \(height - 10)\" stroke-dasharray=\"4 4\"/>"
        }
        for (index, arrow) in messages.enumerated() {
            guard let a = columns[arrow.from], let b = columns[arrow.to] else { continue }
            let y = 72 + index * 38
            let style = arrow.dashed ? " stroke-dasharray=\"5 4\"" : ""
            drawing += "<path d=\"M \(a) \(y) H \(b)\"\(style) marker-end=\"url(#arrow-\(id))\"/>"
            drawing += text(arrow.label, x: (a + b) / 2, y: y - 7)
        }
        return svg(width: length, height: height, drawing: drawing, id: id)
    }

    private static func width(for labels: [String]) -> Int {
        max(95, min(440, 30 + (labels.map(\.count).max() ?? 0) * 9))
    }

    private static func svg(width: Int, height: Int, drawing: String, id: Int) -> String {
        """
        <div class="diagram"><svg class="quicklook-diagram" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) \(height)" width="\(width)" height="\(height)" role="img" aria-label="Mermaid">
        <defs><marker id="arrow-\(id)" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M 0 0 L 8 4 L 0 8 Z" class="diagram-arrow"/></marker></defs>
        \(drawing)</svg></div>
        """
    }

    private static func box(_ label: String, x: Int, y: Int, width: Int) -> String {
        "<rect x=\"\(x - width / 2)\" y=\"\(y - 20)\" width=\"\(width)\" height=\"40\" rx=\"7\"/>"
            + text(label, x: x, y: y + 5)
    }

    private static func text(_ label: String, x: Int, y: Int) -> String {
        "<text x=\"\(x)\" y=\"\(y)\">\(MarkdownRenderer.escape(label))</text>"
    }

    private static func unquote(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        if text.count >= 2, text.first == "\"", text.last == "\"" { return String(text.dropFirst().dropLast()) }
        return text
    }

    private static func match(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map {
            Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
