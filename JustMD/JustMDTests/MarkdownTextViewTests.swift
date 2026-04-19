import Testing
import AppKit
@testable import JustMD

@Suite("MarkdownTextView")
@MainActor
struct MarkdownTextViewTests {
    @Test("text view installs custom layout manager")
    func customLayoutManager() {
        let storage = MarkdownTextStorage()
        let tv = MarkdownTextView(storage: storage)
        #expect(tv.layoutManager is HiddenMarkerLayoutManager)
    }

    @Test("text view disables auto-corrections")
    func disablesAutoCorrections() {
        let tv = MarkdownTextView(storage: MarkdownTextStorage())
        #expect(tv.isRichText == false)
        #expect(tv.isAutomaticQuoteSubstitutionEnabled == false)
        #expect(tv.isAutomaticDashSubstitutionEnabled == false)
        #expect(tv.isAutomaticSpellingCorrectionEnabled == false)
        #expect(tv.isAutomaticTextReplacementEnabled == false)
    }

    @Test("active line updates on selection change")
    func activeLineUpdates() {
        let storage = MarkdownTextStorage()
        let tv = MarkdownTextView(storage: storage)
        tv.string = "first line\nsecond line\nthird line"
        // Force layout manager to load.
        _ = tv.layoutManager
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        let lm = tv.layoutManager as! HiddenMarkerLayoutManager
        #expect(NSLocationInRange(5, lm.activeLineRange))
        tv.setSelectedRange(NSRange(location: 15, length: 0))
        #expect(NSLocationInRange(15, lm.activeLineRange))
    }
}
