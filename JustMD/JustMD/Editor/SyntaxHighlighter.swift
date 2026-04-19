import AppKit

nonisolated enum MarkdownAttribute {
    static let marker = NSAttributedString.Key("com.justmd.marker")
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

nonisolated final class SyntaxHighlighter {
    let parser: MarkdownParser

    /// Optional code-block highlighter. When set, `.codeBlock` content ranges
    /// get per-token foreground colors overlaid on top of the mono font and
    /// code background. When nil, code blocks still receive mono font +
    /// background but no token coloring.
    var codeHighlighter: CodeBlockHighlighter?

    init(parser: MarkdownParser) {
        self.parser = parser
    }

    func apply(to storage: NSTextStorage, context: HighlightContext) {
        let source = storage.string
        let doc = parser.parse(source)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes(context), range: full)
        for block in doc.blocks {
            applyBlock(block, source: source, storage: storage, context: context)
        }
        storage.endEditing()
    }

    private func baseAttributes(_ ctx: HighlightContext) -> [NSAttributedString.Key: Any] {
        return [.font: ctx.baseFont, .foregroundColor: ctx.textColor]
    }

    private func applyBlock(_ block: Block, source: String, storage: NSTextStorage, context: HighlightContext) {
        switch block {
        case .heading(let level, let range, let markerRange):
            let size = context.baseFont.pointSize + CGFloat(max(0, 8 - level)) * 2
            let resized = NSFont(descriptor: context.baseFont.fontDescriptor, size: size) ?? context.baseFont
            let bold = NSFontManager.shared.convert(resized, toHaveTrait: .boldFontMask)
            if NSMaxRange(range) <= storage.length {
                storage.addAttribute(.font, value: bold, range: range)
            }
            if NSMaxRange(markerRange) <= storage.length {
                storage.addAttribute(MarkdownAttribute.marker, value: true, range: markerRange)
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
                if let highlighted = codeHighlighter.highlight(codeText, language: language) {
                    // Only overlay if the highlighted text length matches the content
                    // range length, otherwise the offset mapping is unsafe.
                    if highlighted.length == contentRange.length {
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
            applyInlineSpans(in: block, source: source, storage: storage, context: context)
        default:
            break
        }
    }

    private func applyInlineSpans(in block: Block, source: String, storage: NSTextStorage, context: HighlightContext) {
        let spans = parser.inlineSpans(in: block, source: source)
        for span in spans {
            applySpan(span, storage: storage, context: context)
        }
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
                let bolded = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
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
                let italicized = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
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
            // Placeholder until Task 10.4 attaches NSTextAttachment.
            storage.addAttribute(MarkdownAttribute.marker, value: true, range: r)
        }
    }
}
