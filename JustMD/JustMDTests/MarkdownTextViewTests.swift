import Testing
import AppKit
@testable import JustMD

@Suite("MarkdownTextView")
@MainActor
struct MarkdownTextViewTests {
    @Test("text view disables auto-corrections")
    func disablesAutoCorrections() {
        let tv = MarkdownTextView(storage: MarkdownTextStorage())
        #expect(tv.isRichText == false)
        #expect(tv.isAutomaticQuoteSubstitutionEnabled == false)
        #expect(tv.isAutomaticDashSubstitutionEnabled == false)
        #expect(tv.isAutomaticSpellingCorrectionEnabled == false)
        #expect(tv.isAutomaticTextReplacementEnabled == false)
    }

    @Test("toggleBold wraps selection in **")
    func toggleBoldWraps() {
        let storage = MarkdownTextStorage()
        let tv = MarkdownTextView(storage: storage)
        tv.string = "hello"
        tv.setSelectedRange(NSRange(location: 0, length: 5))
        tv.toggleBold(nil)
        #expect(tv.string == "**hello**")
        #expect(tv.selectedRange() == NSRange(location: 2, length: 5))
    }

    @Test("toggleItalic wraps selection in *")
    func toggleItalicWraps() {
        let storage = MarkdownTextStorage()
        let tv = MarkdownTextView(storage: storage)
        tv.string = "x"
        tv.setSelectedRange(NSRange(location: 0, length: 1))
        tv.toggleItalic(nil)
        #expect(tv.string == "*x*")
    }
}
