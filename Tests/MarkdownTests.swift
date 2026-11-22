import Foundation

@main
enum MarkdownTests {
    static func main() throws {
        let html = try MarkdownRenderer.body(for: """
        # Заголовок

        # Заголовок

        **Жирный**, *курсив*, ~~зачёркнуто~~ и `a < b`.  
        Вторая строка.

        > Цитата

        3. Первый пункт
           - Вложенный пункт
        4. Второй пункт

        | A | B | C |
        | - | :-: | -: |
        | 1 | | 3 |

        ~~~swift
        print("<tag>")
        ~~~

        ---

        [Якорь](#заголовок) [Внешняя](https://example.com) [Локальная](next.md#section)

        [Недопустимая](javascript:alert%281%29) <img src=x onerror=alert(1)>

        <script>alert(1)</script>
        """, document: URL(fileURLWithPath: "/docs/README.md"))

        for expected in [
            "<h1 id=\"заголовок\">Заголовок</h1>",
            "<h1 id=\"заголовок-1\">Заголовок</h1>",
            "<strong>Жирный</strong>", "<em>курсив</em>", "<del>зачёркнуто</del>",
            "<code>a &lt; b</code>.<br>Вторая строка.",
            "<blockquote><p>Цитата</p></blockquote>",
            "<ol start=\"3\"><li><p>Первый пункт</p><ul><li><p>Вложенный пункт</p></li></ul>",
            "<th class=\"center\">B</th>", "<td></td><td class=\"right\">3</td>",
            "<pre><span class=\"code-language\">swift</span><code>print(&quot;&lt;tag&gt;&quot;)",
            "<hr>", "<a href=\"#", "<a href=\"https://example.com\">Внешняя</a>",
            "markdown-file://document?url=file:///docs/next.md%23section",
            "&lt;img src=x onerror=alert(1)&gt;",
            "&lt;script&gt;alert(1)&lt;/script&gt;"
        ] {
            try check(html.contains(expected), "Missing HTML: \(expected)\n\(html)")
        }
        try check(!html.contains("href=\"javascript:") && !html.contains("<script>"), "Unsafe HTML was emitted")
        let extensions = try MarkdownRenderer.body(for: #"""
        - [x] Finished
        - [ ] Pending
          - [X] Nested
        - \[x\] Escaped text
        - [x]word

        [x] Outside a list

        ```mermaid
        flowchart LR
          A["<em>Source</em>"] --> B[Preview]
        ```
        """#)
        try check(extensions.components(separatedBy: "type=\"checkbox\"").count == 4, extensions)
        try check(extensions.contains("disabled checked> Finished"), extensions)
        try check(extensions.contains("disabled> Pending"), extensions)
        try check(extensions.contains("<p>[x] Escaped text</p>"), extensions)
        try check(extensions.contains("<pre data-mermaid><span class=\"code-language\">mermaid</span>"), extensions)
        try check(extensions.contains("A[&quot;&lt;em&gt;Source&lt;/em&gt;&quot;] --&gt; B"), extensions)

        let empty = try MarkdownRenderer.body(for: "")
        try check(empty.isEmpty, "Empty Markdown should return an empty body")

        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let file = directory.appendingPathComponent("Пример.MD")
        let png = directory.appendingPathComponent("example.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRuoAAAAASUVORK5CYII=")!.write(to: png)
        let utf16 = "# Документ\n\n![Описание](example.png) ![Сеть](https://example.com/image.png)"
        try Data([0xFF, 0xFE] + Array(utf16.data(using: .utf16LittleEndian)!)).write(to: file)
        let page = try MarkdownDocument.render(file)
        try check(MarkdownDocument.supports(file), "Uppercase .MD should be accepted")
        try check(page.contains("<h1 id=\"документ\">Документ</h1>"), "UTF-16 text did not render")
        try check(page.contains("<img src=\"data:image/png;base64,") && page.contains("alt=\"Описание\""), "Local image did not render")
        try check(page.contains("Сеть") && !page.contains("example.com"), "Remote image should render as alt text")
        try check(!MarkdownDocument.supports(png), "Image must not open as Markdown")

        try Data([0xEF, 0xBB, 0xBF] + Array("# UTF-8".utf8)).write(to: file)
        let bomPage = try MarkdownDocument.render(file)
        try check(bomPage == "<h1 id=\"utf-8\">UTF-8</h1>", "UTF-8 BOM should be stripped")
        let diagram = "+------+     +------+\n| File | --> | View |\n+------+     +------+"
        try Data(("# ASCII\r\n\r\n```ascii\r\n"
            + diagram.replacingOccurrences(of: "\n", with: "\r\n")
            + "\r\n```\r\n").utf8).write(to: file)
        let asciiPage = try MarkdownDocument.render(file)
        try check(asciiPage.contains("<span class=\"code-language\">ascii</span>"),
                  "The ASCII language label should render")
        let escapedDiagram = diagram.replacingOccurrences(of: ">", with: "&gt;")
        try check(asciiPage.contains("<code>\(escapedDiagram)\n</code>"),
                  "The ASCII diagram should preserve its spaces and line breaks")

        print("Markdown rendering and file checks passed.")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }

    private struct TestFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
