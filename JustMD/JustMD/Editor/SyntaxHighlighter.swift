import AppKit

nonisolated enum MarkdownAttribute {
    static let marker = NSAttributedString.Key("com.justmd.marker")
    static let headingHash = NSAttributedString.Key("com.justmd.headingHash")
    static let codeLanguage = NSAttributedString.Key("com.justmd.codeLanguage")
}

nonisolated struct HighlightContext {
    var baseFont: NSFont
    var textColor: NSColor
    var secondaryColor: NSColor
    var accentColor: NSColor
    var codeFont: NSFont
    var codeBackground: NSColor

    init(
        baseFont: NSFont,
        textColor: NSColor,
        secondaryColor: NSColor,
        accentColor: NSColor,
        codeFont: NSFont,
        codeBackground: NSColor
    ) {
        self.baseFont = baseFont
        self.textColor = textColor
        self.secondaryColor = secondaryColor
        self.accentColor = accentColor
        self.codeFont = codeFont
        self.codeBackground = codeBackground
    }
}

/// Weakly carries the highlighter/storage pair into the `@MainActor` async
/// code-highlight completion. Both objects are main-thread-confined; the box
/// only exists to tell the compiler so.
nonisolated private struct WeakApplyTarget: @unchecked Sendable {
    weak var highlighter: SyntaxHighlighter?
    weak var storage: NSTextStorage?
}

nonisolated final class SyntaxHighlighter {
    let parser: MarkdownParser

    /// Optional code-block highlighter. When set, `.codeBlock` content ranges
    /// get per-token foreground colors overlaid on top of the mono font and
    /// code background. Cached results apply synchronously during the pass;
    /// misses are computed in the background and overlaid when they land.
    var codeHighlighter: CodeBlockHighlighter?

    /// Block content → block-relative inline spans. Typing edits one block;
    /// every other block's substring is unchanged and hits this cache instead
    /// of paying a second cmark parse per block per keystroke.
    private var spanCache: [String: [InlineSpan]] = [:]

    /// Test hooks.
    private(set) var lastAppliedWindow: NSRange?
    private(set) var inlineParseMisses = 0

    init(parser: MarkdownParser) {
        self.parser = parser
    }

    /// Applies markdown styling. With `previousBlocks` + `editedRange`, only
    /// the changed window is restyled (attributes of moved-but-unchanged text
    /// travel with the characters for free); otherwise the full document is.
    /// Returns the fresh block list for the caller to feed back next pass.
    @discardableResult
    func apply(
        to storage: NSTextStorage,
        context: HighlightContext,
        previousBlocks: [Block]? = nil,
        editedRange: NSRange? = nil,
        delta: Int = 0
    ) -> [Block] {
        let source = storage.string
        let doc = parser.parse(source)
        let full = NSRange(location: 0, length: storage.length)

        let window: NSRange
        if let previousBlocks, let editedRange {
            window = BlockDiff.changedWindow(
                old: previousBlocks,
                new: doc.blocks,
                delta: delta,
                editedRange: editedRange,
                newLength: storage.length
            )
        } else {
            window = full
        }
        lastAppliedWindow = window
        guard window.length > 0 else { return doc.blocks }

        storage.beginEditing()
        storage.setAttributes(baseAttributes(context), range: window)
        for block in doc.blocks {
            let r = block.range
            guard NSMaxRange(r) > window.location, r.location < NSMaxRange(window) else { continue }
            applyBlock(block, source: source, storage: storage, context: context)
        }
        // Dim all marker-tagged ranges with the secondary color. This makes the
        // syntax characters (`#`, `*`, `_`, `~`, link URL, code fences, etc.)
        // visually recessive — similar to iA Writer. The layout layer hides
        // them entirely off the active paragraph.
        storage.enumerateAttribute(MarkdownAttribute.marker, in: window, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            storage.addAttribute(.foregroundColor, value: context.secondaryColor, range: range)
        }
        storage.endEditing()
        return doc.blocks
    }

    // MARK: - Font trait helpers

    /// Returns a font matching `base` with the given symbolic traits applied. Falls
    /// back to `base` if the descriptor cannot produce a valid font.
    private func font(_ base: NSFont, traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    /// Adds `adding` traits to `base`'s existing traits (so combining bold + italic
    /// works). Falls back to `base` if the descriptor cannot produce a valid font.
    private func font(_ base: NSFont, addingTraits adding: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let combined = base.fontDescriptor.symbolicTraits.union(adding)
        let descriptor = base.fontDescriptor.withSymbolicTraits(combined)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    private func baseAttributes(_ ctx: HighlightContext) -> [NSAttributedString.Key: Any] {
        return [.font: ctx.baseFont, .foregroundColor: ctx.textColor]
    }

    private func applyBlock(_ block: Block, source: String, storage: NSTextStorage, context: HighlightContext) {
        switch block {
        case .heading(let level, let range, let markerRange):
            let size = context.baseFont.pointSize + CGFloat(max(0, 8 - level)) * 2
            let resized = NSFont(descriptor: context.baseFont.fontDescriptor, size: size) ?? context.baseFont
            let bold = font(resized, addingTraits: .bold)
            if NSMaxRange(range) <= storage.length {
                storage.addAttribute(.font, value: bold, range: range)
            }
            if NSMaxRange(markerRange) <= storage.length {
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: markerRange)
                storage.addAttribute(MarkdownAttribute.headingHash, value: true, range: markerRange)
            }

        case .paragraph:
            break

        case .codeBlock(let language, let range, let contentRange, let fenceRanges):
            if NSMaxRange(range) <= storage.length {
                storage.addAttribute(.font, value: context.codeFont, range: range)
                storage.addAttribute(.backgroundColor, value: context.codeBackground, range: range)
            }
            for fenceRange in fenceRanges where NSMaxRange(fenceRange) <= storage.length {
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: fenceRange)
            }
            if let language, !language.isEmpty, NSMaxRange(contentRange) <= storage.length {
                storage.addAttribute(MarkdownAttribute.codeLanguage, value: language, range: contentRange)
            }
            if let codeHighlighter,
               contentRange.length > 0,
               NSMaxRange(contentRange) <= storage.length {
                let codeText = (source as NSString).substring(with: contentRange)
                if let cached = codeHighlighter.cachedHighlight(codeText, language: language) {
                    overlayTokenColors(cached, on: storage, contentRange: contentRange)
                } else {
                    let target = WeakApplyTarget(highlighter: self, storage: storage)
                    codeHighlighter.highlightAsync(codeText, language: language) { result in
                        guard let highlighter = target.highlighter,
                              let storage = target.storage,
                              let result else { return }
                        highlighter.applyAsyncCodeResult(result, code: codeText, language: language, to: storage)
                    }
                }
            }

        case .blockQuote(let range):
            guard NSMaxRange(range) <= storage.length else { break }
            storage.addAttribute(.foregroundColor, value: context.secondaryColor, range: range)
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 16
            style.headIndent = 16
            storage.addAttribute(.paragraphStyle, value: style, range: range)

        case .list(_, let items, _):
            for item in items where NSMaxRange(item.markerRange) <= storage.length {
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: item.markerRange)
            }

        case .thematicBreak(let range):
            if NSMaxRange(range) <= storage.length {
                storage.addAttribute(.foregroundColor, value: context.secondaryColor, range: range)
            }

        case .table(let range):
            if NSMaxRange(range) <= storage.length {
                storage.addAttribute(.font, value: context.codeFont, range: range)
            }

        case .html:
            break
        }

        // Apply inline spans for blocks that contain inline content.
        switch block {
        case .heading, .paragraph, .blockQuote:
            let nsSource = source as NSString
            for span in spans(for: block, source: nsSource) {
                applySpan(span, storage: storage, context: context)
            }
        default:
            break
        }
    }

    // MARK: - Inline spans (cached)

    private func spans(for block: Block, source nsSource: NSString) -> [InlineSpan] {
        guard let blockRange = parser.inlineRange(of: block),
              blockRange.length > 0,
              blockRange.location >= 0,
              NSMaxRange(blockRange) <= nsSource.length else { return [] }
        let substring = nsSource.substring(with: blockRange)
        if let cached = spanCache[substring] {
            return cached.map { $0.offset(by: blockRange.location) }
        }
        inlineParseMisses += 1
        let relative = parser.inlineSpans(forBlockContent: substring)
        if spanCache.count > 1024 { spanCache.removeAll(keepingCapacity: true) }
        spanCache[substring] = relative
        return relative.map { $0.offset(by: blockRange.location) }
    }

    // MARK: - Code token colors

    private func overlayTokenColors(_ highlighted: NSAttributedString, on storage: NSTextStorage, contentRange: NSRange) {
        // Only overlay if the highlighted text length matches the content
        // range length, otherwise the offset mapping is unsafe.
        guard highlighted.length == contentRange.length,
              NSMaxRange(contentRange) <= storage.length else { return }
        let fullHL = NSRange(location: 0, length: highlighted.length)
        highlighted.enumerateAttribute(.foregroundColor, in: fullHL, options: []) { value, subRange, _ in
            guard let color = value as? NSColor else { return }
            let mappedRange = NSRange(
                location: contentRange.location + subRange.location,
                length: subRange.length
            )
            if NSMaxRange(mappedRange) <= storage.length {
                storage.addAttribute(.foregroundColor, value: color, range: mappedRange)
            }
        }
    }

    /// Applies an asynchronously computed token coloring. The document may have
    /// changed while the JSContext ran, so re-locate code blocks by content
    /// instead of trusting the original range.
    private func applyAsyncCodeResult(
        _ highlighted: NSAttributedString,
        code: String,
        language: String?,
        to storage: NSTextStorage
    ) {
        guard let markdownStorage = storage as? MarkdownTextStorage,
              let blocks = markdownStorage.currentBlocks else { return }
        let nsSource = storage.string as NSString
        storage.beginEditing()
        for block in blocks {
            guard case .codeBlock(let lang, _, let contentRange, _) = block,
                  lang == language,
                  contentRange.length > 0,
                  NSMaxRange(contentRange) <= nsSource.length,
                  nsSource.substring(with: contentRange) == code else { continue }
            overlayTokenColors(highlighted, on: storage, contentRange: contentRange)
        }
        storage.endEditing()
    }

    private func applySpan(_ span: InlineSpan, storage: NSTextStorage, context: HighlightContext) {
        let storageLength = storage.length
        func safe(_ range: NSRange) -> NSRange? {
            guard range.location >= 0, NSMaxRange(range) <= storageLength else { return nil }
            return range
        }

        switch span {
        case .bold(let range, let markerRanges):
            guard let r = safe(range) else { return }
            if let currentFont = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont {
                let bolded = font(currentFont, addingTraits: .bold)
                storage.addAttribute(.font, value: bolded, range: r)
            }
            for m in markerRanges {
                if let mr = safe(m) {
                    storage.addAttribute(MarkdownAttribute.marker, value: true, range: mr)
                }
            }

        case .italic(let range, let markerRanges):
            guard let r = safe(range) else { return }
            if let currentFont = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont {
                let italicized = font(currentFont, addingTraits: .italic)
                storage.addAttribute(.font, value: italicized, range: r)
            }
            for m in markerRanges {
                if let mr = safe(m) {
                    storage.addAttribute(MarkdownAttribute.marker, value: true, range: mr)
                }
            }

        case .strike(let range, let markerRanges):
            guard let r = safe(range) else { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            for m in markerRanges {
                if let mr = safe(m) {
                    storage.addAttribute(MarkdownAttribute.marker, value: true, range: mr)
                }
            }

        case .inlineCode(let range, let markerRanges):
            guard let r = safe(range) else { return }
            storage.addAttribute(.font, value: context.codeFont, range: r)
            storage.addAttribute(.backgroundColor, value: context.codeBackground, range: r)
            for m in markerRanges {
                if let mr = safe(m) {
                    storage.addAttribute(MarkdownAttribute.marker, value: true, range: mr)
                }
            }

        case .link(let range, let urlRange, let markerRanges, let url):
            guard let r = safe(range) else { return }
            if let url, let ur = safe(urlRange) {
                storage.addAttribute(.link, value: url, range: r)
                storage.addAttribute(.foregroundColor, value: context.accentColor, range: r)
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: ur)
            } else {
                storage.addAttribute(.foregroundColor, value: context.accentColor, range: r)
            }
            for m in markerRanges {
                if let mr = safe(m) {
                    storage.addAttribute(MarkdownAttribute.marker, value: true, range: mr)
                }
            }

        case .image(let range, _, _, _):
            guard let r = safe(range) else { return }
            storage.addAttribute(MarkdownAttribute.marker, value: true, range: r)
        }
    }
}
