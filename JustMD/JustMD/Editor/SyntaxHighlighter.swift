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
    }
}
