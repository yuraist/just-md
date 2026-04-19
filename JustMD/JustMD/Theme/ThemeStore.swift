import Foundation

nonisolated public final class ThemeStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("JustMD/Themes", isDirectory: true)
        }
    }

    /// Returns builtins + user themes from the store directory.
    public func loadAll() -> [Theme] {
        let user = loadUser()
        return BuiltinThemes.all + user
    }

    /// Returns only user themes.
    public func loadUser() -> [Theme] {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "justmd-theme" }
            .compactMap { url -> Theme? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Theme.self, from: data)
            }
    }

    /// Persists a theme to `<directory>/<id>.justmd-theme`.
    public func save(_ theme: Theme) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(theme.id).justmd-theme")
        let data = try JSONEncoder().encode(theme)
        try data.write(to: url, options: .atomic)
    }

    /// Removes the theme's file from disk.
    public func delete(_ theme: Theme) throws {
        let url = directory.appendingPathComponent("\(theme.id).justmd-theme")
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Reads a `.justmd-theme` file, assigns a fresh user id, persists, returns the new theme.
    public func importTheme(from url: URL) throws -> Theme {
        let data = try Data(contentsOf: url)
        var theme = try JSONDecoder().decode(Theme.self, from: data)
        // Decode of a fresh file already generates user.<uuid> id and isBuiltin=false.
        // But if the file had an explicit id (e.g., another user re-shared), regenerate to avoid collisions.
        if !theme.id.hasPrefix("user.") {
            theme = Theme(id: "user.\(UUID().uuidString)", name: theme.name, isBuiltin: false, light: theme.light, dark: theme.dark)
        }
        try save(theme)
        return theme
    }

    /// Writes a shareable .justmd-theme file (no id, no isBuiltin) to the given URL.
    public func exportTheme(_ theme: Theme, to url: URL) throws {
        struct ExportShape: Encodable {
            let schema: Int = 1
            let name: String
            let light: Palette
            let dark: Palette?
        }
        let payload = ExportShape(name: theme.name, light: theme.light, dark: theme.dark)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }
}
