//
//  WelcomeWindowController.swift
//  JustMD
//
//  Created by Yuri Istomin on 4/18/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.title = "JustMD"

        super.init(window: window)

        let view = WelcomeView(
            onNew: { [weak self] in self?.handleNew() },
            onOpen: { [weak self] in self?.handleOpen() },
            onOpenURL: { [weak self] url in self?.handleOpenURL(url) }
        )
        window.contentView = NSHostingView(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func handleNew() {
        let panel = NSSavePanel()
        if let mdType = UTType("net.daringfireball.markdown") {
            panel.allowedContentTypes = [mdType]
        }
        panel.nameFieldStringValue = "Untitled.md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try "".write(to: url, atomically: true, encoding: .utf8)
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                self.window?.close()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func handleOpen() {
        NSDocumentController.shared.openDocument(self)
        // Note: we don't close welcome here; if user cancels they may want to come back to it.
        // If document opens successfully, welcome stays open. User can close manually.
    }

    private func handleOpenURL(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, _ in
            self?.window?.close()
        }
    }
}
