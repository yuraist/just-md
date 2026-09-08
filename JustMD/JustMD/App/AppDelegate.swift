//
//  AppDelegate.swift
//  JustMD
//
//  Created by Yuri Istomin on 4/18/26.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var themeMenu: NSMenu?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        installFormatMenu()
        installViewMenu()
        installShowWelcomeMenuItem()
        installSupportMenuItem()
        wirePreferencesMenuItem()
        // The Welcome window is shown through applicationOpenUntitledFile(_:),
        // which AppKit invokes only when the launch (or a Dock click) has
        // nothing else to show — no file to open, no windows restored. A
        // manual "documents.isEmpty" check here fires before state
        // restoration has re-created the documents and shows Welcome on top
        // of them.
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let themeStore = ThemeStore()
        var documentURLs: [URL] = []
        for url in urls {
            if url.pathExtension == "justmd-theme" {
                do {
                    let theme = try themeStore.importTheme(from: url)
                    PreferencesBridge.shared.reloadThemes()
                    let alert = NSAlert()
                    alert.messageText = "Imported theme '\(theme.name)'"
                    alert.informativeText = "The theme has been added to your custom presets."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                } catch {
                    NSAlert(error: error).runModal()
                }
            } else {
                documentURLs.append(url)
            }
        }
        for url in documentURLs {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // No-op.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Launch with nothing to open, or a Dock click / reopen with no
        // visible windows. Existing documents come back to the front;
        // otherwise Welcome stands in for an untitled document.
        let documents = NSDocumentController.shared.documents
        if !documents.isEmpty {
            for document in documents { document.showWindows() }
            return true
        }
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

        // Typography controls. These target AppDelegate directly (rather than
        // flowing through the responder chain) since they mutate global user
        // preferences, not the focused text view's state.
        formatMenu.addItem(NSMenuItem.separator())

        let bigger = NSMenuItem(title: "Bigger",
                                action: #selector(makeFontBigger(_:)),
                                keyEquivalent: "+")
        bigger.keyEquivalentModifierMask = .command
        bigger.target = self
        formatMenu.addItem(bigger)

        let smaller = NSMenuItem(title: "Smaller",
                                 action: #selector(makeFontSmaller(_:)),
                                 keyEquivalent: "-")
        smaller.keyEquivalentModifierMask = .command
        smaller.target = self
        formatMenu.addItem(smaller)

        let actual = NSMenuItem(title: "Actual Size",
                                action: #selector(makeFontActualSize(_:)),
                                keyEquivalent: "0")
        actual.keyEquivalentModifierMask = .command
        actual.target = self
        formatMenu.addItem(actual)

        formatMenu.addItem(NSMenuItem.separator())

        let serif = NSMenuItem(title: "Serif",
                               action: #selector(setFontSerif(_:)),
                               keyEquivalent: "1")
        serif.keyEquivalentModifierMask = [.command, .control]
        serif.target = self
        formatMenu.addItem(serif)

        let sans = NSMenuItem(title: "Sans",
                              action: #selector(setFontSans(_:)),
                              keyEquivalent: "2")
        sans.keyEquivalentModifierMask = [.command, .control]
        sans.target = self
        formatMenu.addItem(sans)

        let mono = NSMenuItem(title: "Mono",
                              action: #selector(setFontMono(_:)),
                              keyEquivalent: "3")
        mono.keyEquivalentModifierMask = [.command, .control]
        mono.target = self
        formatMenu.addItem(mono)

        formatItem.submenu = formatMenu

        // Insert after Edit (standard layout: app, File, Edit, ...).
        let editIndex = mainMenu.items.firstIndex { $0.title == "Edit" } ?? 2
        mainMenu.insertItem(formatItem, at: editIndex + 1)
    }

    private func installViewMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        if !mainMenu.items.contains(where: { $0.title == "View" }) {
            let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
            let viewMenu = NSMenu(title: "View")
            viewItem.submenu = viewMenu
            let formatIndex = mainMenu.items.firstIndex { $0.title == "Format" } ?? mainMenu.items.count - 1
            mainMenu.insertItem(viewItem, at: formatIndex + 1)
        }
        installReadingModeMenuItem()
        installThemeSubmenu()
    }

    private func installReadingModeMenuItem() {
        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu else { return }
        if viewMenu.items.contains(where: { $0.title == "Reading Mode" }) { return }
        let item = NSMenuItem(
            title: "Reading Mode",
            action: #selector(DocumentViewController.toggleReadMode(_:)),
            keyEquivalent: "e"
        )
        item.keyEquivalentModifierMask = [.command, .shift]
        if viewMenu.items.isEmpty {
            viewMenu.addItem(item)
        } else {
            viewMenu.insertItem(item, at: 0)
        }
        viewMenu.insertItem(NSMenuItem.separator(), at: 1)
    }

    private func installThemeSubmenu() {
        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu else { return }
        if viewMenu.items.contains(where: { $0.title == "Theme" }) { return }
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Theme")
        themeItem.submenu = menu
        viewMenu.addItem(themeItem)
        self.themeMenu = menu
        refreshThemeMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshThemeMenuFromNotification),
            name: PreferencesStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func refreshThemeMenuFromNotification() {
        refreshThemeMenu()
    }

    private func refreshThemeMenu() {
        guard let menu = themeMenu else { return }
        menu.removeAllItems()
        let themes = ThemeStore().loadAll()
        let currentId = PreferencesStore.shared.themeId
        for theme in themes {
            let item = NSMenuItem(title: theme.name,
                                  action: #selector(selectTheme(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = theme.id
            item.state = (theme.id == currentId) ? .on : .off
            menu.addItem(item)
        }
    }

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        PreferencesStore.shared.themeId = id
    }

    // MARK: - Font menu actions

    @objc func makeFontBigger(_ sender: Any?) {
        let prefs = PreferencesStore.shared
        prefs.fontSize = min(prefs.fontSize + 1, 32)
    }

    @objc func makeFontSmaller(_ sender: Any?) {
        let prefs = PreferencesStore.shared
        prefs.fontSize = max(prefs.fontSize - 1, 10)
    }

    @objc func makeFontActualSize(_ sender: Any?) {
        PreferencesStore.shared.fontSize = 16
    }

    @objc func setFontSerif(_ sender: Any?) {
        PreferencesStore.shared.fontFamily = .serif
    }

    @objc func setFontSans(_ sender: Any?) {
        PreferencesStore.shared.fontFamily = .sans
    }

    @objc func setFontMono(_ sender: Any?) {
        PreferencesStore.shared.fontFamily = .mono
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

    private func installSupportMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let helpMenu = mainMenu.items.first(where: { $0.title == "Help" })?.submenu else { return }
        if helpMenu.items.contains(where: { $0.title == "Support JustMD…" }) { return }
        let item = NSMenuItem(title: "Support JustMD…",
                              action: #selector(showSupport(_:)),
                              keyEquivalent: "")
        item.target = self
        if !helpMenu.items.isEmpty { helpMenu.addItem(NSMenuItem.separator()) }
        helpMenu.addItem(item)
    }

    @objc func showSupport(_ sender: Any?) {
        SupportWindowController.shared.showWindow(sender)
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
