import Testing
import Foundation
import AppKit
@testable import JustMD

@Suite("Theme codable")
struct ThemeTests {
    @Test("decodes example .justmd-theme JSON")
    func decodes() throws {
        let json = """
        {
          "schema": 1,
          "name": "Nord Focus",
          "author": "yuri",
          "light": {
            "background": "#ECEFF4",
            "text": "#2E3440",
            "accent": "#5E81AC",
            "secondary": "#D8DEE9",
            "codeBackground": "#E5E9F0",
            "selection": "#88C0D0"
          }
        }
        """.data(using: .utf8)!

        let theme = try JSONDecoder().decode(Theme.self, from: json)
        #expect(theme.name == "Nord Focus")
        #expect(theme.light.background == "#ECEFF4")
        #expect(theme.dark == nil)
    }

    @Test("round-trips encode/decode")
    func roundTrip() throws {
        let palette = Palette(background: "#FFFFFF", text: "#000000", accent: "#0066CC", secondary: "#888888", codeBackground: "#F5F5F5", selection: "#B3D4FC")
        let theme = Theme(id: "user.test", name: "T", isBuiltin: false, light: palette, dark: nil)
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded.name == "T")
    }
}

@Suite("Palette color conversion")
struct PaletteColorTests {
    @Test("parses #RRGGBB hex into NSColor with correct components")
    func parsesRGB() throws {
        let color = try #require(NSColor.fromHex("#ECEFF4"))
        let srgb = try #require(color.usingColorSpace(.sRGB))
        let eps: CGFloat = 0.005
        #expect(abs(srgb.redComponent - 236.0/255.0) < eps)
        #expect(abs(srgb.greenComponent - 239.0/255.0) < eps)
        #expect(abs(srgb.blueComponent - 244.0/255.0) < eps)
        #expect(abs(srgb.alphaComponent - 1.0) < eps)
    }

    @Test("parses #RRGGBBAA hex with alpha")
    func parsesRGBA() throws {
        let color = try #require(NSColor.fromHex("#FF000080"))
        let srgb = try #require(color.usingColorSpace(.sRGB))
        let eps: CGFloat = 0.005
        #expect(abs(srgb.redComponent - 1.0) < eps)
        #expect(abs(srgb.greenComponent - 0.0) < eps)
        #expect(abs(srgb.blueComponent - 0.0) < eps)
        #expect(abs(srgb.alphaComponent - 128.0/255.0) < eps)
    }

    @Test("round-trips hex through NSColor")
    func roundTrip() throws {
        let original = "#ECEFF4"
        let color = try #require(NSColor.fromHex(original))
        #expect(color.hexString == original)
    }

    @Test("round-trips RGBA hex with alpha")
    func roundTripWithAlpha() throws {
        let original = "#5E81ACFF"  // alpha=FF should encode without alpha component
        let color = try #require(NSColor.fromHex(original))
        #expect(color.hexString == "#5E81AC")  // simplified to RGB-only
    }

    @Test("returns nil for malformed hex")
    func malformed() {
        #expect(NSColor.fromHex("#XYZ") == nil)
        #expect(NSColor.fromHex("#12") == nil)
        #expect(NSColor.fromHex("hello") == nil)
    }
}

@Suite("Builtin themes")
struct BuiltinThemesTests {
    @Test("loads all 5 builtin themes")
    func count() {
        #expect(BuiltinThemes.all.count == 5)
    }

    @Test("themes have expected ids")
    func ids() {
        let ids = Set(BuiltinThemes.all.map(\.id))
        #expect(ids == ["builtin.followSystem", "builtin.white", "builtin.sepia", "builtin.gray", "builtin.black"])
    }

    @Test("all themes are marked builtin")
    func areBuiltin() {
        let allBuiltin = BuiltinThemes.all.allSatisfy { $0.isBuiltin }
        #expect(allBuiltin)
    }

    @Test("Follow System theme has both light and dark palettes")
    func followSystemHasDark() throws {
        let theme = try #require(BuiltinThemes.all.first { $0.id == "builtin.followSystem" })
        #expect(theme.dark != nil)
    }
}

@Suite("ThemeStore")
struct ThemeStoreTests {

    private func makeTempStore() -> (ThemeStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeStoreTests-\(UUID().uuidString)")
        return (ThemeStore(directory: dir), dir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private let samplePalette = Palette(
        background: "#FFFFFF", text: "#000000", accent: "#0066CC",
        secondary: "#888888", codeBackground: "#F5F5F5", selection: "#B3D4FC"
    )

    @Test("save then loadUser returns the saved theme")
    func saveAndLoad() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let theme = Theme(id: "user.abc", name: "Mine", isBuiltin: false, light: samplePalette)
        try store.save(theme)

        let loaded = store.loadUser()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "user.abc")
        #expect(loaded[0].name == "Mine")
    }

    @Test("loadAll returns builtins plus user themes")
    func loadAll() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let theme = Theme(id: "user.abc", name: "Mine", isBuiltin: false, light: samplePalette)
        try store.save(theme)

        let all = store.loadAll()
        #expect(all.count == BuiltinThemes.all.count + 1)
        #expect(all.contains { $0.id == "user.abc" })
    }

    @Test("delete removes the theme file")
    func delete() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let theme = Theme(id: "user.delme", name: "Bye", isBuiltin: false, light: samplePalette)
        try store.save(theme)
        #expect(store.loadUser().count == 1)

        try store.delete(theme)
        #expect(store.loadUser().isEmpty)
    }

    @Test("importTheme assigns a fresh user.<uuid> id and persists")
    func importFresh() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let json = """
        {
          "schema": 1,
          "name": "Imported",
          "light": {
            "background": "#FFFFFF",
            "text": "#000000",
            "accent": "#0066CC",
            "secondary": "#888888",
            "codeBackground": "#F5F5F5",
            "selection": "#B3D4FC"
          }
        }
        """.data(using: .utf8)!
        let srcURL = dir.appendingPathComponent("incoming.justmd-theme")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: srcURL)

        let imported = try store.importTheme(from: srcURL)
        #expect(imported.id.hasPrefix("user."))
        #expect(imported.name == "Imported")
        #expect(imported.isBuiltin == false)

        let user = store.loadUser()
        #expect(user.contains { $0.id == imported.id })
    }

    @Test("importTheme regenerates id when source has builtin-style id")
    func importRegeneratesBuiltinId() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let json = """
        {
          "schema": 1,
          "id": "builtin.fake",
          "isBuiltin": true,
          "name": "Pretender",
          "light": {
            "background": "#FFFFFF",
            "text": "#000000",
            "accent": "#0066CC",
            "secondary": "#888888",
            "codeBackground": "#F5F5F5",
            "selection": "#B3D4FC"
          }
        }
        """.data(using: .utf8)!
        let srcURL = dir.appendingPathComponent("pretender.justmd-theme")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: srcURL)

        let imported = try store.importTheme(from: srcURL)
        #expect(imported.id.hasPrefix("user."))
        #expect(imported.isBuiltin == false)
    }

    @Test("exportTheme writes a shareable file without id/isBuiltin")
    func export() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let theme = Theme(id: "user.xyz", name: "Exported", isBuiltin: false, light: samplePalette)
        let outURL = dir.appendingPathComponent("out.justmd-theme")
        try store.exportTheme(theme, to: outURL)

        let data = try Data(contentsOf: outURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["name"] as? String == "Exported")
        #expect(json?["schema"] as? Int == 1)
        #expect(json?["id"] == nil)
        #expect(json?["isBuiltin"] == nil)
    }
}
