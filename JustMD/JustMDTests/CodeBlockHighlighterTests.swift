import Testing
import AppKit
@testable import JustMD

@Suite("CodeBlockHighlighter")
@MainActor
struct CodeBlockHighlighterTests {

    @Test("highlights swift code with non-empty result")
    func swiftHighlights() {
        let h = CodeBlockHighlighter()
        let result = h.highlight("let x = 1", language: "swift")
        #expect(result != nil)
        #expect(result?.string == "let x = 1")
    }

    @Test("highlight applies multiple foreground colors")
    func multipleColors() {
        let h = CodeBlockHighlighter()
        let code = "func greet(name: String) -> String { return \"Hello, \\(name)!\" }"
        let result = h.highlight(code, language: "swift")!
        var colors = Set<NSColor>()
        result.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: result.length),
            options: []
        ) { value, _, _ in
            if let c = value as? NSColor { colors.insert(c) }
        }
        // A non-trivial Swift snippet should have at least 2 distinct token colors
        // (keyword/string/type vs default text).
        #expect(colors.count >= 2)
    }

    @Test("highlights without language using auto-detect or plain")
    func noLanguage() {
        let h = CodeBlockHighlighter()
        let result = h.highlight("plain text", language: nil)
        #expect(result != nil)
    }
}
