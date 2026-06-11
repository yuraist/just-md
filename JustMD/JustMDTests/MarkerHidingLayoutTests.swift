import Testing
import AppKit
@testable import JustMD

/// End-to-end checks that marker hiding actually reaches the layout layer —
/// glyph properties, not just attribute bookkeeping. The earlier glyph-hiding
/// attempt rendered garbage, so this guards the real mechanism.
@Suite("MarkerHidingLayout")
@MainActor
struct MarkerHidingLayoutTests {

    private func makeEditor(_ text: String) -> (MarkdownTextView, MarkdownTextStorage) {
        let storage = MarkdownTextStorage()
        let highlighter = SyntaxHighlighter(parser: MarkdownParser())
        storage.highlighter = highlighter
        storage.highlightContext = HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        storage.applyHighlightingNow()
        let view = MarkdownTextView(storage: storage)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 1200)
        return (view, storage)
    }

    @Test("heading hashes get null glyphs when the caret is elsewhere")
    func hashesHiddenOffActive() throws {
        let (view, _) = makeEditor("# Head\n\nbody text")
        let lm = try #require(view.layoutManager)
        let container = try #require(view.textContainer)

        view.setSelectedRange(NSRange(location: 10, length: 0))  // caret in "body text"
        lm.ensureLayout(for: container)
        let hashGlyph = lm.glyphIndexForCharacter(at: 0)
        #expect(lm.propertyForGlyph(at: hashGlyph) == .null)
        let headGlyph = lm.glyphIndexForCharacter(at: 3)
        #expect(lm.propertyForGlyph(at: headGlyph) != .null)
    }

    @Test("moving the caret into the heading reveals the hashes")
    func revealOnCaret() throws {
        let (view, _) = makeEditor("# Head\n\nbody text")
        let lm = try #require(view.layoutManager)
        let container = try #require(view.textContainer)

        view.setSelectedRange(NSRange(location: 10, length: 0))
        lm.ensureLayout(for: container)
        #expect(lm.propertyForGlyph(at: lm.glyphIndexForCharacter(at: 0)) == .null)

        view.setSelectedRange(NSRange(location: 2, length: 0))   // caret in heading
        lm.ensureLayout(for: container)
        #expect(lm.propertyForGlyph(at: lm.glyphIndexForCharacter(at: 0)) != .null)
    }

    @Test("bold asterisks hide while their text stays laid out")
    func asterisksHidden() throws {
        let text = "intro\n\nhas **bold** word"
        let (view, _) = makeEditor(text)
        let lm = try #require(view.layoutManager)
        let container = try #require(view.textContainer)

        view.setSelectedRange(NSRange(location: 0, length: 0))   // caret in "intro"
        lm.ensureLayout(for: container)
        let ns = text as NSString
        let open = ns.range(of: "**")
        #expect(lm.propertyForGlyph(at: lm.glyphIndexForCharacter(at: open.location)) == .null)
        let boldChar = ns.range(of: "bold").location
        #expect(lm.propertyForGlyph(at: lm.glyphIndexForCharacter(at: boldChar)) != .null)
    }

    @Test("quote bar geometry sits on the quote line, not the blank line above")
    func quoteBarGeometry() throws {
        let text = "intro\n\n> A quoted line"
        let (view, _) = makeEditor(text)
        let lm = try #require(view.layoutManager as? MarkdownLayoutManager)
        let container = try #require(view.textContainer)

        // Caret in "intro": the quote's `> ` markers are hidden.
        view.setSelectedRange(NSRange(location: 0, length: 0))
        lm.ensureLayout(for: container)

        let ns = text as NSString
        let quoteRange = ns.range(of: "> A quoted line")
        let union = lm.visibleLineFragmentUnion(forCharacterRange: quoteRange)

        let aGlyph = lm.glyphIndexForCharacter(at: ns.range(of: "A quoted").location)
        let quoteLine = lm.lineFragmentUsedRect(forGlyphAt: aGlyph, effectiveRange: nil)

        #expect(abs(union.minY - quoteLine.minY) < 0.5)
        #expect(abs(union.height - quoteLine.height) < 0.5)
    }

    @Test("typing attributes follow the live neighbor, not the stale snapshot")
    func typingAttributesLiveInheritance() throws {
        // Reproduces the "just-typed character is small in a heading" bug:
        // NSTextView snapshots typing attributes at selection-change time,
        // which is BEFORE the async restyle pass has styled the neighbor.
        let storage = MarkdownTextStorage()
        let highlighter = SyntaxHighlighter(parser: MarkdownParser())
        storage.highlighter = highlighter
        storage.highlightContext = HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "## Head")
        let view = MarkdownTextView(storage: storage)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 200)

        // Caret placed while the text is still unstyled — the snapshot NSTextView
        // takes here carries the base font.
        view.setSelectedRange(NSRange(location: 7, length: 0))
        // The restyle lands afterwards (in the app: one runloop pass later).
        storage.applyHighlightingNow()

        let typingFont = try #require(view.typingAttributes[.font] as? NSFont)
        #expect(typingFont.pointSize > 16)

        view.insertText("y", replacementRange: NSRange(location: 7, length: 0))
        let insertedFont = try #require(storage.attributes(at: 7, effectiveRange: nil)[.font] as? NSFont)
        #expect(insertedFont.pointSize > 16)
    }

    @Test("offscreen render produces a non-empty bitmap (visual artifact)")
    func renderArtifact() throws {
        let demo = """
        # JustMD Demo

        Paragraph with **bold**, *italic*, ~~struck~~, `code` and \
        a [link](https://anthropic.com).

        ## Second heading

        - First bullet
        - Second bullet with a much longer text that should wrap onto the \
        following line and hang under the text column, not under the bullet
        - [ ] Open task
        - [x] Done task

        ---

        > Quoted line.

        ```swift
        let x = 1
        ```

        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let (view, _) = makeEditor(demo)
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        #expect(data.count > 1000)
        // The test host is sandboxed; NSTemporaryDirectory() resolves inside
        // its container, which is the only generally writable spot.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("justmd-render.png")
        try data.write(to: url)
    }
}
