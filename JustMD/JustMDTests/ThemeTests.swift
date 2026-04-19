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
