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
        // No-op for now; Welcome window comes in Phase 8.
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
}
