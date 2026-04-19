import Combine
import Foundation
import SwiftUI

/// An `ObservableObject` façade over `PreferencesStore` so SwiftUI `@Published` bindings can drive the UI.
@MainActor
final class PreferencesBridge: ObservableObject {
    static let shared = PreferencesBridge()

    private let store = PreferencesStore.shared
    private let themeStore = ThemeStore()

    @Published var fontFamily: PreferencesStore.FontFamily {
        didSet {
            guard !isSyncing, oldValue != fontFamily else { return }
            store.fontFamily = fontFamily
        }
    }
    @Published var fontSize: Double {
        didSet {
            guard !isSyncing, oldValue != fontSize else { return }
            store.fontSize = fontSize
        }
    }
    @Published var lineHeight: Double {
        didSet {
            guard !isSyncing, oldValue != lineHeight else { return }
            store.lineHeight = lineHeight
        }
    }
    @Published var readingWidth: Double {
        didSet {
            guard !isSyncing, oldValue != readingWidth else { return }
            store.readingWidth = readingWidth
        }
    }
    @Published var themeId: String {
        didSet {
            guard !isSyncing, oldValue != themeId else { return }
            store.themeId = themeId
        }
    }
    @Published var allThemes: [Theme] = []

    /// True while we're mirroring store values back into published properties.
    /// Prevents the `didSet` observers from writing back to the store (which
    /// would post another `didChangeNotification` and loop).
    private var isSyncing = false
    private var observer: NSObjectProtocol?

    private init() {
        self.fontFamily = store.fontFamily
        self.fontSize = store.fontSize
        self.lineHeight = store.lineHeight
        self.readingWidth = store.readingWidth
        self.themeId = store.themeId
        self.allThemes = themeStore.loadAll()

        self.observer = NotificationCenter.default.addObserver(
            forName: PreferencesStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFromStore()
            }
        }
    }

    // No deinit: `PreferencesBridge` is a process-lifetime singleton and the
    // observer handle outlives us trivially. Adding a nonisolated `deinit` that
    // touches `observer` trips Swift 6 concurrency because
    // `any NSObjectProtocol` is not Sendable.

    private func syncFromStore() {
        isSyncing = true
        defer { isSyncing = false }
        let newFamily = store.fontFamily
        if fontFamily != newFamily { fontFamily = newFamily }
        let newSize = store.fontSize
        if fontSize != newSize { fontSize = newSize }
        let newLine = store.lineHeight
        if lineHeight != newLine { lineHeight = newLine }
        let newWidth = store.readingWidth
        if readingWidth != newWidth { readingWidth = newWidth }
        let newThemeId = store.themeId
        if themeId != newThemeId { themeId = newThemeId }
    }

    func reloadThemes() {
        allThemes = themeStore.loadAll()
    }
}
