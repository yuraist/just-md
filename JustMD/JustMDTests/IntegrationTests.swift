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
