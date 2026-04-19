import AppKit

nonisolated extension String {
    /// Parse a "#RRGGBB" or "#RRGGBBAA" hex color into RGBA components in 0...1.
    /// Returns nil for malformed input.
    var hexColorComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        var s = self
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        guard let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            let r = CGFloat((value >> 16) & 0xFF) / 255.0
            let g = CGFloat((value >> 8) & 0xFF) / 255.0
            let b = CGFloat(value & 0xFF) / 255.0
            return (r, g, b, 1.0)
        } else {
            let r = CGFloat((value >> 24) & 0xFF) / 255.0
            let g = CGFloat((value >> 16) & 0xFF) / 255.0
            let b = CGFloat((value >> 8) & 0xFF) / 255.0
            let a = CGFloat(value & 0xFF) / 255.0
            return (r, g, b, a)
        }
    }
}

extension NSColor {
    /// Construct an sRGB NSColor from a hex string ("#RRGGBB" or "#RRGGBBAA").
    /// Returns nil for malformed input.
    static func fromHex(_ hex: String) -> NSColor? {
        guard let c = hex.hexColorComponents else { return nil }
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    /// Returns "#RRGGBB" (or "#RRGGBBAA" if alpha < 1) for this color, converted to sRGB.
    var hexString: String {
        let srgb = usingColorSpace(.sRGB) ?? self
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        let a = Int(round(srgb.alphaComponent * 255))
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        } else {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
    }
}
