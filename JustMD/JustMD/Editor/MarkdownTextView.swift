import AppKit

@MainActor
final class MarkdownTextView: NSTextView {

    convenience init(storage: MarkdownTextStorage) {
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        self.isRichText = false
        self.usesFindBar = false
        self.allowsUndo = true
        self.isAutomaticLinkDetectionEnabled = false
        self.isAutomaticSpellingCorrectionEnabled = false
        self.isAutomaticQuoteSubstitutionEnabled = false
        self.isAutomaticDashSubstitutionEnabled = false
        self.isAutomaticTextReplacementEnabled = false
        self.isAutomaticDataDetectionEnabled = false
        self.isContinuousSpellCheckingEnabled = false
        self.textContainerInset = NSSize(width: 40, height: 32)
    }

    // MARK: - Typing attributes

    // NSTextView normally inherits typing attributes from the character at the
    // caret's left neighbor — for us that means new chars pick up whatever the
    // last highlight pass put there (heading-bold-22pt, code-mono, dimmed marker
    // color, etc.) until the next highlight pass overwrites them ~200ms later.
    // Visible symptom: typing at the end of a heading produces giant bold chars
    // that pop back to normal a moment later.
    //
    // Force typing to start from the base font/color in the current highlight
    // context. The highlighter still re-applies per-block attributes after the
    // edit, so headings remain bold once they're recognized.
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get {
            if let storage = textStorage as? MarkdownTextStorage,
               let context = storage.highlightContext {
                return [
                    .font: context.baseFont,
                    .foregroundColor: context.textColor
                ]
            }
            return super.typingAttributes
        }
        set {
            super.typingAttributes = newValue
        }
    }

    // MARK: - Link handling

    // NSTextView opens links on plain click by default. Markdown authors more
    // commonly want the caret to land inside the link text to edit it and
    // open the URL only on Cmd+click — matching Bear, iA Writer, and Typora.
    override func clicked(onLink link: Any, at charIndex: Int) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let url: URL?
        if let u = link as? URL {
            url = u
        } else if let s = link as? String {
            url = URL(string: s)
        } else {
            url = nil
        }
        if modifiers.contains(.command), let url {
            NSWorkspace.shared.open(url)
        } else {
            // Plain click: move caret into the clicked position rather than
            // navigating. Call super so default accessibility behaviour is
            // preserved if the user has some other modifier held.
            setSelectedRange(NSRange(location: charIndex, length: 0))
        }
    }

    // MARK: - Formatting (Cmd+B / Cmd+I)

    // NSTextView does not expose `toggleBold(_:)` / `toggleItalic(_:)` as
    // Swift-visible methods, so we implement them as @objc first-responder
    // actions with the matching selectors. The menu targets these via
    // `#selector(NSText.toggleBold(_:))`, which resolves to the same selector
    // name at runtime.
    @objc func toggleBold(_ sender: Any?) {
        applyFormatter(delimiter: .bold)
    }

    @objc func toggleItalic(_ sender: Any?) {
        applyFormatter(delimiter: .italic)
    }

    private func applyFormatter(delimiter: MarkdownFormatter.Delimiter) {
        guard let ts = textStorage else { return }
        let oldString = string
        let oldSelection = selectedRange()
        let result = MarkdownFormatter.wrap(source: oldString,
                                            selection: oldSelection,
                                            delimiter: delimiter)

        // Compute the minimal edit by finding common prefix and suffix — preserves
        // undo granularity and avoids re-rendering the entire document.
        let oldNS = oldString as NSString
        let newNS = result.newString as NSString

        var prefixLen = 0
        let maxPrefix = min(oldNS.length, newNS.length)
        while prefixLen < maxPrefix
            && oldNS.character(at: prefixLen) == newNS.character(at: prefixLen) {
            prefixLen += 1
        }
        var suffixLen = 0
        while suffixLen < maxPrefix - prefixLen
            && oldNS.character(at: oldNS.length - 1 - suffixLen)
                == newNS.character(at: newNS.length - 1 - suffixLen) {
            suffixLen += 1
        }
        let editRange = NSRange(location: prefixLen,
                                length: oldNS.length - prefixLen - suffixLen)
        let replacement = newNS.substring(with: NSRange(location: prefixLen,
                                                        length: newNS.length - prefixLen - suffixLen))

        ts.replaceCharacters(in: editRange, with: replacement)
        setSelectedRange(result.newSelection)
    }
}
