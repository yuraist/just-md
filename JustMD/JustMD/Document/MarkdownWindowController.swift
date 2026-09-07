import AppKit

final class MarkdownWindowController: NSWindowController, NSToolbarDelegate {

    private static let readToggleID = NSToolbarItem.Identifier("com.justmd.readToggle")

    /// Top-left of the most recently placed document window; each new window
    /// cascades from it instead of landing exactly on top of the last one.
    private static var nextCascadePoint = NSPoint.zero

    init(document: MarkdownDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unifiedCompact
        window.center()
        Self.nextCascadePoint = window.cascadeTopLeft(from: Self.nextCascadePoint)
        super.init(window: window)
        self.contentViewController = DocumentViewController(document: document)

        let toolbar = NSToolbar(identifier: "com.justmd.document-toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readModeDidChange(_:)),
            name: DocumentViewController.readModeDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // A document on screen is what the Welcome window exists to produce;
        // keep it from lingering behind the editor.
        if let welcome = WelcomeWindowController.shared.window, welcome.isVisible {
            welcome.orderOut(nil)
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.readToggleID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.readToggleID]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.readToggleID else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isBordered = true
        item.action = #selector(DocumentViewController.toggleReadMode(_:))
        item.target = nil
        configure(item, isReadMode: false)
        return item
    }

    @objc private func readModeDidChange(_ note: Notification) {
        guard let vc = note.object as? DocumentViewController,
              vc === contentViewController,
              let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.readToggleID })
        else { return }
        configure(item, isReadMode: vc.isReadMode)
    }

    private func configure(_ item: NSToolbarItem, isReadMode: Bool) {
        item.label = isReadMode ? "Edit" : "Read"
        item.toolTip = isReadMode ? "Back to editing (⇧⌘E)" : "Reading mode (⇧⌘E)"
        item.image = NSImage(
            systemSymbolName: isReadMode ? "pencil" : "book",
            accessibilityDescription: item.label
        )
    }
}
