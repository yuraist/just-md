import Testing
import Foundation
@testable import JustMD

@Suite("MarkdownFormatter")
struct MarkdownFormatterTests {

    @Test("empty selection inserts **** and places caret between (bold)")
    func emptyBold() {
        let result = MarkdownFormatter.wrap(source: "abc", selection: NSRange(location: 1, length: 0), delimiter: .bold)
        #expect(result.newString == "a****bc")
        #expect(result.newSelection == NSRange(location: 3, length: 0))
    }

    @Test("empty selection inserts ** and places caret between (italic)")
    func emptyItalic() {
        let result = MarkdownFormatter.wrap(source: "abc", selection: NSRange(location: 1, length: 0), delimiter: .italic)
        #expect(result.newString == "a**bc")
        #expect(result.newSelection == NSRange(location: 2, length: 0))
    }

    @Test("wraps non-empty selection in bold")
    func wrapBold() {
        let result = MarkdownFormatter.wrap(source: "hello world", selection: NSRange(location: 0, length: 5), delimiter: .bold)
        #expect(result.newString == "**hello** world")
        #expect(result.newSelection == NSRange(location: 2, length: 5))
    }

    @Test("wraps non-empty selection in italic")
    func wrapItalic() {
        let result = MarkdownFormatter.wrap(source: "hello world", selection: NSRange(location: 0, length: 5), delimiter: .italic)
        #expect(result.newString == "*hello* world")
        #expect(result.newSelection == NSRange(location: 1, length: 5))
    }

    @Test("unwraps selection that includes bold delimiters")
    func unwrapIncludingDelimiters() {
        let result = MarkdownFormatter.wrap(source: "**foo**", selection: NSRange(location: 0, length: 7), delimiter: .bold)
        #expect(result.newString == "foo")
        #expect(result.newSelection == NSRange(location: 0, length: 3))
    }

    @Test("unwraps selection that's inside bold delimiters")
    func unwrapInsideDelimiters() {
        let result = MarkdownFormatter.wrap(source: "x **foo** y", selection: NSRange(location: 4, length: 3), delimiter: .bold)
        #expect(result.newString == "x foo y")
        #expect(result.newSelection == NSRange(location: 2, length: 3))
    }

    @Test("unwraps selection inside italic delimiters")
    func unwrapItalicInside() {
        let result = MarkdownFormatter.wrap(source: "*x*", selection: NSRange(location: 1, length: 1), delimiter: .italic)
        #expect(result.newString == "x")
        #expect(result.newSelection == NSRange(location: 0, length: 1))
    }
}
