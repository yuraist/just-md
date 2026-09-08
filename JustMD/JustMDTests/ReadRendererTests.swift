import Testing
import AppKit
@testable import JustMD

@Suite("MarkdownReadRenderer")
@MainActor
struct ReadRendererTests {

    private func makeContext() -> HighlightContext {
        HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
    }

    private func render(_ source: String) -> NSAttributedString {
        MarkdownReadRenderer().render(source, context: makeContext())
    }

    @Test("no syntax characters survive rendering")
    func noSyntaxChars() {
        let out = render("# Head\n\nsome **bold** and [link](https://e.co)\n")
        #expect(!out.string.contains("#"))
        #expect(!out.string.contains("**"))
        #expect(!out.string.contains("]("))
        #expect(out.string.contains("Head"))
        #expect(out.string.contains("bold"))
        #expect(out.string.contains("link"))
    }

    @Test("table renders into NSTextTable blocks")
    func tableBlocks() {
        let out = render("| A | B |\n|---|---|\n| 1 | 2 |\n")
        // Inspect the style at each paragraph start: every cell must sit in
        // its own (row, column) table block. (Enumerating attribute runs would
        // coalesce them — NSTextBlock equality ignores grid position.)
        var cells = Set<[Int]>()
        let ns = out.string as NSString
        var loc = 0
        while loc < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if paragraph.length > 0,
               let style = out.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
               let block = style.textBlocks.first as? NSTextTableBlock {
                cells.insert([block.startingRow, block.startingColumn])
            }
            loc = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        }
        #expect(cells.count == 4)  // 2×2 cells, header + body
        #expect(!out.string.contains("|"))
        #expect(!out.string.contains("---"))
    }

    @Test("heading gets a larger bold font")
    func headingFont() {
        let out = render("# Big Title\n")
        let loc = (out.string as NSString).range(of: "Big").location
        let font = out.attribute(.font, at: loc, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > 16)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("links are clickable")
    func linkAttribute() {
        let out = render("go to [site](https://example.com) now\n")
        let loc = (out.string as NSString).range(of: "site").location
        let link = out.attribute(.link, at: loc, effectiveRange: nil)
        #expect(link != nil)
    }

    @Test("bullets and checkboxes replace raw list markers")
    func listGlyphs() {
        let out = render("- plain\n- [ ] open\n- [x] done\n")
        #expect(out.string.contains("•"))
        #expect(out.string.contains("☐"))
        #expect(out.string.contains("☑"))
        #expect(!out.string.contains("- ["))
    }

    @Test("ordered lists number their items")
    func orderedNumbers() {
        let out = render("1. first\n2. second\n")
        #expect(out.string.contains("1."))
        #expect(out.string.contains("2."))
    }

    @Test("code block keeps mono font and background")
    func codeBlock() {
        let out = render("```swift\nlet x = 1\n```\n")
        let loc = (out.string as NSString).range(of: "let x").location
        let font = out.attribute(.font, at: loc, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        #expect(out.attribute(.backgroundColor, at: loc, effectiveRange: nil) != nil)
        #expect(!out.string.contains("```"))
    }

    @Test("strikethrough renders struck text")
    func strike() {
        let out = render("a ~~gone~~ b\n")
        let loc = (out.string as NSString).range(of: "gone").location
        #expect(out.attribute(.strikethroughStyle, at: loc, effectiveRange: nil) != nil)
        #expect(!out.string.contains("~~"))
    }

    /// A 1000×100 PNG next to a temporary "document", so relative image paths
    /// resolve the way they do for a real file on disk.
    private func makeImageFixture() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("read-renderer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 100, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("pic.png"))
        return dir.appendingPathComponent("doc.md")
    }

    @Test("local image inside a table cell loads as an attachment")
    func tableCellImage() throws {
        let doc = try makeImageFixture()
        let out = MarkdownReadRenderer().render(
            "| A | B |\n|---|---|\n| ![](pic.png) | text |\n",
            context: makeContext(), baseURL: doc)
        #expect(out.containsAttachments(in: NSRange(location: 0, length: out.length)))
        #expect(!out.string.contains("pic.png"))
        var widths: [CGFloat] = []
        out.enumerateAttribute(.attachment, in: NSRange(location: 0, length: out.length)) { value, _, _ in
            if let a = value as? NSTextAttachment { widths.append(a.bounds.width) }
        }
        // Two columns: the picture is shrunk to fit its cell, not the page.
        #expect(widths.count == 1)
        #expect(widths.first.map { $0 > 0 && $0 <= 620 / 2 } == true)
    }

    @Test("image-only paragraph keeps its natural line height")
    func imageParagraphLineHeight() throws {
        let doc = try makeImageFixture()
        let out = MarkdownReadRenderer().render(
            "Before\n\n![](pic.png)\n\nAfter\n",
            context: makeContext(), baseURL: doc)
        let range = (out.string as NSString).range(of: "\u{FFFC}")
        #expect(range.location != NSNotFound)
        let style = try #require(out.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.lineHeightMultiple == 1)
        let before = try #require(out.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(before.lineHeightMultiple > 1)
    }

    @Test("unloadable image falls back to dimmed alt text")
    func imagePlaceholder() {
        let out = render("![logo](missing.png)\n")
        #expect(out.string.contains("logo"))
    }

    @Test("offscreen read-mode render produces a bitmap (visual artifact)")
    func readRenderArtifact() throws {
        let demo = """
        # Read Mode

        Body with **bold**, a [link](https://anthropic.com), and `code`.

        | Name | Role | Notes |
        |------|------|-------|
        | Ada  | Engineer | Writes compilers |
        | Lin  | Designer | Draws rectangles |

        - First bullet
        - [x] Done task

        > A wise quote.

        ---

        ```swift
        let x = 1
        ```
        """
        let out = render(demo)

        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 900), textContainer: container)
        view.isEditable = false
        storage.setAttributedString(out)
        layoutManager.ensureLayout(for: container)

        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("justmd-read-render.png")
        try data.write(to: url)
        #expect(data.count > 1000)
    }
}
