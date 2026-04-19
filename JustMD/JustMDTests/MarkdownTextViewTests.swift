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
}
