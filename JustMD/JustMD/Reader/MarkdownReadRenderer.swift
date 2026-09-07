import AppKit
import cmark_gfm
import cmark_gfm_extensions

/// Renders markdown into a fully formatted, display-only attributed string for
/// Read mode: real table grids (`NSTextTable`), bullets, checkboxes, clickable
/// links, inline images — no syntax characters at all. The editor keeps the
/// raw source; this renderer owns the "viewer" half of the app.
@MainActor
final class MarkdownReadRenderer {

    private let codeHighlighter: CodeBlockHighlighter?

    init(codeHighlighter: CodeBlockHighlighter? = nil) {
        self.codeHighlighter = codeHighlighter
    }

    // MARK: - Entry point

    func render(_ source: String, context: HighlightContext, baseURL: URL? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        guard !source.isEmpty else { return result }
        lineHeightMultiple = max(1.05, context.lineHeightMultiple)

        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return result }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "tasklist", "autolink"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        let bytes = Array(source.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { cPtr in
                    cmark_parser_feed(parser, cPtr, buffer.count)
                }
            }
        }
        guard let root = cmark_parser_finish(parser) else { return result }
        defer { cmark_node_free(root) }

        var child = cmark_node_first_child(root)
        while let node = child {
            appendBlock(node, to: result, context: context, baseURL: baseURL, listDepth: 0)
            child = cmark_node_next(node)
        }
        return result
    }

    // MARK: - Blocks

    private func appendBlock(
        _ node: UnsafeMutablePointer<cmark_node>,
        to out: NSMutableAttributedString,
        context: HighlightContext,
        baseURL: URL?,
        listDepth: Int
    ) {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_HEADING:
            let level = Int(cmark_node_get_heading_level(node))
            let size = context.baseFont.pointSize + CGFloat(max(0, 8 - level)) * 2
            let resized = NSFont(descriptor: context.baseFont.fontDescriptor, size: size) ?? context.baseFont
            let headingFont = font(resized, addingTraits: .bold)
            let text = inlineText(of: node, context: context, baseURL: baseURL,
                                  state: InlineState(font: headingFont))
            let style = blockStyle()
            style.paragraphSpacingBefore = level <= 2 ? 14 : 10
            append(text, style: style, to: out)

        case CMARK_NODE_PARAGRAPH:
            let text = inlineText(of: node, context: context, baseURL: baseURL,
                                  state: InlineState(font: context.baseFont))
            append(text, style: blockStyle(), to: out)

        case CMARK_NODE_CODE_BLOCK:
            appendCodeBlock(node, to: out, context: context)

        case CMARK_NODE_BLOCK_QUOTE:
            let start = out.length
            var child = cmark_node_first_child(node)
            while let inner = child {
                appendBlock(inner, to: out, context: context, baseURL: baseURL, listDepth: listDepth)
                child = cmark_node_next(inner)
            }
            let range = NSRange(location: start, length: out.length - start)
            guard range.length > 0 else { break }
            out.addAttribute(.foregroundColor, value: context.secondaryColor, range: range)
            out.addAttribute(MarkdownAttribute.blockQuote, value: true, range: range)
            out.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
                let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? self.blockStyle()
                style.firstLineHeadIndent += 16
                style.headIndent += 16
                out.addAttribute(.paragraphStyle, value: style, range: subRange)
            }

        case CMARK_NODE_LIST:
            appendList(node, to: out, context: context, baseURL: baseURL, listDepth: listDepth)

        case CMARK_NODE_THEMATIC_BREAK:
            let style = blockStyle()
            style.paragraphSpacingBefore = 8
            // The rule attribute stops before the newline: the layout manager
            // anchors the rule on the character right after the tagged range,
            // which must be this line's own newline — tagging it too would
            // push the rule onto the next block's first line.
            let rule = NSMutableAttributedString(
                string: "\u{00A0}",
                attributes: [
                    .font: context.baseFont,
                    MarkdownAttribute.thematicBreak: true,
                    .paragraphStyle: style,
                ]
            )
            rule.append(NSAttributedString(string: "\n", attributes: [.font: context.baseFont, .paragraphStyle: style]))
            out.append(rule)

        case CMARK_NODE_HTML_BLOCK:
            if let literal = cmark_node_get_literal(node) {
                let text = NSMutableAttributedString(
                    string: String(cString: literal),
                    attributes: [.font: context.codeFont, .foregroundColor: context.secondaryColor]
                )
                append(text, style: blockStyle(), to: out)
            }

        default:
            if let typeCStr = cmark_node_get_type_string(node), String(cString: typeCStr) == "table" {
                appendTable(node, to: out, context: context)
            }
        }
    }

    private func appendCodeBlock(
        _ node: UnsafeMutablePointer<cmark_node>,
        to out: NSMutableAttributedString,
        context: HighlightContext
    ) {
        guard let literal = cmark_node_get_literal(node) else { return }
        var code = String(cString: literal)
        if code.hasSuffix("\n") { code.removeLast() }
        let language: String? = cmark_node_get_fence_info(node).flatMap {
            let s = String(cString: $0)
            return s.isEmpty ? nil : s
        }

        let attributed: NSMutableAttributedString
        // No language → plain text; Highlightr's auto-detection misfires on
        // short or prose-like blocks.
        if let codeHighlighter, let language,
           let highlighted = codeHighlighter.cachedHighlight(code, language: language)
            ?? codeHighlighter.highlight(code, language: language),
           highlighted.length == (code as NSString).length {
            attributed = NSMutableAttributedString(attributedString: highlighted)
            attributed.addAttribute(.font, value: context.codeFont,
                                    range: NSRange(location: 0, length: attributed.length))
        } else {
            attributed = NSMutableAttributedString(
                string: code,
                attributes: [.font: context.codeFont, .foregroundColor: context.textColor]
            )
        }
        attributed.append(NSAttributedString(string: "\n", attributes: [.font: context.codeFont]))
        let full = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.backgroundColor, value: context.codeBackground, range: full)
        let style = blockStyle()
        style.lineHeightMultiple = context.codeLineHeightMultiple
        style.paragraphSpacing = 0
        style.firstLineHeadIndent = 6
        style.headIndent = 6
        append(attributed, style: style, to: out, overrideStyle: true)
        // The background band fills the paragraph spacing too, so a plain
        // spacer line separates consecutive blocks (and the next paragraph).
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 6),
            .paragraphStyle: blockStyle(),
        ]))
    }

    private var lineHeightMultiple: CGFloat = 1.05

    private func appendList(
        _ node: UnsafeMutablePointer<cmark_node>,
        to out: NSMutableAttributedString,
        context: HighlightContext,
        baseURL: URL?,
        listDepth: Int
    ) {
        let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
        let startNumber = Int(cmark_node_get_list_start(node))
        let baseIndent = CGFloat(listDepth) * 24

        var index = 0
        var itemNode = cmark_node_first_child(node)
        while let item = itemNode {
            defer { itemNode = cmark_node_next(item); index += 1 }
            guard cmark_node_get_type(item) == CMARK_NODE_ITEM else { continue }

            let prefix: String
            var prefixColor = context.accentColor
            if let typeCStr = cmark_node_get_type_string(item), String(cString: typeCStr) == "tasklist" {
                let checked = cmark_gfm_extensions_get_tasklist_item_checked(item)
                prefix = checked ? "☑ " : "☐ "
            } else if ordered {
                prefix = "\(max(startNumber, 1) + index).  "
            } else {
                prefix = "•  "
                prefixColor = context.secondaryColor
            }
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: context.baseFont]).width

            var innerChild = cmark_node_first_child(item)
            var firstParagraph = true
            // An empty item still produces a line for the bullet.
            if innerChild == nil {
                let line = NSMutableAttributedString(
                    string: prefix + "\n",
                    attributes: [.font: context.baseFont, .foregroundColor: prefixColor]
                )
                let style = blockStyle()
                style.firstLineHeadIndent = baseIndent
                style.headIndent = baseIndent + prefixWidth
                append(line, style: style, to: out, overrideStyle: true)
            }
            while let inner = innerChild {
                defer { innerChild = cmark_node_next(inner) }
                let type = cmark_node_get_type(inner)
                if type == CMARK_NODE_LIST {
                    appendList(inner, to: out, context: context, baseURL: baseURL, listDepth: listDepth + 1)
                    continue
                }
                if type == CMARK_NODE_PARAGRAPH {
                    let text = inlineText(of: inner, context: context, baseURL: baseURL,
                                          state: InlineState(font: context.baseFont))
                    let line = NSMutableAttributedString()
                    if firstParagraph {
                        line.append(NSAttributedString(
                            string: prefix,
                            attributes: [.font: context.baseFont, .foregroundColor: prefixColor]
                        ))
                    }
                    line.append(text)
                    let style = blockStyle()
                    style.paragraphSpacing = 2
                    style.firstLineHeadIndent = firstParagraph ? baseIndent : baseIndent + prefixWidth
                    style.headIndent = baseIndent + prefixWidth
                    append(line, style: style, to: out, overrideStyle: true)
                    firstParagraph = false
                } else {
                    appendBlock(inner, to: out, context: context, baseURL: baseURL, listDepth: listDepth + 1)
                }
            }
        }
        // Restore normal spacing after the tight list.
        if out.length > 0 {
            out.enumerateAttribute(.paragraphStyle, in: NSRange(location: out.length - 1, length: 1), options: []) { value, range, _ in
                if let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                    style.paragraphSpacing = 8
                    out.addAttribute(.paragraphStyle, value: style, range: range)
                }
            }
        }
    }

    // MARK: - Tables

    private func appendTable(
        _ node: UnsafeMutablePointer<cmark_node>,
        to out: NSMutableAttributedString,
        context: HighlightContext
    ) {
        let columns = Int(cmark_gfm_extensions_get_table_columns(node))
        guard columns > 0 else { return }

        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.setContentWidth(100, type: .percentageValueType)

        let borderColor = context.secondaryColor.withAlphaComponent(0.35)
        var rowIndex = 0
        var rowNode = cmark_node_first_child(node)
        while let row = rowNode {
            defer { rowNode = cmark_node_next(row) }
            // cmark-gfm names the header row "table_header"; body rows are
            // "table_row".
            guard let typeCStr = cmark_node_get_type_string(row),
                  ["table_row", "table_header"].contains(String(cString: typeCStr)) else { continue }
            let isHeader = String(cString: typeCStr) == "table_header"
                || cmark_gfm_extensions_get_table_row_is_header(row) != 0

            var columnIndex = 0
            var cellNode = cmark_node_first_child(row)
            while let cell = cellNode, columnIndex < columns {
                defer { cellNode = cmark_node_next(cell); columnIndex += 1 }

                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: columnIndex,
                    columnSpan: 1
                )
                block.setBorderColor(borderColor)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                if isHeader {
                    block.backgroundColor = context.codeBackground.withAlphaComponent(0.6)
                }

                let cellFont = isHeader ? font(context.baseFont, addingTraits: .bold) : context.baseFont
                let content = inlineText(of: cell, context: context, baseURL: nil,
                                         state: InlineState(font: cellFont))
                let cellText = NSMutableAttributedString(attributedString: content)
                if cellText.length == 0 {
                    cellText.append(NSAttributedString(
                        string: "\u{00A0}",
                        attributes: [.font: cellFont, .foregroundColor: context.textColor]
                    ))
                }
                cellText.append(NSAttributedString(string: "\n", attributes: [.font: cellFont]))

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                let full = NSRange(location: 0, length: cellText.length)
                cellText.addAttribute(.paragraphStyle, value: style, range: full)
                // NSAttributedString coalesces adjacent runs whose attributes
                // compare equal, and NSTextTableBlock equality is blind to the
                // grid position — without a per-cell discriminator, every cell
                // in a row would collapse onto the first cell's block.
                cellText.addAttribute(
                    NSAttributedString.Key("com.justmd.tableCell"),
                    value: rowIndex * 1024 + columnIndex,
                    range: full
                )
                out.append(cellText)
            }
            rowIndex += 1
        }
        // Space below the table.
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 6),
            .paragraphStyle: blockStyle(),
        ]))
    }

    // MARK: - Inlines

    private struct InlineState {
        var font: NSFont
        var color: NSColor?
        var strike = false
        var code = false
        var link: URL?
    }

    private func inlineText(
        of parent: UnsafeMutablePointer<cmark_node>,
        context: HighlightContext,
        baseURL: URL?,
        state: InlineState
    ) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        var child = cmark_node_first_child(parent)
        while let node = child {
            defer { child = cmark_node_next(node) }
            switch cmark_node_get_type(node) {
            case CMARK_NODE_TEXT:
                if let literal = cmark_node_get_literal(node) {
                    out.append(text(String(cString: literal), state: state, context: context))
                }
            case CMARK_NODE_SOFTBREAK:
                out.append(text(" ", state: state, context: context))
            case CMARK_NODE_LINEBREAK:
                out.append(text("\u{2028}", state: state, context: context))
            case CMARK_NODE_EMPH:
                var s = state
                s.font = font(s.font, addingTraits: .italic)
                out.append(inlineText(of: node, context: context, baseURL: baseURL, state: s))
            case CMARK_NODE_STRONG:
                var s = state
                s.font = font(s.font, addingTraits: .bold)
                out.append(inlineText(of: node, context: context, baseURL: baseURL, state: s))
            case CMARK_NODE_CODE:
                if let literal = cmark_node_get_literal(node) {
                    var s = state
                    s.code = true
                    out.append(text(String(cString: literal), state: s, context: context))
                }
            case CMARK_NODE_LINK:
                var s = state
                if let urlCStr = cmark_node_get_url(node) {
                    s.link = URL(string: String(cString: urlCStr), relativeTo: baseURL)
                }
                s.color = context.accentColor
                out.append(inlineText(of: node, context: context, baseURL: baseURL, state: s))
            case CMARK_NODE_IMAGE:
                out.append(image(node, context: context, baseURL: baseURL, state: state))
            case CMARK_NODE_HTML_INLINE:
                if let literal = cmark_node_get_literal(node) {
                    var s = state
                    s.code = true
                    s.color = context.secondaryColor
                    out.append(text(String(cString: literal), state: s, context: context))
                }
            default:
                if let typeCStr = cmark_node_get_type_string(node),
                   String(cString: typeCStr) == "strikethrough" {
                    var s = state
                    s.strike = true
                    out.append(inlineText(of: node, context: context, baseURL: baseURL, state: s))
                }
            }
        }
        return out
    }

    private func text(_ string: String, state: InlineState, context: HighlightContext) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [:]
        if state.code {
            let size = state.font.pointSize
            attrs[.font] = NSFont(descriptor: context.codeFont.fontDescriptor, size: max(10, size * 0.92))
                ?? context.codeFont
            attrs[.backgroundColor] = context.codeBackground
        } else {
            attrs[.font] = state.font
        }
        attrs[.foregroundColor] = state.color ?? context.textColor
        if state.strike {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = state.link {
            attrs[.link] = link
            attrs[.foregroundColor] = context.accentColor
        }
        return NSAttributedString(string: string, attributes: attrs)
    }

    private func image(
        _ node: UnsafeMutablePointer<cmark_node>,
        context: HighlightContext,
        baseURL: URL?,
        state: InlineState
    ) -> NSAttributedString {
        let urlString = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
        var alt = ""
        var child = cmark_node_first_child(node)
        while let c = child {
            if cmark_node_get_type(c) == CMARK_NODE_TEXT, let literal = cmark_node_get_literal(c) {
                alt += String(cString: literal)
            }
            child = cmark_node_next(c)
        }

        if !urlString.isEmpty,
           let url = URL(string: urlString, relativeTo: baseURL),
           url.isFileURL,
           let nsImage = NSImage(contentsOf: url) {
            let attachment = NSTextAttachment()
            attachment.image = nsImage
            let maxWidth: CGFloat = 620
            let size = nsImage.size
            if size.width > maxWidth, size.width > 0 {
                let scale = maxWidth / size.width
                attachment.bounds = NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            }
            return NSAttributedString(attachment: attachment)
        }
        // Unloadable image (remote, missing, or outside the sandbox grant):
        // show the alt text as a dimmed placeholder.
        var s = state
        s.color = context.secondaryColor
        let label = alt.isEmpty ? urlString : alt
        let placeholder = NSMutableAttributedString(attributedString: text("🖼 \(label)", state: s, context: context))
        // A local image next to a saved document is most likely readable
        // once the user allows its folder — offer that inline.
        if !urlString.isEmpty, baseURL != nil,
           let url = URL(string: urlString, relativeTo: baseURL), url.isFileURL,
           let grant = FolderAccess.grantLink(for: url.deletingLastPathComponent()) {
            var link = state
            link.link = grant
            placeholder.append(text("  ", state: s, context: context))
            placeholder.append(text("Allow access to folder…", state: link, context: context))
        }
        return placeholder
    }

    // MARK: - Helpers

    private func blockStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8
        style.lineHeightMultiple = lineHeightMultiple
        return style
    }

    /// Appends `text` (already carrying inline attributes) and stamps the block
    /// paragraph style + trailing newline. `overrideStyle` forces `style` even
    /// where the text already has one (lists manage their own indents).
    private func append(
        _ text: NSMutableAttributedString,
        style: NSMutableParagraphStyle,
        to out: NSMutableAttributedString,
        overrideStyle: Bool = false
    ) {
        guard text.length > 0 else { return }
        if !text.string.hasSuffix("\n") {
            let lastAttrs = text.attributes(at: text.length - 1, effectiveRange: nil)
            text.append(NSAttributedString(string: "\n", attributes: lastAttrs))
        }
        let full = NSRange(location: 0, length: text.length)
        if overrideStyle {
            text.addAttribute(.paragraphStyle, value: style, range: full)
        } else {
            text.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, range, _ in
                if value == nil {
                    text.addAttribute(.paragraphStyle, value: style, range: range)
                }
            }
        }
        out.append(text)
    }

    private func font(_ base: NSFont, addingTraits adding: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let combined = base.fontDescriptor.symbolicTraits.union(adding)
        let descriptor = base.fontDescriptor.withSymbolicTraits(combined)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }
}
