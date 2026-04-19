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
        didSet { if oldValue != fontFamily { store.fontFamily = fontFamily } }
    }
    @Published var fontSize: Double {
        didSet { if oldValue != fontSize { store.fontSize = fontSize } }
    }
    @Published var lineHeight: Double {
        didSet { if oldValue != lineHeight { store.lineHeight = lineHeight } }
    }
    @Published var readingWidth: Double {
        didSet { if oldValue != readingWidth { store.readingWidth = readingWidth } }
    }
    @Published var themeId: String {
        didSet { if oldValue != themeId { store.themeId = themeId } }
    }
    @Published var allThemes: [Theme] = []

    private init() {
        self.fontFamily = store.fontFamily
        self.fontSize = store.fontSize
        self.lineHeight = store.lineHeight
        self.readingWidth = store.readingWidth
        self.themeId = store.themeId
        self.allThemes = themeStore.loadAll()
    }

    func reloadThemes() {
        allThemes = themeStore.loadAll()
    }
}
