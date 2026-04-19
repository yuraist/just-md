import AppKit

nonisolated final class HiddenMarkerLayoutManager: NSLayoutManager {
    var activeLineRange: NSRange = .init(location: 0, length: 0)

    override func setGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) {
        guard let storage = textStorage else {
            super.setGlyphs(
                glyphs,
                properties: props,
                characterIndexes: charIndexes,
                font: aFont,
                forGlyphRange: glyphRange
            )
            return
        }
        let mutableProps = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: glyphRange.length)
        defer { mutableProps.deallocate() }
        for i in 0..<glyphRange.length {
            let charIndex = charIndexes[i]
            var property = props[i]
            if charIndex < storage.length {
                let attrs = storage.attributes(at: charIndex, effectiveRange: nil)
                let isHeadingHash = attrs[MarkdownAttribute.headingHash] as? Bool == true
                let isMarker = attrs[MarkdownAttribute.marker] as? Bool == true
                let onActiveLine = NSLocationInRange(charIndex, activeLineRange)
                if isHeadingHash || (isMarker && !onActiveLine) {
                    property.insert(.null)
                }
            }
            mutableProps[i] = property
        }
        super.setGlyphs(
            glyphs,
            properties: mutableProps,
            characterIndexes: charIndexes,
            font: aFont,
            forGlyphRange: glyphRange
        )
    }
}
