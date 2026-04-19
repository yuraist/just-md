import AppKit

final class MarkdownWindowController: NSWindowController {
    init(document: MarkdownDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        self.contentViewController = DocumentViewController(document: document)
    }

    required init?(coder: NSCoder) { fatalError() }
}
