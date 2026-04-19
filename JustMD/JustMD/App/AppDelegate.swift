//
//  AppDelegate.swift
//  JustMD
//
//  Created by Yuri Istomin on 4/18/26.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        installFormatMenu()
        installShowWelcomeMenuItem()
        wirePreferencesMenuItem()

        // Show welcome window on launch if no documents are being opened.
        // NSDocumentController.openDocument may already be in flight from a "Open Recent" / file association.
        // Use a delayed check so doc-opening machinery has run first.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                WelcomeWindowController.shared.showWindow(self)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // No-op.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // System asks us to open an untitled doc (e.g. dock icon click with no windows).
        // Show welcome instead.
        WelcomeWindowController.shared.showWindow(self)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menus

    private func installFormatMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        // Avoid double-installing if the menu is already present.
        if mainMenu.items.contains(where: { $0.title == "Format" }) { return }

        let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        let formatMenu = NSMenu(title: "Format")

        // Reference our own override for the selector. The menu dispatches via
        // the first responder chain, so any responder implementing the same
        // selector name (`toggleBold:` / `toggleItalic:`) will receive it.
        let bold = NSMenuItem(title: "Bold",
                              action: #selector(MarkdownTextView.toggleBold(_:)),
                              keyEquivalent: "b")
        bold.keyEquivalentModifierMask = NSEvent.ModifierFlags.command

        let italic = NSMenuItem(title: "Italic",
                                action: #selector(MarkdownTextView.toggleItalic(_:)),
                                keyEquivalent: "i")
        italic.keyEquivalentModifierMask = NSEvent.ModifierFlags.command

        formatMenu.addItem(bold)
        formatMenu.addItem(italic)
        formatItem.submenu = formatMenu

        // Insert after Edit (standard layout: app, File, Edit, ...).
        let editIndex = mainMenu.items.firstIndex { $0.title == "Edit" } ?? 2
        mainMenu.insertItem(formatItem, at: editIndex + 1)
    }

    private func installShowWelcomeMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let fileMenu = mainMenu.items.first(where: { $0.title == "File" })?.submenu else { return }
        // Check if already installed.
        if fileMenu.items.contains(where: { $0.title == "Show Welcome Window" }) { return }
        let item = NSMenuItem(title: "Show Welcome Window",
                              action: #selector(showWelcome(_:)),
                              keyEquivalent: "w")
        item.keyEquivalentModifierMask = [.command, .control]
        item.target = self
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(item)
    }

    @objc func showWelcome(_ sender: Any?) {
        WelcomeWindowController.shared.showWindow(sender)
    }

    @objc func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow(sender)
    }

    private func wirePreferencesMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let appSubmenu = mainMenu.items.first?.submenu else { return }
        let titles: Set<String> = ["Preferences…", "Settings…", "Preferences...", "Settings..."]
        guard let item = appSubmenu.items.first(where: { titles.contains($0.title) }) else { return }
        item.target = self
        item.action = #selector(showPreferences(_:))
    }
}
