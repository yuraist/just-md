import Foundation
import Testing
@testable import JustMD

@Suite("MarkdownParser")
struct MarkdownParserTests {
    @Test("parses empty string to empty document")
    func parsesEmpty() {
        let parser = MarkdownParser()
        let doc = parser.parse("")
        #expect(doc.blocks.isEmpty)
    }

    @Test("parses ATX heading levels 1–6")
    func parsesHeadings() {
        let parser = MarkdownParser()
        let source = "# H1\n## H2\n###### H6\n"
        let doc = parser.parse(source)
        #expect(doc.blocks.count == 3)

        if case let .heading(level, _, _) = doc.blocks[0] { #expect(level == 1) } else { Issue.record("not heading") }
        if case let .heading(level, _, _) = doc.blocks[1] { #expect(level == 2) } else { Issue.record("not heading") }
        if case let .heading(level, _, _) = doc.blocks[2] { #expect(level == 6) } else { Issue.record("not heading") }
    }

    @Test("parses paragraphs")
    func parsesParagraphs() {
        let parser = MarkdownParser()
        let doc = parser.parse("Hello\n\nWorld")
        #expect(doc.blocks.count == 2)
        if case .paragraph = doc.blocks[0] {} else { Issue.record("not paragraph 0") }
        if case .paragraph = doc.blocks[1] {} else { Issue.record("not paragraph 1") }
    }

    @Test("parses thematic break")
    func parsesThematicBreak() {
        let parser = MarkdownParser()
        let doc = parser.parse("---\n")
        #expect(doc.blocks.count == 1)
        if case .thematicBreak = doc.blocks[0] {} else { Issue.record("not thematicBreak") }
    }

    @Test("parses fenced code block with language")
    func parsesFencedCodeBlock() {
        let parser = MarkdownParser()
        let source = "```swift\nlet x = 1\n```"
        let doc = parser.parse(source)
        #expect(doc.blocks.count == 1)
        guard case let .codeBlock(language, range, contentRange, fenceRanges) = doc.blocks[0] else {
            Issue.record("not codeBlock")
            return
        }
        #expect(language == "swift")
        #expect(fenceRanges.count == 2)
        // contentRange should cover "let x = 1" (length 9)
        let nsSource = source as NSString
        #expect(nsSource.substring(with: contentRange) == "let x = 1")
        // overall range covers the whole block
        #expect(nsSource.substring(with: range) == source)
    }

    @Test("parses unordered list")
    func parsesUnorderedList() {
        let parser = MarkdownParser()
        let doc = parser.parse("- one\n- two\n- three\n")
        #expect(doc.blocks.count == 1)
        guard case let .list(ordered, items, _) = doc.blocks[0] else {
            Issue.record("not list")
            return
        }
        #expect(ordered == false)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.taskState == nil })
    }

    @Test("parses ordered list")
    func parsesOrderedList() {
        let parser = MarkdownParser()
        let doc = parser.parse("1. one\n2. two\n3. three\n")
        #expect(doc.blocks.count == 1)
        guard case let .list(ordered, items, _) = doc.blocks[0] else {
            Issue.record("not list")
            return
        }
        #expect(ordered == true)
        #expect(items.count == 3)
    }

    @Test("parses GFM task list with checked and unchecked items")
    func parsesTaskList() {
        let parser = MarkdownParser()
        let doc = parser.parse("- [ ] todo\n- [x] done\n- regular\n")
        #expect(doc.blocks.count == 1)
        guard case let .list(_, items, _) = doc.blocks[0] else {
            Issue.record("not list")
            return
        }
        #expect(items.count == 3)
        #expect(items[0].taskState == .unchecked)
        #expect(items[1].taskState == .checked)
        #expect(items[2].taskState == nil)
    }

    @Test("parses blockquote")
    func parsesBlockquote() {
        let parser = MarkdownParser()
        let doc = parser.parse("> a quote\n> with two lines\n")
        #expect(doc.blocks.count == 1)
        if case .blockQuote = doc.blocks[0] {} else { Issue.record("not blockQuote") }
    }

    @Test("parses GFM pipe table")
    func parsesTable() {
        let parser = MarkdownParser()
        let source = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let doc = parser.parse(source)
        #expect(doc.blocks.count == 1)
        if case .table = doc.blocks[0] {} else { Issue.record("not table") }
    }

    @Test("parses raw HTML block")
    func parsesHtmlBlock() {
        let parser = MarkdownParser()
        let source = "<div>\n<p>hi</p>\n</div>\n"
        let doc = parser.parse(source)
        #expect(doc.blocks.count == 1)
        if case .html = doc.blocks[0] {} else { Issue.record("not html") }
    }

    // MARK: - Inline span extraction (Task 1.6)

    @Test("extracts bold span from paragraph")
    func extractsBold() {
        let parser = MarkdownParser()
        let source = "this is **bold** text"
        let doc = parser.parse(source)
        guard case .paragraph = doc.blocks[0] else { Issue.record("not paragraph"); return }
        let spans = parser.inlineSpans(in: doc.blocks[0], source: source)
        let nsSource = source as NSString
        let bolds = spans.compactMap { span -> NSRange? in
            if case let .bold(range, _) = span { return range } else { return nil }
        }
        #expect(bolds.count == 1)
        #expect(nsSource.substring(with: bolds[0]) == "**bold**")
    }

    @Test("extracts italic span")
    func extractsItalic() {
        let parser = MarkdownParser()
        let source = "*emph* word"
        let doc = parser.parse(source)
        let spans = parser.inlineSpans(in: doc.blocks[0], source: source)
        let italics = spans.compactMap { span -> NSRange? in
            if case let .italic(range, _) = span { return range } else { return nil }
        }
        #expect(italics.count == 1)
        let nsSource = source as NSString
        #expect(nsSource.substring(with: italics[0]) == "*emph*")
    }

    @Test("extracts inline code span")
    func extractsInlineCode() {
        let parser = MarkdownParser()
        let source = "use `let x = 1` here"
        let doc = parser.parse(source)
        let spans = parser.inlineSpans(in: doc.blocks[0], source: source)
        let codes = spans.compactMap { span -> NSRange? in
            if case let .inlineCode(range, _) = span { return range } else { return nil }
        }
        #expect(codes.count == 1)
        let nsSource = source as NSString
        #expect(nsSource.substring(with: codes[0]) == "`let x = 1`")
    }

    @Test("extracts strikethrough span (GFM)")
    func extractsStrike() {
        let parser = MarkdownParser()
        let source = "~~gone~~"
        let doc = parser.parse(source)
        let spans = parser.inlineSpans(in: doc.blocks[0], source: source)
        let strikes = spans.compactMap { span -> NSRange? in
            if case let .strike(range, _) = span { return range } else { return nil }
        }
        #expect(strikes.count == 1)
        let nsSource = source as NSString
        #expect(nsSource.substring(with: strikes[0]) == "~~gone~~")
    }

    @Test("extracts link with url")
    func extractsLink() {
        let parser = MarkdownParser()
        let source = "see [Apple](https://apple.com) site"
        let doc = parser.parse(source)
        let spans = parser.inlineSpans(in: doc.blocks[0], source: source)
        let links = spans.compactMap { span -> (NSRange, URL?)? in
            if case let .link(range, _, _, url) = span { return (range, url) } else { return nil }
        }
        #expect(links.count == 1)
        #expect(links[0].1?.absoluteString == "https://apple.com")
        let nsSource = source as NSString
        #expect(nsSource.substring(with: links[0].0) == "[Apple](https://apple.com)")
    }

    @Test("extracts image with url and alt")
    func extractsImage() {
        let parser = MarkdownParser()
        let source = "![logo](pic.png)"
        let doc = parser.parse(source)
        let spans = parser.inlineSpans(in: doc.blocks[0], source: source)
        let images = spans.compactMap { span -> (NSRange, URL?, String)? in
            if case let .image(range, _, url, alt) = span { return (range, url, alt) } else { return nil }
        }
        #expect(images.count == 1)
        #expect(images[0].2 == "logo")
        #expect(images[0].1?.absoluteString == "pic.png")
    }

    @Test("no inline spans for code blocks")
    func codeBlockHasNoSpans() {
        let parser = MarkdownParser()
        let source = "```\n**not bold**\n```"
        let doc = parser.parse(source)
        guard case .codeBlock = doc.blocks[0] else { Issue.record("not codeBlock"); return }
        let spans = parser.inlineSpans(in: doc.blocks[0], source: source)
        #expect(spans.isEmpty)
    }
}
