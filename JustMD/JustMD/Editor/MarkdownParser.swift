import Foundation
import cmark_gfm
import cmark_gfm_extensions

nonisolated struct MarkdownDocument: Sendable {
    let blocks: [Block]
}

nonisolated enum Block: Sendable {
    case paragraph(range: NSRange)
    case heading(level: Int, range: NSRange, markerRange: NSRange)
    case codeBlock(language: String?, range: NSRange, contentRange: NSRange, fenceRanges: [NSRange])
    case blockQuote(range: NSRange)
    case list(ordered: Bool, items: [ListItem], range: NSRange)
    case thematicBreak(range: NSRange)
    case table(range: NSRange)
    case html(range: NSRange)
}

nonisolated struct ListItem: Sendable {
    let range: NSRange
    let markerRange: NSRange
    let taskState: TaskState?
}

nonisolated enum TaskState: Sendable {
    case unchecked
    case checked
}

nonisolated final class MarkdownParser: Sendable {
    private static let extensionsRegistered: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    init() {
        _ = MarkdownParser.extensionsRegistered
    }

    func parse(_ source: String) -> MarkdownDocument {
        return MarkdownDocument(blocks: [])
    }
}
