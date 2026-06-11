import AppKit

/// Pure logic for deciding which marker characters are hidden, separated from
/// the layout-manager plumbing so it can be unit-tested.
nonisolated enum MarkerVisibility {
    /// Returns the sub-ranges of `span` that must be hidden from layout:
    /// characters tagged `MarkdownAttribute.marker` that fall outside
    /// `activeRange` (the caret's paragraph, where markers stay visible).
    static func hiddenRanges(
        in span: NSRange,
        attributed: NSAttributedString,
        activeRange: NSRange
    ) -> [NSRange] {
        let start = max(0, span.location)
        let end = min(NSMaxRange(span), attributed.length)
        guard end > start else { return [] }
        let limit = NSRange(location: start, length: end - start)

        var result: [NSRange] = []
        attributed.enumerateAttribute(MarkdownAttribute.marker, in: limit, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            if NSIntersectionRange(range, activeRange).length == 0 {
                result.append(range)
                return
            }
            // Partial overlap with the active paragraph: hide only the parts
            // outside it.
            if range.location < activeRange.location {
                let len = min(NSMaxRange(range), activeRange.location) - range.location
                result.append(NSRange(location: range.location, length: len))
            }
            if NSMaxRange(range) > NSMaxRange(activeRange) {
                let s = max(range.location, NSMaxRange(activeRange))
                result.append(NSRange(location: s, length: NSMaxRange(range) - s))
            }
        }
        return result
    }
}

/// Hides markdown syntax markers (`#`, `**`, backticks, link URLs, code
/// fences…) from layout on every paragraph except the active one — the
/// Bear-style "reveal on caret" behaviour. The characters always stay in the
/// text storage, so files round-trip raw markdown; hiding happens at glyph
/// generation by assigning the `.null` glyph property, which removes the
/// glyph from layout and display entirely.
///
/// This replaces the earlier `setGlyphs`-override attempt that produced
/// garbled glyphs: the delegate hook is the documented customization point,
/// and we re-submit the *original* glyphs with only the properties changed.
@MainActor
final class MarkerVisibilityController: NSObject {

    weak var layoutManager: NSLayoutManager?

    /// Paragraph-extended range around the caret/selection where markers stay
    /// visible (dimmed). Everything outside hides its markers.
    private(set) var activeRange = NSRange(location: 0, length: 0)

    /// Recomputes the active paragraph range for a selection and invalidates
    /// glyphs for the paragraphs that flipped state.
    func updateActiveRange(for selection: NSRange, in storage: NSTextStorage) {
        let ns = storage.string as NSString
        let clamped = NSRange(
            location: min(max(0, selection.location), ns.length),
            length: min(selection.length, ns.length - min(max(0, selection.location), ns.length))
        )
        let newActive = ns.paragraphRange(for: clamped)
        guard newActive != activeRange else { return }
        let oldActive = activeRange
        activeRange = newActive
        invalidate(oldActive)
        invalidate(newActive)
    }

    /// Regenerates glyphs for `range` so hidden/visible state is recomputed.
    func invalidate(_ range: NSRange) {
        guard let lm = layoutManager, range.length > 0 else { return }
        let storageLength = lm.textStorage?.length ?? 0
        let start = min(range.location, storageLength)
        let length = min(range.length, storageLength - start)
        guard length > 0 else { return }
        let safe = NSRange(location: start, length: length)
        lm.invalidateGlyphs(forCharacterRange: safe, changeInLength: 0, actualCharacterRange: nil)
        lm.invalidateLayout(forCharacterRange: safe, actualCharacterRange: nil)
    }
}

extension MarkerVisibilityController: @preconcurrency NSLayoutManagerDelegate {

    nonisolated static let hiddenProperty = NSLayoutManager.GlyphProperty.null

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard glyphRange.length > 0, let storage = layoutManager.textStorage else { return 0 }

        let count = glyphRange.length
        let firstChar = charIndexes[0]
        let lastChar = charIndexes[count - 1]
        let span = NSRange(location: firstChar, length: lastChar - firstChar + 1)
        let hidden = MarkerVisibility.hiddenRanges(in: span, attributed: storage, activeRange: activeRange)
        guard !hidden.isEmpty else { return 0 }  // 0 → default glyph generation

        var newProps = [NSLayoutManager.GlyphProperty](repeating: [], count: count)
        var rangeCursor = 0
        for i in 0..<count {
            newProps[i] = props[i]
            let charIndex = charIndexes[i]
            while rangeCursor < hidden.count && NSMaxRange(hidden[rangeCursor]) <= charIndex {
                rangeCursor += 1
            }
            if rangeCursor < hidden.count && NSLocationInRange(charIndex, hidden[rangeCursor]) {
                newProps[i] = Self.hiddenProperty
            }
        }
        newProps.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(
                glyphs,
                properties: buffer.baseAddress!,
                characterIndexes: charIndexes,
                font: aFont,
                forGlyphRange: glyphRange
            )
        }
        return count
    }
}
