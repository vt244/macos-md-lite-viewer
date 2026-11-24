import AppKit
import QuickLookUI
import WebKit

@objc(MarkdownQuickLookPreviewController)
final class PreviewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private static let resources = Bundle(for: PreviewController.self)
    private static let initialSize = NSSize(width: 770, height: 620)
    private let page = PreviewPage(bundle: resources)
    private lazy var preview = WKWebView(
        frame: NSRect(origin: .zero, size: Self.initialSize), configuration: page.configuration()
    )
    private var pendingNavigation: WKNavigation?
    private var previewReady: ((Error?) -> Void)?

    override func loadView() {
        // Quick Look prepares the document before presenting it. Give WebKit a
        // viewport for that first layout, then follow the host's actual size.
        let container = NSView(frame: NSRect(origin: .zero, size: Self.initialSize))
        preview.navigationDelegate = self
        preview.autoresizingMask = [.width, .height]
        container.addSubview(preview)
        view = container
        preferredContentSize = Self.initialSize
    }

    func preparePreviewOfFile(at file: URL, completionHandler: @escaping (Error?) -> Void) {
        let bundle = Self.resources
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hasScope = file.startAccessingSecurityScopedResource()
            defer { if hasScope { file.stopAccessingSecurityScopedResource() } }

            let result = Result { try MarkdownDocument.render(file, bundle: bundle) }
            DispatchQueue.main.async {
                guard let self else {
                    completionHandler(CancellationError())
                    return
                }
                _ = self.view
                self.previewReady = completionHandler
                switch result {
                case .success(let body):
                    self.pendingNavigation = self.page.loadDocument(body, in: self.preview)
                case .failure(let error):
                    let title = MarkdownRenderer.escape(L10n.text("status.openFailed"))
                    let details = MarkdownRenderer.escape(error.localizedDescription)
                    self.pendingNavigation = self.page.load(
                        "<h1>\(title)</h1><p>\(details)</p>", in: self.preview, notice: true
                    )
                }
                if self.pendingNavigation == nil { self.finishPreview(URLError(.cannotDecodeContentData)) }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if pendingNavigation === navigation { finishPreview(nil) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if pendingNavigation === navigation { finishPreview(error) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if pendingNavigation === navigation { finishPreview(error) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishPreview(WKError(.webContentProcessTerminated))
    }

    private func finishPreview(_ error: Error?) {
        pendingNavigation = nil
        let completion = previewReady
        previewReady = nil
        completion?(error)
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
        if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        }
    }
}
