import AppKit

nonisolated enum MarkdownAttribute {
    static let marker = NSAttributedString.Key("com.justmd.marker")
    static let headingHash = NSAttributedString.Key("com.justmd.headingHash")
    static let codeLanguage = NSAttributedString.Key("com.justmd.codeLanguage")
    /// Tagged on `---` ranges; the layout manager draws a separator rule when
    /// the raw dashes are hidden.
    static let thematicBreak = NSAttributedString.Key("com.justmd.thematicBreak")
    /// Tagged on blockquote ranges; the layout manager draws the accent bar.
    static let blockQuote = NSAttributedString.Key("com.justmd.blockQuote")
    /// Tagged on the `-`/`*`/`+` of unordered list items; rendered as `•` off
    /// the active paragraph.
    static let listBullet = NSAttributedString.Key("com.justmd.listBullet")
    /// Tagged on the `[` of a task item, value = Bool (checked); rendered as
    /// ☑/□ off the active paragraph.
    static let taskCheckbox = NSAttributedString.Key("com.justmd.taskCheckbox")
    /// Tagged on a table's alignment row (`|---|---|`); hidden off the active
    /// paragraph and drawn as a horizontal rule by the layout manager.
    static let tableSeparator = NSAttributedString.Key("com.justmd.tableSeparator")
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
                // Hidden fence lines must not paint an empty background band —
                // including their trailing newline, which alone is enough for
                // TextKit to fill the whole line fragment.
                var clear = fenceRange
                if NSMaxRange(clear) < storage.length,
                   (storage.string as NSString).character(at: NSMaxRange(clear)) == 0x0A {
                    clear.length += 1
                }
                storage.removeAttribute(.backgroundColor, range: clear)
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
            storage.addAttribute(MarkdownAttribute.blockQuote, value: true, range: range)
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 16
            style.headIndent = 16
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            tagBlockquoteMarkers(in: range, source: source, storage: storage)

        case .list(let ordered, let items, _):
            // Bullets/numbers stay visible (accent-tinted) — hiding them would
            // leave bullet-less lines. Wrapped lines hang under the text, not
            // under the marker. Off the active paragraph, dashes render as •
            // and task brackets as ☑/□ (glyph substitution in the layout
            // delegate, keyed by the attributes set here).
            let ns = source as NSString
            for item in items where NSMaxRange(item.markerRange) <= storage.length {
                storage.addAttribute(.foregroundColor, value: context.accentColor, range: item.markerRange)

                let indent: CGFloat
                if let taskState = item.taskState {
                    tagTaskCheckbox(item: item, checked: taskState == .checked,
                                    source: ns, storage: storage, context: context)
                    // Visible prefix off the active line is "☑ ", not "- [x] ".
                    indent = ("☑ " as NSString).size(
                        withAttributes: [.font: NSFont.systemFont(ofSize: context.baseFont.pointSize)]
                    ).width
                } else {
                    if !ordered {
                        tagBulletChar(item: item, source: ns, storage: storage)
                    }
                    let lineStart = ns.lineRange(for: NSRange(location: item.markerRange.location, length: 0)).location
                    let prefixRange = NSRange(location: lineStart, length: NSMaxRange(item.markerRange) - lineStart)
                    guard prefixRange.length > 0, NSMaxRange(prefixRange) <= ns.length else { continue }
                    let prefix = ns.substring(with: prefixRange)
                    indent = (prefix as NSString).size(withAttributes: [.font: context.baseFont]).width
                }
                let style = NSMutableParagraphStyle()
                style.headIndent = indent
                if NSMaxRange(item.range) <= storage.length {
                    storage.addAttribute(.paragraphStyle, value: style, range: item.range)
                }
            }

        case .thematicBreak(let range):
            if NSMaxRange(range) <= storage.length {
                storage.addAttribute(.foregroundColor, value: context.secondaryColor, range: range)
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: range)
                storage.addAttribute(MarkdownAttribute.thematicBreak, value: true, range: range)
            }

        case .table(let range):
            if NSMaxRange(range) <= storage.length {
                storage.addAttribute(.font, value: context.codeFont, range: range)
                styleTable(in: range, source: source, storage: storage, context: context)
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

    // MARK: - Block chrome helpers

    /// Tags the single `-`/`*`/`+` character of an unordered item for bullet
    /// substitution.
    private func tagBulletChar(item: ListItem, source ns: NSString, storage: NSTextStorage) {
        var i = item.markerRange.location
        let end = min(NSMaxRange(item.markerRange), ns.length)
        while i < end, ns.character(at: i) == 0x20 { i += 1 }
        guard i < end else { return }
        let c = ns.character(at: i)
        guard c == 0x2D || c == 0x2A || c == 0x2B else { return }  // - * +
        storage.addAttribute(MarkdownAttribute.listBullet, value: true, range: NSRange(location: i, length: 1))
    }

    /// For `- [x] ` task markers: the *dash* renders as the checkbox glyph and
    /// the ` [x]` tail hides off the active paragraph. The dash must stay a
    /// visible glyph — a paragraph whose leading glyphs are all `.null` gets
    /// laid out with `headIndent` applied to its first line. The dash gets the
    /// system font; the serif and mono faces lack the checkbox glyphs.
    private func tagTaskCheckbox(
        item: ListItem,
        checked: Bool,
        source ns: NSString,
        storage: NSTextStorage,
        context: HighlightContext
    ) {
        let start = item.markerRange.location
        let end = min(NSMaxRange(item.markerRange), ns.length)
        var dash = start
        while dash < end, ns.character(at: dash) == 0x20 { dash += 1 }
        guard dash < end else { return }
        let dashChar = ns.character(at: dash)
        guard dashChar == 0x2D || dashChar == 0x2A || dashChar == 0x2B else { return }  // - * +
        var bracket = dash + 1
        while bracket < end, ns.character(at: bracket) != 0x5B { bracket += 1 }  // [
        guard bracket + 2 < end, ns.character(at: bracket + 2) == 0x5D else { return }  // ]

        let box = NSRange(location: dash, length: 1)
        storage.addAttribute(MarkdownAttribute.taskCheckbox, value: checked, range: box)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: context.baseFont.pointSize), range: box)
        storage.addAttribute(
            .foregroundColor,
            value: checked ? context.accentColor : context.secondaryColor,
            range: box
        )
        // Hide " [x]" between the checkbox and the trailing space.
        let tail = NSRange(location: dash + 1, length: (bracket + 3) - (dash + 1))
        storage.addAttribute(MarkdownAttribute.marker, value: true, range: tail)
    }

    /// Tags the leading `>` markers of every blockquote line so they hide off
    /// the active paragraph (the drawn accent bar carries the meaning).
    private func tagBlockquoteMarkers(in range: NSRange, source: String, storage: NSTextStorage) {
        let gt: UInt16 = 0x3E      // >
        let space: UInt16 = 0x20
        let ns = source as NSString
        var loc = range.location
        let upper = min(NSMaxRange(range), ns.length)
        while loc < upper {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            var i = line.location
            var markerEnd = i
            var leadingSpaces = 0
            scan: while i < min(NSMaxRange(line), upper) {
                switch ns.character(at: i) {
                case gt:
                    leadingSpaces = 0
                    i += 1
                    // A single space after `>` belongs to the marker.
                    if i < NSMaxRange(line), ns.character(at: i) == space { i += 1 }
                    markerEnd = i
                case space where leadingSpaces < 3 && markerEnd == line.location:
                    leadingSpaces += 1
                    i += 1
                default:
                    break scan
                }
            }
            if markerEnd > line.location {
                let markerRange = NSRange(location: line.location, length: markerEnd - line.location)
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: markerRange)
            }
            loc = NSMaxRange(line)
        }
    }

    /// Editor-mode table presentation, without touching the text: pipes dim,
    /// the alignment row hides (a rule is drawn in its place), the header row
    /// goes bold, and cells get `.kern` padding on their last character so
    /// the pipes line up column-by-column across rows — the mono font makes
    /// the result read as a real grid.
    private func styleTable(in range: NSRange, source: String, storage: NSTextStorage, context: HighlightContext) {
        let pipe: UInt16 = 0x7C    // |
        let dash: UInt16 = 0x2D    // -
        let colon: UInt16 = 0x3A   // :
        let space: UInt16 = 0x20
        let lf: UInt16 = 0x0A
        let cr: UInt16 = 0x0D
        let ns = source as NSString
        let upper = min(NSMaxRange(range), ns.length)

        struct TableRow {
            var line: NSRange
            var pipes: [Int]
            var isAlignment: Bool
        }
        var rows: [TableRow] = []
        var loc = range.location
        while loc < upper {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let lineEnd = min(NSMaxRange(line), upper)
            var pipes: [Int] = []
            var isAlignment = true
            var i = line.location
            while i < lineEnd {
                let c = ns.character(at: i)
                if c == pipe {
                    pipes.append(i)
                } else if c != dash && c != colon && c != space && c != lf && c != cr {
                    isAlignment = false
                }
                i += 1
            }
            rows.append(TableRow(
                line: NSRange(location: line.location, length: max(0, lineEnd - line.location)),
                pipes: pipes,
                isAlignment: isAlignment && !pipes.isEmpty
            ))
            loc = NSMaxRange(line)
        }

        let firstAlignmentIndex = rows.firstIndex(where: { $0.isAlignment })
        for (r, row) in rows.enumerated() {
            for p in row.pipes {
                storage.addAttribute(.foregroundColor, value: context.secondaryColor, range: NSRange(location: p, length: 1))
            }
            if row.isAlignment {
                // Exclude the trailing newline: it anchors the (collapsed)
                // line's fragment so the rule can be drawn in its place.
                var content = row.line
                if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == lf {
                    content.length -= 1
                }
                guard content.length > 0 else { continue }
                storage.addAttribute(.foregroundColor, value: context.secondaryColor, range: content)
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: content)
                storage.addAttribute(MarkdownAttribute.tableSeparator, value: true, range: content)
            } else if let sep = firstAlignmentIndex, r < sep, row.line.length > 0 {
                // Header rows sit above the alignment row.
                storage.addAttribute(.font, value: font(context.codeFont, addingTraits: .bold), range: row.line)
            }
        }

        // Column alignment: pad each cell's trailing character with kern so
        // every closing pipe lands at the column's max content width. Mono
        // font means bold headers measure the same as body cells.
        let measure: [NSAttributedString.Key: Any] = [.font: context.codeFont]
        struct Cell {
            var column: Int
            var content: NSRange
            var width: CGFloat
        }
        var columnWidths: [CGFloat] = []
        var cells: [Cell] = []
        for row in rows where !row.isAlignment && row.pipes.count >= 2 {
            for k in 0..<(row.pipes.count - 1) {
                let start = row.pipes[k] + 1
                let length = row.pipes[k + 1] - start
                let text = length > 0 ? ns.substring(with: NSRange(location: start, length: length)) : ""
                let width = (text as NSString).size(withAttributes: measure).width
                if k >= columnWidths.count {
                    columnWidths.append(width)
                } else {
                    columnWidths[k] = max(columnWidths[k], width)
                }
                cells.append(Cell(column: k, content: NSRange(location: start, length: length), width: width))
            }
        }
        for cell in cells {
            let pad = columnWidths[cell.column] - cell.width
            guard pad > 0.01 else { continue }
            let target = cell.content.length > 0
                ? NSRange(location: NSMaxRange(cell.content) - 1, length: 1)
                : NSRange(location: cell.content.location - 1, length: 1)  // empty cell: pad the pipe
            guard target.location >= 0, NSMaxRange(target) <= storage.length else { continue }
            storage.addAttribute(.kern, value: pad, range: target)
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
            // Dim the raw image syntax but never hide it — until inline image
            // rendering exists, hiding would make the image vanish entirely.
            guard let r = safe(range) else { return }
            storage.addAttribute(.foregroundColor, value: context.secondaryColor, range: r)
        }
    }
}
