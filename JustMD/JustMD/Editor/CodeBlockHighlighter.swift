import AppKit
import Highlightr

/// Wraps `Highlightr` to provide syntax-highlighted `NSAttributedString`s
/// for code blocks. Uses the "github" theme and fast HTML rendering.
///
/// The underlying `Highlightr` instance uses a single `JSContext`; callers
/// should not invoke `highlight` concurrently from multiple threads. In
/// practice this is called from the main-actor text storage edit pipeline.
nonisolated final class CodeBlockHighlighter {
    private let engine: Highlightr

    init() {
        guard let h = Highlightr() else {
            preconditionFailure("Highlightr failed to initialize")
        }
        self.engine = h
        _ = h.setTheme(to: "github")
    }

    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        if let language, !language.isEmpty {
            return engine.highlight(code, as: language, fastRender: true)
        } else {
            return engine.highlight(code, as: nil, fastRender: true)
        }
    }
}
