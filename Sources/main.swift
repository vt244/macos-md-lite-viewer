import AppKit
import UniformTypeIdentifiers

final class ViewerApplication: NSObject, NSApplicationDelegate {
    private var windows = [ViewerWindow]()
    private var openPanel: NSOpenPanel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        installMenus()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if windows.isEmpty { makeWindow().showWindow(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showFiles(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { makeWindow().showWindow(nil) }
        return true
    }

    @objc private func chooseFile(_ sender: Any? = nil) {
        guard openPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Открыть Markdown"
        panel.message = "Выберите один или несколько файлов Markdown."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MarkdownDocument.extensions.compactMap { UTType(filenameExtension: $0) }
        openPanel = panel

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.openPanel = nil
            if response == .OK { self?.showFiles(panel.urls) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private func showFiles(_ urls: [URL]) {
        let supported = urls.filter(MarkdownDocument.supports)
        for url in supported {
            let file = MarkdownDocument.fileURL(for: url)
            let controller = windows.first(where: { $0.documentURL == file })
                ?? windows.first(where: { $0.documentURL == nil })
                ?? makeWindow()
            controller.showDocument(url)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        if !supported.isEmpty { NSApp.activate(ignoringOtherApps: true) }
    }

    private func makeWindow() -> ViewerWindow {
        let controller = ViewerWindow(
            openPanel: { [weak self] in self?.chooseFile() },
            openFiles: { [weak self] in self?.showFiles($0) },
            didClose: { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        )
        if let origin = windows.last?.window?.frame.origin, let window = controller.window {
            let offset = 24.0
            window.setFrameOrigin(NSPoint(x: origin.x + offset, y: origin.y - offset))
        }
        windows.append(controller)
        return controller
    }

    private func installMenus() {
        let main = NSMenu()

        func menu(_ title: String, items: [NSMenuItem]) {
            let root = NSMenuItem()
            let submenu = NSMenu(title: title)
            for item in items { submenu.addItem(item) }
            root.submenu = submenu
            main.addItem(root)
        }

        func item(_ title: String, _ action: Selector, _ key: String,
                  target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }

        menu("Markdown Viewer", items: [
            item("О Markdown Viewer", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", target: NSApp),
            .separator(),
            item("Завершить Markdown Viewer", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        ])
        menu("Файл", items: [
            item("Открыть…", #selector(chooseFile(_:)), "o", target: self),
            item("Перечитать файл", #selector(ViewerWindow.reloadDocument(_:)), "r"),
            .separator(),
            item("Закрыть окно", #selector(NSWindow.performClose(_:)), "w")
        ])
        menu("Правка", items: [
            item("Вырезать", #selector(NSText.cut(_:)), "x"),
            item("Копировать", #selector(NSText.copy(_:)), "c"),
            item("Вставить", #selector(NSText.paste(_:)), "v"),
            item("Выделить всё", #selector(NSResponder.selectAll(_:)), "a"),
            .separator(),
            item("Найти…", #selector(ViewerWindow.focusSearch(_:)), "f"),
            item("Найти далее", #selector(ViewerWindow.findNext(_:)), "g"),
            item("Найти ранее", #selector(ViewerWindow.findPrevious(_:)), "g", modifiers: [.command, .shift])
        ])
        NSApp.mainMenu = main
    }
}

let application = NSApplication.shared
let delegate = ViewerApplication()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
