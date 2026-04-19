import AppKit

final class MarkdownDocument: NSDocument {
    var text: String = ""

    static let didReloadNotification = Notification.Name("com.justmd.document.didReload")

    nonisolated override class var autosavesInPlace: Bool { true }
    nonisolated override class var preservesVersions: Bool { true }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        }
        MainActor.assumeIsolated {
            self.text = string
        }
        // Notify any open editor view to reload its storage from the new text.
        // Post on the main queue so observers registered with a main-queue-
        // isolated selector receive it there.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: MarkdownDocument.didReloadNotification, object: self)
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

    // NSDocument conforms to NSFilePresenter automatically. `presentedItemDidChange`
    // fires on an arbitrary queue; bounce to main before touching document state.
    nonisolated override func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handleExternalChange()
        }
    }

    @MainActor
    private func handleExternalChange() {
        guard let url = self.fileURL else { return }

        // Skip if the change was our own autosave/save.
        // NSDocument tracks the modification date it last knew about; if the
        // file's current mtime matches (within sub-second tolerance), this
        // notification is from our own write and there's nothing external to react to.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let diskMod = attrs[.modificationDate] as? Date,
           let ours = self.fileModificationDate,
           abs(diskMod.timeIntervalSince(ours)) < 1.0 {
            return
        }

        let typeName = self.fileType ?? "net.daringfireball.markdown"
        if !self.isDocumentEdited {
            try? self.revert(toContentsOf: url, ofType: typeName)
            return
        }
        let alert = NSAlert()
        alert.messageText = "File changed on disk"
        alert.informativeText = "Revert to the disk version? You'll lose unsaved changes."
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Keep My Changes")
        if alert.runModal() == .alertFirstButtonReturn {
            try? self.revert(toContentsOf: url, ofType: typeName)
        }
    }
}
