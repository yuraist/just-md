import Foundation
import cmark_gfm
import cmark_gfm_extensions

nonisolated struct ParsedMarkdown: Sendable {
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

nonisolated enum TaskState: Sendable, Equatable {
    case unchecked
    case checked
}

nonisolated enum InlineSpan: Sendable {
    case bold(range: NSRange, markerRanges: [NSRange])
    case italic(range: NSRange, markerRanges: [NSRange])
    case strike(range: NSRange, markerRanges: [NSRange])
    case inlineCode(range: NSRange, markerRanges: [NSRange])
    case link(range: NSRange, urlRange: NSRange, markerRanges: [NSRange], url: URL?)
    case image(range: NSRange, urlRange: NSRange, url: URL?, alt: String)
}

nonisolated final class MarkdownParser: Sendable {
    private static let extensionsRegistered: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    init() {
        _ = MarkdownParser.extensionsRegistered
    }

    func parse(_ source: String) -> ParsedMarkdown {
        guard !source.isEmpty else {
            return ParsedMarkdown(blocks: [])
        }

        let options = CMARK_OPT_DEFAULT
        guard let parser = cmark_parser_new(options) else {
            return ParsedMarkdown(blocks: [])
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
            return ParsedMarkdown(blocks: [])
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
            case CMARK_NODE_LIST:
                if let block = listBlock(from: node, source: source, offsets: offsets) {
                    blocks.append(block)
                }
            case CMARK_NODE_BLOCK_QUOTE:
                blocks.append(.blockQuote(range: nodeRange(node, source: source, offsets: offsets)))
            case CMARK_NODE_HTML_BLOCK:
                blocks.append(.html(range: nodeRange(node, source: source, offsets: offsets)))
            default:
                if let typeCStr = cmark_node_get_type_string(node),
                   String(cString: typeCStr) == "table" {
                    blocks.append(.table(range: nodeRange(node, source: source, offsets: offsets)))
                }
            }
            child = cmark_node_next(node)
        }

        return ParsedMarkdown(blocks: blocks)
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

    private func listBlock(
        from node: UnsafeMutablePointer<cmark_node>,
        source: String,
        offsets: ByteOffsetTable
    ) -> Block? {
        let listType = cmark_node_get_list_type(node)
        let ordered = (listType == CMARK_ORDERED_LIST)

        var items: [ListItem] = []
        var itemNode = cmark_node_first_child(node)
        while let item = itemNode {
            if cmark_node_get_type(item) == CMARK_NODE_ITEM {
                let itemRange = nodeRange(item, source: source, offsets: offsets)

                // Marker range: from item start to first child's start column.
                let markerRange: NSRange
                if let firstChild = cmark_node_first_child(item) {
                    let itemStartLine = cmark_node_get_start_line(item)
                    let itemStartCol = cmark_node_get_start_column(item)
                    let childStartLine = cmark_node_get_start_line(firstChild)
                    let childStartCol = cmark_node_get_start_column(firstChild)

                    if childStartLine == itemStartLine && childStartCol > itemStartCol {
                        let markerStartByte = offsets.byteOffset(line: itemStartLine, column: itemStartCol)
                        let markerEndByte = offsets.byteOffset(line: childStartLine, column: childStartCol)
                        let markerStartUTF16 = utf16Offset(byteOffset: markerStartByte, in: source)
                        let markerEndUTF16 = utf16Offset(byteOffset: markerEndByte, in: source)
                        markerRange = NSRange(
                            location: markerStartUTF16,
                            length: Swift.max(0, markerEndUTF16 - markerStartUTF16)
                        )
                    } else {
                        markerRange = itemRange
                    }
                } else {
                    markerRange = itemRange
                }

                // Task state: tasklist extension gives us type_string == "tasklist" for task items.
                let taskState: TaskState?
                if let typeCStr = cmark_node_get_type_string(item),
                   String(cString: typeCStr) == "tasklist" {
                    taskState = cmark_gfm_extensions_get_tasklist_item_checked(item) ? .checked : .unchecked
                } else {
                    taskState = nil
                }

                items.append(ListItem(range: itemRange, markerRange: markerRange, taskState: taskState))
            }
            itemNode = cmark_node_next(item)
        }

        let range = nodeRange(node, source: source, offsets: offsets)
        return .list(ordered: ordered, items: items, range: range)
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

    // MARK: - Inline spans

    /// Extracts inline spans (bold, italic, strike, inlineCode, link, image) from a block's
    /// content. Blocks without inline content (code blocks, thematic breaks, tables, html)
    /// return an empty array. Ranges are in the coordinate space of the original `source`.
    func inlineSpans(in block: Block, source: String) -> [InlineSpan] {
        guard let blockRange = inlineRange(of: block), blockRange.length > 0 else {
            return []
        }
        let nsSource = source as NSString
        guard blockRange.location >= 0,
              blockRange.location + blockRange.length <= nsSource.length else {
            return []
        }
        let substring = nsSource.substring(with: blockRange)
        guard !substring.isEmpty else { return [] }

        let options = CMARK_OPT_DEFAULT
        guard let parser = cmark_parser_new(options) else { return [] }
        defer { cmark_parser_free(parser) }

        attachExtension(to: parser, named: "table")
        attachExtension(to: parser, named: "strikethrough")
        attachExtension(to: parser, named: "tasklist")
        attachExtension(to: parser, named: "autolink")

        let subBytes = Array(substring.utf8)
        subBytes.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { cPtr in
                    cmark_parser_feed(parser, cPtr, buffer.count)
                }
            }
        }

        guard let root = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(root) }

        let subOffsets = ByteOffsetTable(source: substring)
        var spans: [InlineSpan] = []

        // Find the first block-level node that can contain inlines (paragraph or heading).
        var blockChild = cmark_node_first_child(root)
        while let blockNode = blockChild {
            let type = cmark_node_get_type(blockNode)
            if type == CMARK_NODE_PARAGRAPH || type == CMARK_NODE_HEADING {
                collectInlineSpans(
                    parent: blockNode,
                    substring: substring,
                    subOffsets: subOffsets,
                    shift: blockRange.location,
                    into: &spans
                )
            }
            blockChild = cmark_node_next(blockNode)
        }

        return spans
    }

    /// Returns the range within `source` whose content should be re-parsed for inline spans,
    /// or nil if the block has no inline content.
    private func inlineRange(of block: Block) -> NSRange? {
        switch block {
        case .paragraph(let range):
            return range
        case .heading(_, let range, _):
            return range
        case .blockQuote(let range):
            return range
        case .codeBlock, .thematicBreak, .table, .html, .list:
            // Code blocks, thematic breaks, tables, html: no inline spans extracted here.
            // Lists: inline spans live inside list items; callers should use paragraph blocks
            //   produced elsewhere. For MVP we skip list-level span extraction.
            return nil
        }
    }

    private func collectInlineSpans(
        parent: UnsafeMutablePointer<cmark_node>,
        substring: String,
        subOffsets: ByteOffsetTable,
        shift: Int,
        into spans: inout [InlineSpan]
    ) {
        var child = cmark_node_first_child(parent)
        while let node = child {
            let type = cmark_node_get_type(node)
            let localRange = nodeRange(node, source: substring, offsets: subOffsets)
            let shifted = NSRange(location: localRange.location + shift, length: localRange.length)

            switch type {
            case CMARK_NODE_STRONG:
                let markers = pairedDelimiterMarkers(range: shifted, in: substring, shift: shift, maxLen: 2)
                spans.append(.bold(range: shifted, markerRanges: markers))
                // Recurse to catch nested spans.
                collectInlineSpans(
                    parent: node, substring: substring, subOffsets: subOffsets, shift: shift, into: &spans
                )
            case CMARK_NODE_EMPH:
                let markers = pairedDelimiterMarkers(range: shifted, in: substring, shift: shift, maxLen: 1)
                spans.append(.italic(range: shifted, markerRanges: markers))
                collectInlineSpans(
                    parent: node, substring: substring, subOffsets: subOffsets, shift: shift, into: &spans
                )
            case CMARK_NODE_CODE:
                // cmark reports the inline code node range as the content only (excluding
                // backticks). Expand outward to include the surrounding backtick runs.
                let expanded = expandInlineCodeRange(content: shifted, in: substring, shift: shift)
                let markers = backtickMarkers(range: expanded, in: substring, shift: shift)
                spans.append(.inlineCode(range: expanded, markerRanges: markers))
            case CMARK_NODE_LINK:
                let (urlRange, markers) = linkMarkersAndUrlRange(range: shifted, in: substring, shift: shift)
                let urlStr = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
                let url = urlStr.isEmpty ? nil : URL(string: urlStr)
                spans.append(.link(range: shifted, urlRange: urlRange, markerRanges: markers, url: url))
                collectInlineSpans(
                    parent: node, substring: substring, subOffsets: subOffsets, shift: shift, into: &spans
                )
            case CMARK_NODE_IMAGE:
                let (urlRange, _) = linkMarkersAndUrlRange(range: shifted, in: substring, shift: shift)
                let urlStr = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
                let url = urlStr.isEmpty ? nil : URL(string: urlStr)
                let alt = imageAltText(node: node)
                spans.append(.image(range: shifted, urlRange: urlRange, url: url, alt: alt))
            default:
                // Strikethrough is a GFM extension; check type_string.
                if let typeCStr = cmark_node_get_type_string(node),
                   String(cString: typeCStr) == "strikethrough" {
                    let markers = pairedDelimiterMarkers(range: shifted, in: substring, shift: shift, maxLen: 2)
                    spans.append(.strike(range: shifted, markerRanges: markers))
                    collectInlineSpans(
                        parent: node, substring: substring, subOffsets: subOffsets, shift: shift, into: &spans
                    )
                }
            }
            child = cmark_node_next(node)
        }
    }

    /// For strong/emph/strike: locate matching opening and closing delimiter runs in the
    /// substring, returning their ranges in the original-source coordinate space.
    /// `maxLen` is the delimiter length (1 for emph, 2 for strong/strike).
    private func pairedDelimiterMarkers(
        range shifted: NSRange,
        in substring: String,
        shift: Int,
        maxLen: Int
    ) -> [NSRange] {
        // Translate shifted back to substring coordinates.
        let localLoc = shifted.location - shift
        let localEnd = localLoc + shifted.length
        let utf16 = Array(substring.utf16)
        guard localLoc >= 0, localEnd <= utf16.count, shifted.length >= maxLen * 2 else {
            return []
        }
        // Opening: first `maxLen` UTF-16 code units.
        let openRange = NSRange(location: shifted.location, length: maxLen)
        // Closing: last `maxLen`.
        let closeRange = NSRange(location: shifted.location + shifted.length - maxLen, length: maxLen)
        return [openRange, closeRange]
    }

    /// cmark emits the content range for inline code (e.g. `let x = 1` for `` `let x = 1` ``).
    /// Expand the range outward symmetrically to include the backtick delimiters.
    private func expandInlineCodeRange(
        content shifted: NSRange,
        in substring: String,
        shift: Int
    ) -> NSRange {
        let utf16 = Array(substring.utf16)
        let backtick: UInt16 = 0x60
        let contentStartLocal = shifted.location - shift
        let contentEndLocal = contentStartLocal + shifted.length

        var openLen = 0
        var i = contentStartLocal - 1
        while i >= 0 && utf16[i] == backtick {
            openLen += 1
            i -= 1
        }
        var closeLen = 0
        var j = contentEndLocal
        while j < utf16.count && utf16[j] == backtick {
            closeLen += 1
            j += 1
        }
        // Use the longer of the two sides to find a consistent delimiter length; pick the min.
        // In practice cmark guarantees the two sides are equal.
        let delimLen = Swift.min(openLen, closeLen)
        guard delimLen > 0 else { return shifted }
        let newLoc = shifted.location - delimLen
        let newLen = shifted.length + delimLen * 2
        return NSRange(location: newLoc, length: newLen)
    }

    /// For inline code: the opening and closing runs of backticks can each be 1+ chars. Scan.
    private func backtickMarkers(
        range shifted: NSRange,
        in substring: String,
        shift: Int
    ) -> [NSRange] {
        let localLoc = shifted.location - shift
        let localEnd = localLoc + shifted.length
        let utf16 = Array(substring.utf16)
        guard localLoc >= 0, localEnd <= utf16.count else { return [] }

        let backtick: UInt16 = 0x60 // `
        var openLen = 0
        var i = localLoc
        while i < localEnd && utf16[i] == backtick {
            openLen += 1
            i += 1
        }
        var closeLen = 0
        var j = localEnd - 1
        while j >= localLoc && utf16[j] == backtick {
            closeLen += 1
            j -= 1
        }
        guard openLen > 0, closeLen > 0, openLen + closeLen <= shifted.length else { return [] }
        let openRange = NSRange(location: shifted.location, length: openLen)
        let closeRange = NSRange(location: shifted.location + shifted.length - closeLen, length: closeLen)
        return [openRange, closeRange]
    }

    /// For links `[text](url)` and images `![alt](url)`: find the `[`, `]`, `(`, `)` markers
    /// and the URL range (inside parentheses).
    private func linkMarkersAndUrlRange(
        range shifted: NSRange,
        in substring: String,
        shift: Int
    ) -> (urlRange: NSRange, markers: [NSRange]) {
        let localLoc = shifted.location - shift
        let localEnd = localLoc + shifted.length
        let utf16 = Array(substring.utf16)
        guard localLoc >= 0, localEnd <= utf16.count, shifted.length >= 4 else {
            return (NSRange(location: shifted.location, length: 0), [])
        }

        let lbracket: UInt16 = 0x5B // [
        let rbracket: UInt16 = 0x5D // ]
        let lparen: UInt16 = 0x28   // (
        let rparen: UInt16 = 0x29   // )

        // Opening `[` — for images it's after `!`; shifted.location points to `!` for images.
        // Find the `[` at or after localLoc.
        var openBracketLocal = -1
        var k = localLoc
        while k < localEnd {
            if utf16[k] == lbracket { openBracketLocal = k; break }
            k += 1
        }

        // Find the `](` pair by scanning from the end: `)` is last, preceded by URL, then `(`, then `]`.
        var closeParenLocal = -1
        if localEnd - 1 >= 0 && localEnd - 1 < utf16.count, utf16[localEnd - 1] == rparen {
            closeParenLocal = localEnd - 1
        }

        // Scan backwards from closeParenLocal to find matching `(` at depth 0.
        var openParenLocal = -1
        if closeParenLocal > 0 {
            var depth = 0
            var i = closeParenLocal - 1
            while i >= localLoc {
                let c = utf16[i]
                if c == rparen { depth += 1 }
                else if c == lparen {
                    if depth == 0 { openParenLocal = i; break }
                    depth -= 1
                }
                i -= 1
            }
        }

        // `]` is the character immediately before `(`.
        var closeBracketLocal = -1
        if openParenLocal > localLoc, utf16[openParenLocal - 1] == rbracket {
            closeBracketLocal = openParenLocal - 1
        }

        guard openBracketLocal >= 0,
              closeBracketLocal > openBracketLocal,
              openParenLocal == closeBracketLocal + 1,
              closeParenLocal > openParenLocal else {
            return (NSRange(location: shifted.location, length: 0), [])
        }

        let urlStart = openParenLocal + 1
        let urlLen = closeParenLocal - urlStart
        let urlRange = NSRange(location: urlStart + shift, length: Swift.max(0, urlLen))

        let markers = [
            NSRange(location: openBracketLocal + shift, length: 1),
            NSRange(location: closeBracketLocal + shift, length: 1),
            NSRange(location: openParenLocal + shift, length: 1),
            NSRange(location: closeParenLocal + shift, length: 1),
        ]
        return (urlRange, markers)
    }

    /// Concatenate text-node content across the image node's children to produce alt text.
    private func imageAltText(node: UnsafeMutablePointer<cmark_node>) -> String {
        var alt = ""
        var child = cmark_node_first_child(node)
        while let c = child {
            if cmark_node_get_type(c) == CMARK_NODE_TEXT {
                if let cstr = cmark_node_get_literal(c) {
                    alt += String(cString: cstr)
                }
            } else {
                // Recurse into nested inline structure (e.g. emph inside alt).
                alt += imageAltText(node: c)
            }
            child = cmark_node_next(c)
        }
        return alt
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
