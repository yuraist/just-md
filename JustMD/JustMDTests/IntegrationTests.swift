//
//  IntegrationTests.swift
//  JustMDTests
//
//  Smoke tests covering design assumptions wired up in Phase 10:
//  - "Follow System" builtin theme actually carries a dark palette.
//  - Font-size clamp accepts the 10...32 range exposed by the Format menu.
//

import Testing
import AppKit
import Foundation
@testable import JustMD

@Suite("Read mode integration")
@MainActor
struct ReadModeIntegrationTests {
    @Test("toggling read mode swaps the document view and renders content")
    func toggleSwapsViews() {
        let document = MarkdownDocument()
        document.text = "# Title\n\n| A | B |\n|---|---|\n| 1 | 2 |\n"
        let vc = DocumentViewController(document: document)
        _ = vc.view  // force loadView

        let scroll = vc.view as? NSScrollView
        let editorView = scroll?.documentView
        #expect(vc.isReadMode == false)

        vc.toggleReadMode(nil)
        #expect(vc.isReadMode == true)
        let readView = scroll?.documentView as? NSTextView
        #expect(readView !== editorView)
        #expect(readView?.isEditable == false)
        let rendered = readView?.textStorage?.string ?? ""
        #expect(rendered.contains("Title"))
        #expect(!rendered.contains("#"))
        #expect(!rendered.contains("|"))

        vc.toggleReadMode(nil)
        #expect(vc.isReadMode == false)
        #expect(scroll?.documentView === editorView)
    }
}

@Suite("Theme integration")
@MainActor
struct ThemeIntegrationTests {
    @Test("Follow System builtin theme provides a dark palette")
    func followSystemDark() throws {
        let theme = try #require(BuiltinThemes.all.first(where: { $0.id == "builtin.followSystem" }))
        #expect(theme.dark != nil)
    }

    @Test("Font size clamps to [10, 32] for menu +/- actions")
    func fontSizeClampRange() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PreferencesStore(defaults: defaults)
        store.fontSize = 100
        #expect(store.fontSize == 32)
        store.fontSize = 1
        #expect(store.fontSize == 10)
    }
}
