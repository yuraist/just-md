import AppKit
import SwiftUI

@MainActor
final class SupportWindowController: NSWindowController {
    static let shared = SupportWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Support JustMD"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let hosting = NSHostingController(rootView: SupportView())
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
