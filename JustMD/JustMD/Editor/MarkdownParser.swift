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
        guard !source.isEmpty else {
            return MarkdownDocument(blocks: [])
        }

        let options = CMARK_OPT_DEFAULT
        guard let parser = cmark_parser_new(options) else {
            return MarkdownDocument(blocks: [])
        }
        defer { cmark_parser_free(parser) }

        attachExtension(to: parser, named: "table")
        attachExtension(to: parser, named: "strikethrough")
        attachExtension(to: parser, named: "tasklist")
        attachExtension(to: parser, named: "autolink")

        let sourceBytes = Array(source.utf8)
        sourceBytes.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { cPtr in
                    cmark_parser_feed(parser, cPtr, buffer.count)
                }
            }
        }

        guard let root = cmark_parser_finish(parser) else {
            return MarkdownDocument(blocks: [])
        }
        defer { cmark_node_free(root) }

        let offsets = ByteOffsetTable(source: source)
        var blocks: [Block] = []

        var child = cmark_node_first_child(root)
        while let node = child {
            switch cmark_node_get_type(node) {
            case CMARK_NODE_HEADING:
                if let block = headingBlock(from: node, source: source, offsets: offsets) {
                    blocks.append(block)
                }
            case CMARK_NODE_PARAGRAPH:
                if let block = paragraphBlock(from: node, source: source, offsets: offsets) {
                    blocks.append(block)
                }
            case CMARK_NODE_THEMATIC_BREAK:
                if let block = thematicBreakBlock(from: node, source: source, offsets: offsets) {
                    blocks.append(block)
                }
            case CMARK_NODE_CODE_BLOCK:
                if let block = codeBlock(from: node, source: source, offsets: offsets) {
                    blocks.append(block)
                }
            default:
                break
            }
            child = cmark_node_next(node)
        }

        return MarkdownDocument(blocks: blocks)
    }

    private func attachExtension(to parser: UnsafeMutablePointer<cmark_parser>, named name: String) {
        guard let ext = cmark_find_syntax_extension(name) else { return }
        cmark_parser_attach_syntax_extension(parser, ext)
    }

    nonisolated private func nodeRange(
        _ node: UnsafeMutablePointer<cmark_node>,
        source: String,
        offsets: ByteOffsetTable
    ) -> NSRange {
        let startLine = cmark_node_get_start_line(node)
        let startCol = cmark_node_get_start_column(node)
        let endLine = cmark_node_get_end_line(node)
        let endCol = cmark_node_get_end_column(node)
        let startByte = offsets.byteOffset(line: startLine, column: startCol)
        // end_column is inclusive (1-based last byte), so +1 for half-open length.
        let endByte = offsets.byteOffset(line: endLine, column: endCol) + 1
        let startUTF16 = utf16Offset(byteOffset: startByte, in: source)
        let endUTF16 = utf16Offset(byteOffset: endByte, in: source)
        return NSRange(location: startUTF16, length: Swift.max(0, endUTF16 - startUTF16))
    }

    private func headingBlock(
        from node: UnsafeMutablePointer<cmark_node>,
        source: String,
        offsets: ByteOffsetTable
    ) -> Block? {
        let level = Int(cmark_node_get_heading_level(node))
        guard level >= 1 else { return nil }

        let range = nodeRange(node, source: source, offsets: offsets)

        // Marker: the hashes plus single trailing space (for non-empty ATX headings).
        let markerLength = level + 1
        let markerRange = NSRange(location: range.location, length: markerLength)

        return .heading(level: level, range: range, markerRange: markerRange)
    }

    private func paragraphBlock(
        from node: UnsafeMutablePointer<cmark_node>,
        source: String,
        offsets: ByteOffsetTable
    ) -> Block? {
        let range = nodeRange(node, source: source, offsets: offsets)
        return .paragraph(range: range)
    }

    private func thematicBreakBlock(
        from node: UnsafeMutablePointer<cmark_node>,
        source: String,
        offsets: ByteOffsetTable
    ) -> Block? {
        let range = nodeRange(node, source: source, offsets: offsets)
        return .thematicBreak(range: range)
    }

    /// Emits a `.codeBlock` only for fenced code blocks. Indented code blocks
    /// are currently skipped (MVP); fenceRanges would be empty otherwise.
    private func codeBlock(
        from node: UnsafeMutablePointer<cmark_node>,
        source: String,
        offsets: ByteOffsetTable
    ) -> Block? {
        var fenceLength: Int32 = 0
        var fenceOffset: Int32 = 0
        var fenceChar: CChar = 0
        let isFenced = cmark_node_get_fenced(node, &fenceLength, &fenceOffset, &fenceChar) != 0
        guard isFenced else { return nil }

        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))

        // Overall block range: opening-fence line start through closing-fence line end (excluding trailing \n).
        let openFenceRange = lineRangeExcludingNewline(line: startLine, in: source, table: offsets)
        let closeFenceRange = startLine == endLine
            ? openFenceRange
            : lineRangeExcludingNewline(line: endLine, in: source, table: offsets)
        let overallStart = openFenceRange.location
        let overallEnd = closeFenceRange.location + closeFenceRange.length
        let range = NSRange(location: overallStart, length: Swift.max(0, overallEnd - overallStart))

        // Content range: text between the two fence lines.
        let contentRange: NSRange
        if endLine <= startLine + 1 {
            // No inner content line; zero-length range at end of opening fence.
            let loc = openFenceRange.location + openFenceRange.length
            contentRange = NSRange(location: loc, length: 0)
        } else {
            let firstContent = lineRangeExcludingNewline(line: startLine + 1, in: source, table: offsets)
            let lastContent = lineRangeExcludingNewline(line: endLine - 1, in: source, table: offsets)
            let contentStart = firstContent.location
            let contentEnd = lastContent.location + lastContent.length
            contentRange = NSRange(location: contentStart, length: Swift.max(0, contentEnd - contentStart))
        }

        // Language from fence info string (empty -> nil).
        let language: String?
        if let cstr = cmark_node_get_fence_info(node) {
            let str = String(cString: cstr)
            language = str.isEmpty ? nil : str
        } else {
            language = nil
        }

        let fenceRanges: [NSRange] = startLine == endLine ? [openFenceRange] : [openFenceRange, closeFenceRange]

        return .codeBlock(language: language, range: range, contentRange: contentRange, fenceRanges: fenceRanges)
    }

    nonisolated private func lineRangeExcludingNewline(line: Int, in source: String, table: ByteOffsetTable) -> NSRange {
        // line is 1-based
        let lineIdx = line - 1
        guard lineIdx >= 0 && lineIdx < table.lineStarts.count else {
            return NSRange(location: source.utf16.count, length: 0)
        }
        let startByte = table.lineStarts[lineIdx]
        let endByte = lineIdx + 1 < table.lineStarts.count
            ? table.lineStarts[lineIdx + 1] - 1   // exclude the \n
            : table.totalBytes
        let startUTF16 = utf16Offset(byteOffset: startByte, in: source)
        let endUTF16 = utf16Offset(byteOffset: endByte, in: source)
        return NSRange(location: startUTF16, length: Swift.max(0, endUTF16 - startUTF16))
    }
}

nonisolated private struct ByteOffsetTable {
    let lineStarts: [Int]   // index = line-1; UTF-8 byte offset of line start
    let totalBytes: Int

    init(source: String) {
        let bytes = Array(source.utf8)
        var starts = [0]
        for (i, b) in bytes.enumerated() where b == 0x0A {
            starts.append(i + 1)
        }
        self.lineStarts = starts
        self.totalBytes = bytes.count
    }

    func byteOffset(line: Int32, column: Int32) -> Int {
        let lineIdx = Int(line) - 1
        guard lineIdx >= 0 && lineIdx < lineStarts.count else { return totalBytes }
        return lineStarts[lineIdx] + Int(column) - 1
    }
}

/// UTF-8 byte offset -> UTF-16 offset.
nonisolated private func utf16Offset(byteOffset: Int, in source: String) -> Int {
    let utf8 = source.utf8
    let clamped = Swift.max(0, Swift.min(byteOffset, utf8.count))
    let utf8Idx = utf8.index(utf8.startIndex, offsetBy: clamped)
    guard let strIdx = String.Index(utf8Idx, within: source) else { return source.utf16.count }
    return source.utf16.distance(from: source.utf16.startIndex, to: strIdx)
}
