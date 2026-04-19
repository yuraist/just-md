import AppKit
import Testing
@testable import JustMD

@Suite("MarkdownTextStorage")
@MainActor
struct MarkdownTextStorageTests {
    @Test("storage reports length and string match backing store")
    func lengthMatches() {
        let storage = MarkdownTextStorage()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "hello")
        #expect(storage.length == 5)
        #expect(storage.string == "hello")
    }
}
