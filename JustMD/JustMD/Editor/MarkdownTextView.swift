import AppKit

@MainActor
final class MarkdownTextView: NSTextView {

    convenience init(storage: MarkdownTextStorage) {
        let layoutManager = HiddenMarkerLayoutManager()
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

    override func didChangeText() {
        super.didChangeText()
        updateActiveLine()
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateActiveLine()
    }

    private func updateActiveLine() {
        guard let lm = layoutManager as? HiddenMarkerLayoutManager else { return }
        let caret = selectedRange().location
        let s = string as NSString
        let safeCaret = min(caret, s.length)
        let line = s.lineRange(for: NSRange(location: safeCaret, length: 0))
        if !NSEqualRanges(lm.activeLineRange, line) {
            lm.activeLineRange = line
            lm.invalidateGlyphs(
                forCharacterRange: NSRange(location: 0, length: s.length),
                changeInLength: 0,
                actualCharacterRange: nil
            )
            lm.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: s.length))
            if let container = textContainer {
                lm.ensureLayout(for: container)
            }
            needsDisplay = true
        }
    }
}
