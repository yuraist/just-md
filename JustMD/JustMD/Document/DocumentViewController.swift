import AppKit

final class DocumentViewController: NSViewController {
    let document: MarkdownDocument

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.view = v
    }
}
