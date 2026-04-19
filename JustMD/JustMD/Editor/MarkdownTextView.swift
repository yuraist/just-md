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
