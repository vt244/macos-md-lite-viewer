import AppKit
import QuickLookUI
import UniformTypeIdentifiers

@objc(MarkdownQuickLookPreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest, completionHandler: @escaping (QLPreviewReply?, Error?) -> Void) {
        let file = request.fileURL
        DispatchQueue.global(qos: .userInitiated).async {
            let hasScope = file.startAccessingSecurityScopedResource()
            defer { if hasScope { file.stopAccessingSecurityScopedResource() } }

            let bundle = Bundle(for: PreviewProvider.self)
            let result = Result { try MarkdownDocument.render(file, bundle: bundle, drawDiagram: QuickLookDiagram.render) }
            DispatchQueue.main.async {
                let page = PreviewPage(bundle: bundle)
                let data: Data
                switch result {
                case .success(let body) where body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                    let title = MarkdownRenderer.escape(L10n.text("status.empty"))
                    data = Data(page.html("<h1>\(title)</h1>", notice: true).utf8)
                case .success(let body):
                    data = Data(page.html(body).utf8)
                case .failure(let error):
                    let title = MarkdownRenderer.escape(L10n.text("status.openFailed"))
                    let details = MarkdownRenderer.escape(error.localizedDescription)
                    data = Data(page.html("<h1>\(title)</h1><p>\(details)</p>", notice: true).utf8)
                }
                let preview = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 770, height: 620)) {
                    _ in data
                }
                completionHandler(preview, nil)
            }
        }
    }
}
