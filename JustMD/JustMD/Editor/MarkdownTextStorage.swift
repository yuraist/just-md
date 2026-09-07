import AppKit

nonisolated final class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()

    var highlighter: SyntaxHighlighter?
    var highlightContext: HighlightContext?

    /// Blocks produced by the most recent highlight pass. Used to diff against
    /// the next parse (incremental restyling) and to re-locate code blocks when
    /// async token coloring lands.
    private(set) var currentBlocks: [Block]?

    /// Accumulated character range touched since the last highlight pass
    /// (post-edit coordinates) and the net length change.
    private var dirtyRange: NSRange?
    private var dirtyDelta = 0

    private var highlightScheduled = false
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
        // Capture before super — the edited* properties reset afterwards.
        let mask = editedMask
        let range = editedRange
        let delta = changeInLength
        super.processEditing()
        guard !isHighlighting, mask.contains(.editedCharacters) else { return }
        accumulateDirty(range: range, delta: delta)
        guard highlighter != nil, highlightContext != nil else { return }
        scheduleHighlight()
    }

    private func accumulateDirty(range: NSRange, delta: Int) {
        dirtyDelta += delta
        guard let existing = dirtyRange else {
            dirtyRange = range
            return
        }
        // `existing` is in pre-this-edit coordinates; shift the part at/after
        // the edit point by this edit's delta, then union with the new range.
        var start = existing.location
        var end = NSMaxRange(existing)
        if start >= range.location { start = max(range.location, start + delta) }
        if end > range.location { end = max(range.location, end + delta) }
        start = min(start, range.location)
        end = max(end, NSMaxRange(range))
        dirtyRange = NSRange(location: max(0, start), length: max(0, end - start))
    }

    /// Highlighting is deferred to the next runloop pass: edits within one
    /// event (typing burst, paste) coalesce, and the pass runs before the next
    /// frame draws — visually instant, unlike the previous 200 ms debounce.
    /// Scheduled on the runloop (in `.common` modes) rather than the main GCD
    /// queue so it also fires during event-tracking (drag/scroll) and inside
    /// nested runloop spins.
    private func scheduleHighlight() {
        guard !highlightScheduled else { return }
        highlightScheduled = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            guard let self else { return }
            self.highlightScheduled = false
            self.runHighlight()
        }
        // CFRunLoopPerformBlock enqueues without waking the runloop — after a
        // keystroke the loop goes back to sleep and the block would only run
        // on the NEXT event, leaving the just-typed text unstyled until then.
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func runHighlight() {
        guard let highlighter, let highlightContext else { return }
        guard !isHighlighting else { return }
        // A stale scheduled tick after a forced synchronous pass has nothing to do.
        if dirtyRange == nil, currentBlocks != nil { return }
        isHighlighting = true
        let edited = dirtyRange
        let delta = dirtyDelta
        dirtyRange = nil
        dirtyDelta = 0
        currentBlocks = highlighter.apply(
            to: self,
            context: highlightContext,
            previousBlocks: currentBlocks,
            editedRange: edited,
            delta: delta
        )
        isHighlighting = false

        // Marker attributes may have appeared/disappeared in the restyled
        // window; glyph hiding is decided at glyph generation, so regenerate
        // glyphs there. (Character edits regenerate glyphs before the
        // highlight pass has tagged the new markers.)
        if let window = highlighter.lastAppliedWindow, window.length > 0,
           NSMaxRange(window) <= length {
            for lm in layoutManagers {
                lm.invalidateGlyphs(forCharacterRange: window, changeInLength: 0, actualCharacterRange: nil)
                lm.invalidateLayout(forCharacterRange: window, actualCharacterRange: nil)
                // Neither call above marks the text view dirty; without an
                // explicit display invalidation the window can show the
                // pre-pass frame (edited paragraph blank) until the next event.
                lm.invalidateDisplay(forCharacterRange: window)
            }
        }
    }

    /// Apply highlighting synchronously over the whole document. Used on
    /// initial load and theme/font changes, where every attribute depends on
    /// the new context.
    func applyHighlightingNow() {
        currentBlocks = nil
        dirtyRange = nil
        dirtyDelta = 0
        runHighlight()
    }
}
