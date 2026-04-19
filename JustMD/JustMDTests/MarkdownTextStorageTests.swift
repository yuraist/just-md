import AppKit
import Testing
@testable import JustMD

@Suite("MarkdownTextStorage")
@MainActor
struct MarkdownTextStorageTests {
    @Test("storage reports length and string match backing store")
    func lengthMatches() {
        let storage = MarkdownTextStorage()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "hello")
        #expect(storage.length == 5)
        #expect(storage.string == "hello")
    }

    @Test("highlighter applies on insert")
    func highlightsOnInsert() {
        let storage = MarkdownTextStorage()
        let parser = MarkdownParser()
        let highlighter = SyntaxHighlighter(parser: parser)
        let context = HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
        storage.highlighter = highlighter
        storage.highlightContext = context
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello")
        // After insert, processEditing fires once, highlighting applies.
        let attrs = storage.attributes(at: 3, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > 16)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(storage.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool == true)
    }

    @Test("highlighter does not loop when guarded")
    func noInfiniteLoop() {
        let storage = MarkdownTextStorage()
        let parser = MarkdownParser()
        let highlighter = SyntaxHighlighter(parser: parser)
        let context = HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
        storage.highlighter = highlighter
        storage.highlightContext = context
        // If recursion isn't guarded, this insert would crash with stack overflow or infinite loop.
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Hello *world*")
        #expect(storage.length == 13)
    }
}
