import AppKit
import Highlightr

@MainActor
final class CodeBlockHighlighter {
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
