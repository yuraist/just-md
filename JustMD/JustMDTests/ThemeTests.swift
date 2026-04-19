import Testing
import Foundation
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
