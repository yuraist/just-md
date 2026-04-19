//
//  PreferencesTests.swift
//  JustMDTests
//
//  Created by Yuri Istomin on 4/18/26.
//

import Testing
import Foundation
@testable import JustMD

@Suite("PreferencesStore")
@MainActor
struct PreferencesStoreTests {
    @Test("default values are sensible")
    func defaults() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PreferencesStore(defaults: defaults)
        #expect(store.fontFamily == .sans)
        #expect(store.fontSize == 16)
        #expect(store.lineHeight == 1.5)
        #expect(store.readingWidth == 720)
        #expect(store.themeId == "builtin.followSystem")
    }

    @Test("setting values persists across instances")
    func persistence() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store1 = PreferencesStore(defaults: defaults)
        store1.fontFamily = .serif
        store1.fontSize = 18
        store1.themeId = "user.foo"

        let store2 = PreferencesStore(defaults: defaults)
        #expect(store2.fontFamily == .serif)
        #expect(store2.fontSize == 18)
        #expect(store2.themeId == "user.foo")
    }
}
