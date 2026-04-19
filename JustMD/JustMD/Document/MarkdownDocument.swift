import AppKit

final class MarkdownDocument: NSDocument {
    var text: String = ""

    nonisolated override class var autosavesInPlace: Bool { true }
    nonisolated override class var preservesVersions: Bool { true }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        }
        MainActor.assumeIsolated {
            self.text = string
        }
    }

    nonisolated override func data(ofType typeName: String) throws -> Data {
        let snapshot = MainActor.assumeIsolated { self.text }
        return snapshot.data(using: .utf8) ?? Data()
    }

    override func makeWindowControllers() {
        let controller = MarkdownWindowController(document: self)
        self.addWindowController(controller)
    }
}
