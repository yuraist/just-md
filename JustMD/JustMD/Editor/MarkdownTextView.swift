import AppKit

@MainActor
final class MarkdownTextView: NSTextView {

    private(set) var markerVisibility: MarkerVisibilityController?

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
