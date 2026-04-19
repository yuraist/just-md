import Foundation

nonisolated public struct Palette: Codable, Sendable, Equatable {
    public var background: String     // hex, e.g. "#FFFFFF"
    public var text: String
    public var accent: String
    public var secondary: String
    public var codeBackground: String
    public var selection: String

    public init(background: String, text: String, accent: String, secondary: String, codeBackground: String, selection: String) {
        self.background = background
        self.text = text
        self.accent = accent
        self.secondary = secondary
        self.codeBackground = codeBackground
        self.selection = selection
    }
}
