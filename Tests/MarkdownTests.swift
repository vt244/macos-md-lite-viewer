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

        let quickLook = try MarkdownRenderer.body(for: """
        ```mermaid
        flowchart LR
          A["<Start>"] -->|approve| B[End] --> C[Next]
        ```

        ```mermaid
        sequenceDiagram
          participant A as Reader
          A->>B: Open
          B-->>A: Preview
        ```

        ```mermaid
        classDiagram
          class Example
        ```
        """, drawDiagram: QuickLookDiagram.render)
        try check(quickLook.components(separatedBy: "class=\"quicklook-diagram\"").count == 3, quickLook)
        try check(quickLook.contains("&lt;Start&gt;") && quickLook.contains(">approve</text>"), quickLook)
        try check(quickLook.contains(">Reader</text>") && quickLook.contains(">Preview</text>"), quickLook)
        try check(quickLook.contains("<pre data-mermaid>") && quickLook.contains("classDiagram"), quickLook)

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

        let includes = directory.appendingPathComponent("chapters", isDirectory: true)
        try FileManager.default.createDirectory(at: includes, withIntermediateDirectories: true)
        try Data("""
        include::details.adoc[tag=excerpt]
        """.utf8).write(to: includes.appendingPathComponent("chapter.adoc"))
        try Data("""
        // tag::excerpt[]
        Nested include.
        // end::excerpt[]
        Excluded paragraph.
        """.utf8).write(to: includes.appendingPathComponent("details.adoc"))
        try Data("== Appendix".utf8).write(to: directory.appendingPathComponent("appendix.adoc"))
        try Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12"><circle cx="6" cy="6" r="5"/></svg>
        """.utf8).write(to: directory.appendingPathComponent("diagram.svg"))
        for fileExtension in ["asciidoc", "asc", "AD", "adoc"] {
            let asciiDoc = directory.appendingPathComponent("example.\(fileExtension)")
            try Data("""
            = AsciiDoc
            :toc:
            :project-name: Viewer

            == Formatting

            {project-name} supports *strong*, _emphasis_, `code`, and footnote:[Notes are numbered.].

            NOTE: Local preview.

            * first
            * second

            [source,swift]
            ----
            print("<tag>")
            ----

            [cols="1,2",options="header"]
            |===
            |Name |Description
            |AsciiDoc |Markup
            |===

            include::chapters/chapter.adoc[]

            image::example.png[Local image]

            image::diagram.svg[Local SVG]

            image::https://example.invalid/image.png[Remote image]

            xref:appendix.adoc#_appendix[Appendix]

            ++++
            <script>alert(1)</script>
            <meta http-equiv="refresh" content="0;url=https://example.invalid">
            <a href="javascript:alert(1)" onclick="alert(1)">Unsafe link</a>
            ++++
            """.utf8).write(to: asciiDoc)
            try check(MarkdownDocument.supports(asciiDoc), "AsciiDoc .\(fileExtension) should open")
            let body = try MarkdownDocument.render(asciiDoc)
            for expected in [
                "<h1>AsciiDoc</h1>", "href=\"#_formatting\"", "Viewer supports <strong>strong</strong>",
                "<em>emphasis</em>", "<code>code</code>", "Notes are numbered.", "Local preview.",
                "<ul>", "language-swift", "print(\"&lt;tag&gt;\")", "<thead>", "Nested include.",
                "data:image/png;base64,", "data:image/svg+xml;base64,", "Remote image",
                "appendix.adoc%23_appendix", "Unsafe link"
            ] {
                try check(body.contains(expected), "Missing AsciiDoc HTML: \(expected)\n\(body)")
            }
            for forbidden in [
                "Excluded paragraph.", "<script", "<meta", "onclick=", "javascript:", "example.invalid"
            ] {
                try check(!body.contains(forbidden), "Unexpected AsciiDoc HTML: \(forbidden)\n\(body)")
            }
        }
        let nestedDocument = includes.appendingPathComponent("isolated.adoc")
        try FileManager.default.createSymbolicLink(
            at: includes.appendingPathComponent("outside.adoc"),
            withDestinationURL: directory.appendingPathComponent("appendix.adoc")
        )
        try Data("""
        = Isolated document

        include::../appendix.adoc[opts=optional]

        include::outside.adoc[opts=optional]

        include::https://example.invalid/outside.adoc[opts=optional]
        """.utf8).write(to: nestedDocument)
        let isolated = try MarkdownDocument.render(nestedDocument)
        try check(!isolated.contains("Appendix"), "AsciiDoc includes must stay inside the document directory")

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
