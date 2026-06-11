import Testing
import AppKit
@testable import JustMD

@Suite("MarkerVisibility")
@MainActor
struct MarkerVisibilityTests {

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

    private func highlighted(_ text: String) -> NSTextStorage {
        let s = NSTextStorage(string: text)
        SyntaxHighlighter(parser: MarkdownParser()).apply(to: s, context: makeContext())
        return s
    }

    @Test("markers outside the active paragraph are hidden")
    func hiddenOutsideActive() {
        let text = "# Head\n\nbody **bold** end"
        let s = highlighted(text)
        let ns = text as NSString
        let secondParagraph = ns.paragraphRange(for: NSRange(location: 10, length: 0))
        let hidden = MarkerVisibility.hiddenRanges(
            in: NSRange(location: 0, length: s.length),
            attributed: s,
            activeRange: secondParagraph
        )
        // The heading marker "# " hides; the asterisks sit in the active
        // paragraph and stay visible.
        #expect(hidden.contains(NSRange(location: 0, length: 2)))
        for range in hidden {
            #expect(NSIntersectionRange(range, secondParagraph).length == 0)
        }
    }

    @Test("markers inside the active paragraph stay visible")
    func visibleInsideActive() {
        let text = "# Head\n\nbody **bold** end"
        let s = highlighted(text)
        let firstParagraph = (text as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        let hidden = MarkerVisibility.hiddenRanges(
            in: NSRange(location: 0, length: s.length),
            attributed: s,
            activeRange: firstParagraph
        )
        #expect(!hidden.contains(NSRange(location: 0, length: 2)))
        // Both asterisk runs of the second paragraph hide.
        let boldOpen = (text as NSString).range(of: "**")
        #expect(hidden.contains(boldOpen))
    }

    @Test("a marker run straddling the active boundary hides only outside")
    func partialOverlap() {
        let s = NSTextStorage(string: "abcdef")
        s.addAttribute(MarkdownAttribute.marker, value: true, range: NSRange(location: 0, length: 4))
        let hidden = MarkerVisibility.hiddenRanges(
            in: NSRange(location: 0, length: 6),
            attributed: s,
            activeRange: NSRange(location: 2, length: 2)
        )
        #expect(hidden == [NSRange(location: 0, length: 2)])
    }

    @Test("link URL part is hidden off the active paragraph, text is not")
    func linkURLHidden() {
        let text = "see [site](https://e.co) ok\n\nnext"
        let s = highlighted(text)
        let ns = text as NSString
        let lastParagraph = ns.paragraphRange(for: NSRange(location: ns.length - 1, length: 0))
        let hidden = MarkerVisibility.hiddenRanges(
            in: NSRange(location: 0, length: s.length),
            attributed: s,
            activeRange: lastParagraph
        )
        let urlRange = ns.range(of: "https://e.co")
        let textRange = ns.range(of: "site")
        let urlHidden = hidden.contains { NSIntersectionRange($0, urlRange).length == urlRange.length }
        let textHidden = hidden.contains { NSIntersectionRange($0, textRange).length > 0 }
        #expect(urlHidden)
        #expect(!textHidden)
    }
}
