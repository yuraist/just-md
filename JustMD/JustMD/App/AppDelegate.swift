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
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // No-op.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu

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
}
