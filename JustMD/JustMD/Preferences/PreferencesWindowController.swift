import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // macOS 13+ calls this window "Settings" (the app menu item is renamed
        // by the system); match it.
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let hosting = NSHostingController(rootView: PreferencesView())
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }
}
