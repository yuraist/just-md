import Testing
import AppKit
@testable import JustMD

// MARK: - BlockDiff

@Suite("BlockDiff")
struct BlockDiffTests {

    private let parser = MarkdownParser()

    @Test("edit inside a middle paragraph restyles only that paragraph")
    func middleParagraphWindow() {
        let old = parser.parse("AAAA\n\nBBBB\n\nCCCC").blocks
        let new = parser.parse("AAAA\n\nBBxxBB\n\nCCCC").blocks
        let w = BlockDiff.changedWindow(
            old: old, new: new, delta: 2,
            editedRange: NSRange(location: 8, length: 2),
            newLength: ("AAAA\n\nBBxxBB\n\nCCCC" as NSString).length
        )
        #expect(w == NSRange(location: 6, length: 6))
    }

    @Test("edit in the first paragraph leaves later blocks out of the window")
    func laterBlocksUntouched() {
        let old = parser.parse("AAAA\n\nBBBB").blocks
        let new = parser.parse("AAxAA\n\nBBBB").blocks
        let w = BlockDiff.changedWindow(
            old: old, new: new, delta: 1,
            editedRange: NSRange(location: 2, length: 1),
            newLength: ("AAxAA\n\nBBBB" as NSString).length
        )
        #expect(w == NSRange(location: 0, length: 5))
    }

    @Test("opening a code fence cascades the window to the document end")
    func fenceCascade() {
        let old = parser.parse("``\npara").blocks
        let new = parser.parse("```\npara").blocks
        let w = BlockDiff.changedWindow(
            old: old, new: new, delta: 1,
            editedRange: NSRange(location: 2, length: 1),
            newLength: ("```\npara" as NSString).length
        )
        #expect(w == NSRange(location: 0, length: 8))
    }

    @Test("deleting across a block boundary covers the merged block")
    func mergeParagraphs() {
        // Delete the blank line between A and B: the paragraphs merge.
        let old = parser.parse("AAAA\n\nBBBB").blocks
        let new = parser.parse("AAAA\nBBBB").blocks
        let w = BlockDiff.changedWindow(
            old: old, new: new, delta: -1,
            editedRange: NSRange(location: 5, length: 0),
            newLength: ("AAAA\nBBBB" as NSString).length
        )
        #expect(w == NSRange(location: 0, length: 9))
    }
}

// MARK: - Parser offsets

@Suite("ParserOffsets")
struct ParserOffsetTests {

    @Test("ranges are correct in non-ASCII documents")
    func nonASCIIRanges() throws {
        let src = "# Заголовок 😀\n\nтекст **жирный** хвост"
        let parser = MarkdownParser()
        let blocks = parser.parse(src).blocks
        try #require(blocks.count == 2)
        let ns = src as NSString

        guard case .heading(let level, let hr, let mr) = blocks[0] else {
            Issue.record("first block is not a heading")
            return
        }
        #expect(level == 1)
        #expect(ns.substring(with: hr) == "# Заголовок 😀")
        #expect(ns.substring(with: mr) == "# ")

        let spans = parser.inlineSpans(in: blocks[1], source: src)
        var boldRange: NSRange?
        for span in spans {
            if case .bold(let r, _) = span { boldRange = r }
        }
        let bold = try #require(boldRange)
        #expect(ns.substring(with: bold) == "**жирный**")
    }
}

// MARK: - Highlight pipeline

@Suite("HighlightPipeline")
@MainActor
struct HighlightPipelineTests {

    private func makeContext() -> HighlightContext {
        HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
    }

    private func makeStorage(_ text: String) -> (MarkdownTextStorage, SyntaxHighlighter) {
        let storage = MarkdownTextStorage()
        let highlighter = SyntaxHighlighter(parser: MarkdownParser())
        storage.highlighter = highlighter
        storage.highlightContext = makeContext()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        storage.applyHighlightingNow()
        return (storage, highlighter)
    }

    private func spinRunLoop(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @Test("highlight lands on the next runloop tick without an explicit flush")
    func nextTickHighlight() {
        let storage = MarkdownTextStorage()
        storage.highlighter = SyntaxHighlighter(parser: MarkdownParser())
        storage.highlightContext = makeContext()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello")
        spinRunLoop()
        let font = storage.attributes(at: 3, effectiveRange: nil)[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > 16)
    }

    @Test("typing in the first paragraph restyles only that window")
    func incrementalWindow() {
        let (storage, highlighter) = makeStorage("Hello world\n\n**b** y")
        storage.replaceCharacters(in: NSRange(location: 2, length: 0), with: "x")
        spinRunLoop()
        let window = highlighter.lastAppliedWindow
        #expect(window == NSRange(location: 0, length: 12))

        // The bold span in the untouched paragraph keeps its styling.
        let boldLoc = ("Hello xworld\n\n**" as NSString).length
        let font = storage.attributes(at: boldLoc, effectiveRange: nil)[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("inline spans are cached per block content")
    func spanCache() {
        let highlighter = SyntaxHighlighter(parser: MarkdownParser())
        let storage = NSTextStorage(string: "first **b**\n\nsecond *i*")
        highlighter.apply(to: storage, context: makeContext())
        let missesAfterFirst = highlighter.inlineParseMisses
        #expect(missesAfterFirst == 2)
        highlighter.apply(to: storage, context: makeContext())
        #expect(highlighter.inlineParseMisses == missesAfterFirst)
    }

    @Test("structure change re-applies through the document end")
    func structureChange() {
        let (storage, highlighter) = makeStorage("``\npara")
        storage.replaceCharacters(in: NSRange(location: 2, length: 0), with: "`")
        spinRunLoop()
        let window = highlighter.lastAppliedWindow
        #expect(window == NSRange(location: 0, length: storage.length))
        // The text below the new fence is now a code block: mono font.
        let font = storage.attributes(at: 5, effectiveRange: nil)[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }
}

// MARK: - Code highlight cache

@Suite("CodeBlockHighlighterCache")
@MainActor
struct CodeBlockHighlighterCacheTests {

    @Test("async highlight lands in the cache and is reused")
    func asyncCachePopulates() async {
        let h = CodeBlockHighlighter()
        #expect(h.cachedHighlight("let x = 1", language: "swift") == nil)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            h.highlightAsync("let x = 1", language: "swift") { result in
                #expect(result != nil)
                cont.resume()
            }
        }
        #expect(h.cachedHighlight("let x = 1", language: "swift") != nil)
    }

    @Test("repeated cached lookups return the same instance")
    func cacheStable() async {
        let h = CodeBlockHighlighter()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            h.highlightAsync("print(1)", language: "swift") { _ in cont.resume() }
        }
        let a = h.cachedHighlight("print(1)", language: "swift")
        let b = h.cachedHighlight("print(1)", language: "swift")
        #expect(a != nil)
        #expect(a === b)
    }
}
