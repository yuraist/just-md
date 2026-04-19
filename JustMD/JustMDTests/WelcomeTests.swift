//
//  WelcomeTests.swift
//  JustMDTests
//
//  Created by Yuri Istomin on 4/18/26.
//

import Testing
import AppKit
@testable import JustMD

@Suite("Welcome window")
@MainActor
struct WelcomeTests {
    @Test("WelcomeWindowController has a window with expected size")
    func windowExists() {
        let wc = WelcomeWindowController.shared
        #expect(wc.window != nil)
        #expect(wc.window!.contentView != nil)
    }
}
