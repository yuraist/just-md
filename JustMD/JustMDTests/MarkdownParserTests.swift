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
}
