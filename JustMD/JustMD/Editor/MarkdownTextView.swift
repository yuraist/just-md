import AppKit

@MainActor
final class MarkdownTextView: NSTextView {

    private(set) var markerVisibility: MarkerVisibilityController?
    private var checkboxTrackingArea: NSTrackingArea?
    private var isShowingCheckboxCursor = false

    convenience init(storage: MarkdownTextStorage) {
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)

        // Bear-style marker hiding. Glyph generation must stay on the main
        // thread for the delegate, so background layout is disabled — fine for
        // an editor that restyles incrementally anyway.
        let visibility = MarkerVisibilityController()
        visibility.layoutManager = layoutManager
        layoutManager.delegate = visibility
        layoutManager.backgroundLayoutEnabled = false
        layoutManager.visibility = visibility
        self.markerVisibility = visibility

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

    // NSTextView snapshots typing attributes from the caret's left neighbor at
    // selection-change time. With our restyle pass running asynchronously (one
    // runloop pass after the edit), that snapshot is routinely STALE — it was
    // taken before the neighbor got its heading/bold/code styling, so every
    // character typed in a heading would start out base-sized and only pop to
    // the right size on the next pass. Re-read the neighbor's live attributes
    // at insertion time instead, then strip what must not leak into new text:
    // bookkeeping attributes, the dimmed marker color, links, and span-edge
    // styles (code background, strikethrough) once the caret has left the span.
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get {
            var attrs = super.typingAttributes
            guard let storage = textStorage as? MarkdownTextStorage,
                  let context = storage.highlightContext else { return attrs }

            let caret = selectedRange().location
            if caret > 0, caret <= storage.length {
                let live = storage.attributes(at: caret - 1, effectiveRange: nil)
                attrs[.font] = live[.font]
                attrs[.foregroundColor] = live[.foregroundColor]
                attrs[.backgroundColor] = live[.backgroundColor]
                attrs[.strikethroughStyle] = live[.strikethroughStyle]
                attrs[.paragraphStyle] = live[.paragraphStyle]
            }

            attrs.removeValue(forKey: MarkdownAttribute.marker)
            attrs.removeValue(forKey: MarkdownAttribute.headingHash)
            attrs.removeValue(forKey: MarkdownAttribute.codeLanguage)
            attrs.removeValue(forKey: .link)
            if let color = attrs[.foregroundColor] as? NSColor, color == context.secondaryColor {
                attrs[.foregroundColor] = context.textColor
            }
            // Span-edge rule: keep the code background / strikethrough only
            // while the caret is strictly inside the span (the character at
            // the caret carries the attribute too).
            if attrs[.backgroundColor] != nil {
                let insideCode = caret < storage.length
                    && storage.attribute(.backgroundColor, at: caret, effectiveRange: nil) != nil
                if !insideCode {
                    attrs.removeValue(forKey: .backgroundColor)
                    attrs[.font] = context.baseFont
                }
            }
            if attrs[.strikethroughStyle] != nil {
                let insideStrike = caret < storage.length
                    && storage.attribute(.strikethroughStyle, at: caret, effectiveRange: nil) != nil
                if !insideStrike {
                    attrs.removeValue(forKey: .strikethroughStyle)
                }
            }
            if attrs[.font] == nil { attrs[.font] = context.baseFont }
            if attrs[.foregroundColor] == nil { attrs[.foregroundColor] = context.textColor }
            return attrs
        }
        set {
            super.typingAttributes = newValue
        }
    }

    // MARK: - Selection → marker visibility

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if let storage = textStorage, let first = ranges.first?.rangeValue {
            markerVisibility?.updateActiveRange(for: first, in: storage)
        }
    }

    // MARK: - Task checkboxes

    // Clicking a rendered ☑/□ toggles the task state in the source. On the
    // active paragraph the raw `- [x]` shows instead, and clicks fall through
    // to normal caret placement for editing.
    override func mouseDown(with event: NSEvent) {
        if handleCheckboxClick(event) { return }
        super.mouseDown(with: event)
    }

    private func handleCheckboxClick(_ event: NSEvent) -> Bool {
        guard let dashIndex = checkboxDashIndex(at: convert(event.locationInWindow, from: nil)) else {
            return false
        }
        return toggleTaskCheckbox(atDash: dashIndex)
    }

    /// Character index of the checkbox (the task item's dash) under `point`
    /// (view coordinates), or nil when the point isn't on a rendered checkbox.
    func checkboxDashIndex(at viewPoint: NSPoint) -> Int? {
        guard let lm = layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return nil }
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = lm.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < storage.length,
              storage.attribute(MarkdownAttribute.taskCheckbox, at: charIndex, effectiveRange: nil) != nil
        else { return nil }
        // On the active paragraph the raw markdown shows — no checkbox there.
        if let visibility = markerVisibility, NSLocationInRange(charIndex, visibility.activeRange) {
            return nil
        }
        // characterIndex(for:) returns the *nearest* character; require the
        // click to actually land on the checkbox glyph.
        let glyphIndex = lm.glyphIndexForCharacter(at: charIndex)
        let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
            .insetBy(dx: -3, dy: -3)
        guard glyphRect.contains(containerPoint) else { return nil }
        return charIndex
    }

    /// Flips `[ ]` ↔ `[x]` for the task item whose dash is at `dashIndex`.
    /// Routed through the undo stack; the caret stays where it is.
    @discardableResult
    func toggleTaskCheckbox(atDash dashIndex: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let ns = storage.string as NSString
        guard dashIndex < ns.length else { return false }
        let line = ns.paragraphRange(for: NSRange(location: dashIndex, length: 0))
        var bracket = dashIndex + 1
        while bracket < NSMaxRange(line), ns.character(at: bracket) != 0x5B { bracket += 1 }  // [
        let stateIndex = bracket + 1
        guard stateIndex + 1 < NSMaxRange(line),
              ns.character(at: stateIndex + 1) == 0x5D else { return false }  // ]
        let current = ns.character(at: stateIndex)
        let replacement = (current == 0x78 || current == 0x58) ? " " : "x"  // x / X
        let range = NSRange(location: stateIndex, length: 1)
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
    }

    // MARK: - Cursor feedback

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = checkboxTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        checkboxTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let overCheckbox = checkboxDashIndex(at: convert(event.locationInWindow, from: nil)) != nil
        if overCheckbox {
            if !isShowingCheckboxCursor {
                isShowingCheckboxCursor = true
                NSCursor.pointingHand.set()
            }
            return  // keep the hand; don't let the I-beam machinery run
        }
        if isShowingCheckboxCursor {
            isShowingCheckboxCursor = false
            NSCursor.iBeam.set()
        }
        super.mouseMoved(with: event)
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

        // Route through shouldChangeText/didChangeText so the edit lands on the
        // undo stack — direct storage mutation would make Cmd+Z skip it.
        guard shouldChangeText(in: editRange, replacementString: replacement) else { return }
        ts.replaceCharacters(in: editRange, with: replacement)
        didChangeText()
        setSelectedRange(result.newSelection)
    }
}
