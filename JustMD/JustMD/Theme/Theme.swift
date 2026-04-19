import Foundation

nonisolated public struct Theme: Codable, Sendable, Identifiable, Equatable {
    public let id: String          // "builtin.white" or "user.<uuid>"
    public var name: String
    public var isBuiltin: Bool
    public var light: Palette      // required
    public var dark: Palette?      // optional

    public init(id: String, name: String, isBuiltin: Bool, light: Palette, dark: Palette? = nil) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.light = light
        self.dark = dark
    }

    // Custom Codable: .justmd-theme files have no `id` or `isBuiltin` fields.
    // When decoding such a file, generate a fresh user id and mark not-builtin.
    private enum CodingKeys: String, CodingKey {
        case schema, name, author, light, dark, id, isBuiltin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // schema and author are accepted but not stored (forward-compat hooks).
        _ = try c.decodeIfPresent(Int.self, forKey: .schema)
        _ = try c.decodeIfPresent(String.self, forKey: .author)
        self.name = try c.decode(String.self, forKey: .name)
        self.light = try c.decode(Palette.self, forKey: .light)
        self.dark = try c.decodeIfPresent(Palette.self, forKey: .dark)
        // If id/isBuiltin are present (re-decoding our own encoded output), use them.
        // Otherwise (decoding a fresh .justmd-theme file), generate.
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "user.\(UUID().uuidString)"
        self.isBuiltin = try c.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .schema)
        try c.encode(name, forKey: .name)
        try c.encode(light, forKey: .light)
        try c.encodeIfPresent(dark, forKey: .dark)
        try c.encode(id, forKey: .id)
        try c.encode(isBuiltin, forKey: .isBuiltin)
    }
}
