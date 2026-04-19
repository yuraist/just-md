import AppKit

@MainActor
final class DocumentViewController: NSViewController {
    let document: MarkdownDocument
    private let storage = MarkdownTextStorage()
    private let parser = MarkdownParser()
    private(set) var textView: MarkdownTextView?
    private var scrollView: NSScrollView?

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let highlighter = SyntaxHighlighter(parser: parser)
        highlighter.codeHighlighter = CodeBlockHighlighter()
        storage.highlighter = highlighter
        storage.highlightContext = makeContext()

        let textView = MarkdownTextView(storage: storage)
        textView.frame = scroll.contentView.bounds
        textView.minSize = NSSize(width: 0, height: scroll.contentView.bounds.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scroll.documentView = textView

        // Load document text into storage. Apply highlighting synchronously so
        // the file renders fully styled on first paint — the 200ms debounce
        // would otherwise cause a visible blank flash on open.
        if !document.text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: document.text)
            storage.applyHighlightingNow()
        }

        // Forward storage edits back to document.text + change count.
        storage.delegate = self

        self.textView = textView
        self.scrollView = scroll
        self.view = scroll
    }

    private func makeContext() -> HighlightContext {
        return HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
    }
}

extension DocumentViewController: NSTextStorageDelegate {
    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let snapshot = textStorage.string
        Task { @MainActor in
            self.document.text = snapshot
            self.document.updateChangeCount(.changeDone)
        }
    }
}
