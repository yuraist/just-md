import AppKit

/// Layout manager that draws the chrome attribute-based styling can't: the
/// horizontal-rule line standing in for hidden `---` characters and the
/// accent bar alongside blockquotes.
nonisolated final class MarkdownLayoutManager: NSLayoutManager {

    weak var visibility: MarkerVisibilityController?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let context = (storage as? MarkdownTextStorage)?.highlightContext
        let secondary = context?.secondaryColor ?? .secondaryLabelColor
        let active = visibility?.activeRange ?? NSRange(location: 0, length: 0)
        let padding = container.lineFragmentPadding

        // Horizontal rule where the raw `---` is hidden. When the paragraph is
        // active the dimmed dashes show instead, so skip drawing.
        storage.enumerateAttribute(MarkdownAttribute.thematicBreak, in: charRange, options: []) { value, range, _ in
            guard value as? Bool == true,
                  NSIntersectionRange(range, active).length == 0 else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphs, in: container)
            let y = (rect.midY + origin.y).rounded() + 0.5
            let line = NSRect(
                x: origin.x + padding,
                y: y,
                width: container.size.width - padding * 2,
                height: 1
            )
            secondary.withAlphaComponent(0.35).setFill()
            line.fill()
        }

        // Blockquote accent bar, drawn per enclosed line fragment so wrapped
        // and multi-line quotes get a continuous bar.
        storage.enumerateAttribute(MarkdownAttribute.blockQuote, in: charRange, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphs, in: container)
            let bar = NSRect(
                x: origin.x + padding + 2,
                y: rect.minY + origin.y + 1,
                width: 3,
                height: max(0, rect.height - 2)
            )
            secondary.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
