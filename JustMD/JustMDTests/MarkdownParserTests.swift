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
}
