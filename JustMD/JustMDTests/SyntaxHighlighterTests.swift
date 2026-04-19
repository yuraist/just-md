import Testing
import AppKit
@testable import JustMD

@Suite("SyntaxHighlighter")
@MainActor
struct SyntaxHighlighterTests {

    private func makeContext() -> HighlightContext {
        return HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
    }

    private func storage(_ text: String) -> NSTextStorage {
        let s = MarkdownTextStorage()
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        return s
    }

    @Test("heading gets bold larger font")
    func headingFont() {
        let s = storage("# Hello")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let attrs = s.attributes(at: 3, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > 16)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("heading hash is marked as marker")
    func headingMarker() {
        let s = storage("# Hi")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let isMarker = s.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool
        #expect(isMarker == true)
    }

    @Test("code block content gets mono font and language attribute")
    func codeBlockMono() {
        let s = storage("```swift\nlet x = 1\n```")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let contentLoc = ("```swift\n" as NSString).length + 2
        let attrs = s.attributes(at: contentLoc, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        let language = attrs[MarkdownAttribute.codeLanguage] as? String
        #expect(language == "swift")
    }

    @Test("code block fences are marked as marker")
    func codeBlockFenceMarker() {
        let s = storage("```\nx\n```")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let firstFence = s.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool
        #expect(firstFence == true)
    }

    @Test("blockquote gets secondary color and indent")
    func blockquoteStyle() {
        let s = storage("> a quote")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let attrs = s.attributes(at: 2, effectiveRange: nil)
        let color = attrs[.foregroundColor] as? NSColor
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        #expect(color != nil)
        #expect(style?.firstLineHeadIndent ?? 0 > 0)
    }

    @Test("list item bullets are marked as marker")
    func listItemMarker() {
        let s = storage("- one\n- two\n")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let isMarker = s.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool
        #expect(isMarker == true)
    }
}
