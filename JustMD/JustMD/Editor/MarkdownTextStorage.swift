import AppKit

nonisolated final class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()

    var highlighter: SyntaxHighlighter?
    var highlightContext: HighlightContext?

    private var pendingHighlight: DispatchWorkItem?
    /// Highlight runs on the main queue because `HighlightContext` holds `NSColor`
    /// values that resolve via `NSAppearance`, which must be touched from the main
    /// thread. The storage itself is `nonisolated` so the Swift 6 compiler
    /// accepts `self` captures from a `DispatchWorkItem`.
    private let highlightQueue = DispatchQueue.main
    private static let debounceInterval: DispatchTimeInterval = .milliseconds(200)
    private var isHighlighting = false

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        super.processEditing()
        guard !isHighlighting, highlighter != nil, highlightContext != nil else { return }
        scheduleHighlight()
    }

    private func scheduleHighlight() {
        pendingHighlight?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runHighlight()
        }
        pendingHighlight = work
        highlightQueue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func runHighlight() {
        guard let highlighter, let highlightContext else { return }
        guard !isHighlighting else { return }
        isHighlighting = true
        highlighter.apply(to: self, context: highlightContext)
        isHighlighting = false
    }

    /// Apply highlighting synchronously. Used on initial load to avoid a blank
    /// flash while the 200ms debounce window elapses.
    func applyHighlightingNow() {
        pendingHighlight?.cancel()
        pendingHighlight = nil
        runHighlight()
    }
}
