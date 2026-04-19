import AppKit
import Foundation

/// Persistent user preferences for typography, reading width, and active theme.
/// Each setter writes to `UserDefaults` and posts `didChangeNotification` on the main queue.
nonisolated public final class PreferencesStore: @unchecked Sendable {
    public enum FontFamily: String, CaseIterable, Sendable {
        case serif
        case sans
        case mono
    }

    public static let didChangeNotification = Notification.Name("com.justmd.preferences.didChange")

    private enum Keys {
        static let fontFamily = "com.justmd.prefs.fontFamily"
        static let fontSize = "com.justmd.prefs.fontSize"
        static let lineHeight = "com.justmd.prefs.lineHeight"
        static let readingWidth = "com.justmd.prefs.readingWidth"
        static let themeId = "com.justmd.prefs.themeId"
    }

    private enum Defaults {
        static let fontFamily: FontFamily = .sans
        static let fontSize: Double = 16
        static let lineHeight: Double = 1.5
        static let readingWidth: Double = 720
        static let themeId: String = "builtin.followSystem"
    }

    public static let shared: PreferencesStore = .init()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var fontFamily: FontFamily {
        get {
            guard let raw = defaults.string(forKey: Keys.fontFamily),
                  let value = FontFamily(rawValue: raw) else {
                return Defaults.fontFamily
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.fontFamily)
            postDidChange()
        }
    }

    public var fontSize: Double {
        get {
            let v = defaults.object(forKey: Keys.fontSize) as? Double
            return v ?? Defaults.fontSize
        }
        set {
            let clamped = min(max(newValue, 12), 24)
            defaults.set(clamped, forKey: Keys.fontSize)
            postDidChange()
        }
    }

    public var lineHeight: Double {
        get {
            let v = defaults.object(forKey: Keys.lineHeight) as? Double
            return v ?? Defaults.lineHeight
        }
        set {
            let clamped = min(max(newValue, 1.2), 2.0)
            defaults.set(clamped, forKey: Keys.lineHeight)
            postDidChange()
        }
    }

    public var readingWidth: Double {
        get {
            let v = defaults.object(forKey: Keys.readingWidth) as? Double
            return v ?? Defaults.readingWidth
        }
        set {
            defaults.set(newValue, forKey: Keys.readingWidth)
            postDidChange()
        }
    }

    public var themeId: String {
        get {
            defaults.string(forKey: Keys.themeId) ?? Defaults.themeId
        }
        set {
            defaults.set(newValue, forKey: Keys.themeId)
            postDidChange()
        }
    }

    private func postDidChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: PreferencesStore.didChangeNotification, object: self)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PreferencesStore.didChangeNotification, object: self)
            }
        }
    }

    /// Resolves the configured `FontFamily` and size to an `NSFont` via `NSFontDescriptor` with the appropriate design.
    public static func nsFont(family: FontFamily, size: CGFloat) -> NSFont {
        let baseDescriptor: NSFontDescriptor
        switch family {
        case .serif:
            baseDescriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor
        case .sans:
            baseDescriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        case .mono:
            baseDescriptor = NSFont.monospacedSystemFont(ofSize: size, weight: .regular).fontDescriptor
        }
        return NSFont(descriptor: baseDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}
