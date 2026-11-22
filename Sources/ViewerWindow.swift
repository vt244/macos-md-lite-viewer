import AppKit
import WebKit

final class ViewerWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSSearchFieldDelegate, WKNavigationDelegate {
    private static let openItem = NSToolbarItem.Identifier("Open")
    private static let reloadItem = NSToolbarItem.Identifier("Reload")
    private static let searchItem = NSToolbarItem.Identifier("Search")

    private static let page = PreviewPage(bundle: .main)

    private let preview: PreviewWebView
    private let search = NSSearchField()
    private let openPanel: () -> Void
    private let openFiles: ([URL]) -> Void
    private let didClose: (ViewerWindow) -> Void
    private var loadID = UUID()
    private var pendingAnchor: String?
    private var isRendering = false
    private var pageNavigation: WKNavigation?

    private(set) var documentURL: URL?

    init(openPanel: @escaping () -> Void, openFiles: @escaping ([URL]) -> Void,
         didClose: @escaping (ViewerWindow) -> Void) {
        self.openPanel = openPanel
        self.openFiles = openFiles
        self.didClose = didClose

        preview = PreviewWebView(frame: .zero, configuration: Self.page.configuration())

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        super.init(window: window)

        window.delegate = self
        window.title = "Markdown Viewer"
        window.minSize = NSSize(width: 430, height: 300)
        window.contentView = preview
        window.toolbarStyle = .unified
        window.center()

        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.delegate = self
        window.toolbar = toolbar

        preview.navigationDelegate = self
        preview.onDrop = openFiles
        preview.registerForDraggedTypes([.fileURL])
        showHTML("""
        <h1>\(MarkdownRenderer.escape("Откройте файл Markdown"))</h1>
        <p>\(MarkdownRenderer.escape("Перетащите файл в окно или нажмите ⌘O."))</p>
        <a href="markdown-viewer://open">\(MarkdownRenderer.escape("Открыть файл"))</a>
        """, notice: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(openPanel:openFiles:didClose:)") }

    func showDocument(_ url: URL) {
        pendingAnchor = URLComponents(url: url, resolvingAgainstBaseURL: true)?.fragment
        let file = MarkdownDocument.fileURL(for: url)
        if documentURL == file {
            if pageNavigation == nil, !isRendering { jumpToPendingAnchor() }
            return
        }

        documentURL = file
        window?.title = file.lastPathComponent
        window?.representedURL = file
        search.stringValue = ""
        loadDocument()
    }

    @objc func reloadDocument(_ sender: Any? = nil) {
        guard documentURL != nil else { return }
        loadDocument()
    }

    private func loadDocument() {
        guard let documentURL else { return }
        let request = UUID()
        loadID = request
        isRendering = true
        showHTML("<p>\(MarkdownRenderer.escape("Открытие документа…"))</p>", notice: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try MarkdownDocument.render(documentURL) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadID == request else { return }
                self.isRendering = false
                switch result {
                case .success(let body):
                    self.pageNavigation = Self.page.loadDocument(body, in: self.preview)
                case .failure(let error):
                    let message = MarkdownRenderer.escape(error.localizedDescription)
                    self.showHTML("<h1>\(MarkdownRenderer.escape("Не удалось открыть файл"))</h1><p>\(message)</p>", notice: true)
                }
            }
        }
    }

    private func showHTML(_ body: String, notice: Bool) {
        pageNavigation = Self.page.load(body, in: preview, notice: notice)
    }

    func windowWillClose(_ notification: Notification) {
        loadID = UUID()
        didClose(self)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.openItem, Self.reloadItem, .flexibleSpace, Self.searchItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == Self.searchItem {
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.label = "Поиск"
            search.placeholderString = "Поиск по документу"
            search.delegate = self
            search.setAccessibilityLabel("Поиск по документу")
            item.searchField = search
            return item
        }

        let item = NSToolbarItem(itemIdentifier: identifier)
        let isOpen = identifier == Self.openItem
        item.label = isOpen ? "Открыть" : "Обновить"
        item.toolTip = isOpen ? "Открыть файл (⌘O)" : "Перечитать файл (⌘R)"
        item.image = NSImage(systemSymbolName: isOpen ? "folder" : "arrow.clockwise",
                             accessibilityDescription: item.label)
        item.target = self
        item.action = isOpen ? #selector(chooseFile) : #selector(reloadDocument(_:))
        return item
    }

    @objc private func chooseFile() { openPanel() }

    @objc func focusSearch(_ sender: Any? = nil) {
        if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.searchItem })
            as? NSSearchToolbarItem {
            item.beginSearchInteraction()
        }
        window?.makeFirstResponder(search)
        search.selectText(nil)
    }

    @objc func findNext(_ sender: Any? = nil) { find(backwards: false) }
    @objc func findPrevious(_ sender: Any? = nil) { find(backwards: true) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
        return true
    }

    private func find(backwards: Bool) {
        guard !search.stringValue.isEmpty else {
            focusSearch()
            return
        }
        let options = WKFindConfiguration()
        options.backwards = backwards
        options.wraps = true
        preview.find(search.stringValue, configuration: options) { result in
            if !result.matchFound { NSSound.beep() }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === pageNavigation else { return }
        pageNavigation = nil
        if !isRendering { jumpToPendingAnchor() }
    }

    private func jumpToPendingAnchor() {
        guard let anchor = pendingAnchor,
              let encoded = try? JSONEncoder().encode(anchor),
              let literal = String(data: encoded, encoding: .utf8)
        else { return }
        pendingAnchor = nil
        preview.evaluateJavaScript("document.getElementById(\(literal))?.scrollIntoView()")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "about", action.targetFrame?.isMainFrame == true {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        guard action.navigationType == .linkActivated else { return }

        switch url.scheme?.lowercased() {
        case "markdown-viewer" where url.host == "open":
            openPanel()
        case "markdown-file" where url.host == "document":
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value
            if let target, let file = URL(string: target), MarkdownDocument.supports(file) {
                openFiles([file])
            }
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        default: break
        }
    }
}

private final class PreviewWebView: WKWebView {
    var onDrop: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        markdownFiles(in: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        markdownFiles(in: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = markdownFiles(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func markdownFiles(in sender: NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL] ?? []).filter(MarkdownDocument.supports)
    }
}
