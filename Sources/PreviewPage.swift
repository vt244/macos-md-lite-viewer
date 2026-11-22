import WebKit

@MainActor
struct PreviewPage {
    let bundle: Bundle

    func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return configuration
    }

    @discardableResult
    func load(_ body: String, in webView: WKWebView, notice: Bool = false) -> WKNavigation? {
        return webView.loadHTMLString(html(body, notice: notice), baseURL: nil)
    }

    func html(_ body: String, notice: Bool = false) -> String {
        let style = resource("Preview", extension: "css") ?? ""
        let language = notice ? " lang=\"\(L10n.language)\"" : ""
        let pageClass = notice ? "notice" : "document"
        return """
        <!doctype html>
        <html\(language)><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>\(style)</style></head>
        <body><main class="\(pageClass)">\(body)</main></body></html>
        """
    }

    @discardableResult
    func loadDocument(_ body: String, in webView: WKWebView) -> WKNavigation? {
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return load("<h1>\(MarkdownRenderer.escape(L10n.text("status.empty")))</h1>", in: webView, notice: true)
        }
        return load(body, in: webView)
    }

    private func resource(_ name: String, extension suffix: String) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: suffix) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
