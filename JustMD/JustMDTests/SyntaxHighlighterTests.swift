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

    @Test("heading hash gets headingHash attribute")
    func headingHashAttr() {
        let s = storage("# Hi")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let isHash = s.attribute(MarkdownAttribute.headingHash, at: 0, effectiveRange: nil) as? Bool
        #expect(isHash == true)
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

    @Test("list item bullets stay visible: accent tint, no hide marker")
    func listItemMarker() {
        let s = storage("- one\n- two\n")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let isMarker = s.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool
        #expect(isMarker != true)
        let color = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.controlAccentColor)
    }

    @Test("list items hang wrapped lines under the text column")
    func listHangingIndent() {
        let s = storage("- one\n- two\n")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let style = s.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.headIndent ?? 0) > 0)
    }

    @Test("horizontal rule is hidden and tagged for drawing")
    func thematicBreakTagged() {
        let s = storage("above\n\n---\n\nbelow")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let hrLoc = ("above\n\n" as NSString).length
        #expect(s.attribute(MarkdownAttribute.marker, at: hrLoc, effectiveRange: nil) as? Bool == true)
        #expect(s.attribute(MarkdownAttribute.thematicBreak, at: hrLoc, effectiveRange: nil) as? Bool == true)
    }

    @Test("blockquote leading > markers hide, range tagged for the bar")
    func blockquoteMarkers() {
        let s = storage("> a quote")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        #expect(s.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(s.attribute(MarkdownAttribute.marker, at: 1, effectiveRange: nil) as? Bool == true)
        #expect(s.attribute(MarkdownAttribute.marker, at: 2, effectiveRange: nil) as? Bool != true)
        #expect(s.attribute(MarkdownAttribute.blockQuote, at: 4, effectiveRange: nil) as? Bool == true)
    }

    @Test("code fence lines carry no background band")
    func fenceNoBackground() {
        let s = storage("```swift\nlet x = 1\n```")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        #expect(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        let contentLoc = ("```swift\n" as NSString).length + 1
        #expect(s.attribute(.backgroundColor, at: contentLoc, effectiveRange: nil) != nil)
    }

    @Test("table pipes are dimmed but not hidden")
    func tablePipesDimmed() {
        let s = storage("| A | B |\n|---|---|\n| 1 | 2 |")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let pipeColor = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(pipeColor == NSColor.secondaryLabelColor)
        #expect(s.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool != true)
        // Cell content keeps the text color.
        let cellColor = s.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(cellColor == NSColor.labelColor)
    }

    @Test("bold inside a list item renders bold with hidden markers")
    func listItemBold() {
        let text = "- has **bold** word"
        let s = storage(text)
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let ns = text as NSString
        let boldLoc = ns.range(of: "bold").location
        let font = s.attribute(.font, at: boldLoc, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let openMarker = ns.range(of: "**").location
        #expect(s.attribute(MarkdownAttribute.marker, at: openMarker, effectiveRange: nil) as? Bool == true)
    }

    @Test("links and code inside task items render")
    func listItemLinkAndCode() {
        let text = "- [x] see [site](https://e.co) and `cmd`"
        let s = storage(text)
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let ns = text as NSString
        let linkLoc = ns.range(of: "site").location
        #expect(s.attribute(.link, at: linkLoc, effectiveRange: nil) != nil)
        let codeLoc = ns.range(of: "cmd").location
        #expect(s.attribute(.backgroundColor, at: codeLoc, effectiveRange: nil) != nil)
    }

    @Test("table alignment row hides and is tagged for the drawn rule")
    func tableSeparatorTagged() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |"
        let s = storage(text)
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let sepLoc = (text as NSString).range(of: "|---|---|").location
        #expect(s.attribute(MarkdownAttribute.marker, at: sepLoc, effectiveRange: nil) as? Bool == true)
        #expect(s.attribute(MarkdownAttribute.tableSeparator, at: sepLoc, effectiveRange: nil) as? Bool == true)
    }

    @Test("table header row is bold")
    func tableHeaderBold() {
        let s = storage("| A | B |\n|---|---|\n| 1 | 2 |")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let headerFont = s.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(headerFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let bodyLoc = ("| A | B |\n|---|---|\n| " as NSString).length
        let bodyFont = s.attribute(.font, at: bodyLoc, effectiveRange: nil) as? NSFont
        #expect(bodyFont?.fontDescriptor.symbolicTraits.contains(.bold) != true)
    }

    @Test("table cells get kern padding that equalizes column widths")
    func tableKernAlignment() {
        // "Ada" is wider than "1" — the body cell must carry kern equal to
        // the pixel difference so the closing pipes align.
        let text = "| Ada | Role |\n|-----|------|\n| 1 | 2 |"
        let s = storage(text)
        let h = SyntaxHighlighter(parser: MarkdownParser())
        let ctx = makeContext()
        h.apply(to: s, context: ctx)
        let ns = text as NSString
        let measure: [NSAttributedString.Key: Any] = [.font: ctx.codeFont]
        let headerWidth = (" Ada " as NSString).size(withAttributes: measure).width
        let bodyWidth = (" 1 " as NSString).size(withAttributes: measure).width
        // Kern lands on the last char of the narrower cell (the space in " 1 ").
        let bodyCellEnd = ns.range(of: "| 1 |").location + 3  // index of trailing space
        let kern = s.attribute(.kern, at: bodyCellEnd, effectiveRange: nil) as? CGFloat
        #expect(kern != nil)
        #expect(abs((kern ?? 0) - (headerWidth - bodyWidth)) < 0.5)
    }

    @Test("bold span gets bold font")
    func boldSpan() {
        let s = storage("hello **world**")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let attrs = s.attributes(at: 9, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("bold markers tagged as marker")
    func boldMarker() {
        let s = storage("**x**")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let opener = s.attribute(MarkdownAttribute.marker, at: 0, effectiveRange: nil) as? Bool
        let closer = s.attribute(MarkdownAttribute.marker, at: 3, effectiveRange: nil) as? Bool
        #expect(opener == true)
        #expect(closer == true)
    }

    @Test("italic span gets italic font")
    func italicSpan() {
        let s = storage("a *b* c")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let attrs = s.attributes(at: 3, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test("strike span gets strikethrough")
    func strikeSpan() {
        let s = storage("~~done~~")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let attrs = s.attributes(at: 3, effectiveRange: nil)
        let strike = attrs[.strikethroughStyle] as? Int
        #expect(strike == NSUnderlineStyle.single.rawValue)
    }

    @Test("inline code span gets mono font")
    func inlineCodeSpan() {
        let s = storage("x `code` y")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let attrs = s.attributes(at: 4, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    @Test("link span gets accent color and link attribute")
    func linkSpan() {
        let s = storage("see [Apple](https://apple.com)")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        h.apply(to: s, context: makeContext())
        let attrs = s.attributes(at: 5, effectiveRange: nil)
        let url = attrs[.link] as? URL
        #expect(url?.absoluteString == "https://apple.com")
        let color = attrs[.foregroundColor] as? NSColor
        #expect(color != nil)
    }

    @Test("markers get dimmed via secondary color")
    func markersDimmed() {
        let s = storage("**bold**")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        let ctx = makeContext()
        h.apply(to: s, context: ctx)
        let opener = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(opener == ctx.secondaryColor)
    }

    @Test("fenced code block applies syntax highlighting")
    func fencedCodeBlockHighlighted() async {
        let swiftSnippet = "func greet(name: String) -> String { return \"Hello, \\(name)!\" }"
        let s = storage("```swift\n\(swiftSnippet)\n```")
        let h = SyntaxHighlighter(parser: MarkdownParser())
        let codeHighlighter = CodeBlockHighlighter()
        h.codeHighlighter = codeHighlighter
        // Token coloring is async on cache miss; pre-warm the cache so apply()
        // takes the synchronous overlay path.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            codeHighlighter.highlightAsync(swiftSnippet, language: "swift") { _ in cont.resume() }
        }
        h.apply(to: s, context: makeContext())
        let prefix = ("```swift\n" as NSString).length
        let contentLen = (swiftSnippet as NSString).length
        var foundColors = Set<NSColor>()
        s.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: prefix, length: contentLen),
            options: []
        ) { value, _, _ in
            if let c = value as? NSColor { foundColors.insert(c) }
        }
        #expect(foundColors.count >= 2)
    }
}
