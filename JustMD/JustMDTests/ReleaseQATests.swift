import Testing
import AppKit
@testable import JustMD

/// Regression tests for the issues found during the 1.0 release QA pass
/// (docs/plans/2026-09-07-v1.0-test-plan.md).
@Suite("Release QA regressions")
@MainActor
struct ReleaseQATests {

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

    // MARK: F1 — Read mode horizontal rule lands on its own line

    @Test("read-mode rule is drawn on the rule line, not the following block")
    func readRuleGeometry() throws {
        let rendered = MarkdownReadRenderer().render("Above\n\n---\n\nBelow\n", context: makeContext())
        let storage = NSTextStorage(attributedString: rendered)
        let lm = MarkdownLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        lm.addTextContainer(container)
        lm.ensureLayout(for: container)

        var ruleRange = NSRange(location: 0, length: 0)
        var found = false
        storage.enumerateAttribute(MarkdownAttribute.thematicBreak, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard value as? Bool == true else { return }
            ruleRange = range
            found = true
            stop.pointee = true
        }
        #expect(found)

        let ruleRect = try #require(lm.hiddenLineRect(forCharacterRange: ruleRange))
        let ns = storage.string as NSString
        let belowLoc = ns.range(of: "Below").location
        let belowRect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: belowLoc), effectiveRange: nil)
        let aboveRect = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        #expect(ruleRect.minY > aboveRect.minY)
        #expect(ruleRect.minY < belowRect.minY, "rule rect must sit above the 'Below' paragraph")
    }

    // MARK: F5 — nested list items are styled like top-level ones

    @Test("parser reports nested list items with their own marker ranges")
    func nestedListItems() {
        let source = "- Parent\n  - Child\n    - Grandchild\n"
        let doc = MarkdownParser().parse(source)
        guard case .list(_, let items, _)? = doc.blocks.first else {
            Issue.record("expected a list block")
            return
        }
        let ns = source as NSString
        let markers = items.map { ns.substring(with: $0.markerRange).trimmingCharacters(in: .whitespaces) }
        #expect(items.count == 3)
        #expect(markers == ["-", "-", "-"])
        let lines = items.map { ns.lineRange(for: NSRange(location: $0.markerRange.location, length: 0)).location }
        #expect(lines == [0, ns.range(of: "  - Child").location, ns.range(of: "    - Grandchild").location])
    }

    // MARK: Undo drives the change count

    @Test("typing dirties the document and undo makes it clean again")
    func undoTracksChangeCount() throws {
        let document = MarkdownDocument()
        document.text = "hello\n"
        document.makeWindowControllers()
        let vc = try #require(document.windowControllers.first?.contentViewController as? DocumentViewController)
        _ = vc.view
        let textView = try #require(vc.textView)
        #expect(textView.undoManager === document.undoManager)
        #expect(document.isDocumentEdited == false)

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        // NSDocument bumps its change count when the undo group closes, which
        // the event loop does at the end of the event. A nested runloop spin
        // is not reliable for that inside the test host, so close it by hand.
        func endEvent() {
            let undo = document.undoManager
            while let u = undo, u.groupingLevel > 0 { u.endUndoGrouping() }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        endEvent()
        #expect(document.text == "hello!\n")
        #expect(document.undoManager?.canUndo == true)
        #expect(document.isDocumentEdited == true)

        document.undoManager?.undo()
        endEvent()
        #expect(document.text == "hello\n")
        #expect(document.isDocumentEdited == false, "undoing the only edit must return to clean")
        document.close()
    }

    @Test("nested dashes get the bullet attribute in the editor")
    func nestedBulletsTagged() {
        let storage = MarkdownTextStorage()
        storage.highlighter = SyntaxHighlighter(parser: MarkdownParser())
        storage.highlightContext = makeContext()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- Parent\n  - Child\n")
        storage.applyHighlightingNow()
        let childDash = ("- Parent\n  " as NSString).length
        #expect(storage.attribute(MarkdownAttribute.listBullet, at: childDash, effectiveRange: nil) as? Bool == true)
    }

    // MARK: F6 — nested emphasis markers all hide

    @Test("***bold italic*** tags all six asterisks as markers")
    func nestedEmphasisMarkers() {
        let source = "***bold italic***"
        let spans = MarkdownParser().inlineSpans(forBlockContent: source)
        var covered = Set<Int>()
        for span in spans {
            switch span {
            case .bold(_, let m), .italic(_, let m), .strike(_, let m), .inlineCode(_, let m):
                for r in m { for i in r.location..<NSMaxRange(r) { covered.insert(i) } }
            case .link(_, _, let m, _):
                for r in m { for i in r.location..<NSMaxRange(r) { covered.insert(i) } }
            case .image:
                break
            }
        }
        let len = (source as NSString).length
        #expect(covered.isSuperset(of: [0, 1, 2]), "opening run: \(covered.sorted())")
        #expect(covered.isSuperset(of: [len - 3, len - 2, len - 1]), "closing run: \(covered.sorted())")
    }

    // MARK: F15 — reloading from disk must not dirty the document

    @Test("reload after an external change leaves the document clean")
    func reloadKeepsDocumentClean() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("doc.md")
        try "one\n".write(to: url, atomically: true, encoding: .utf8)

        let document = try MarkdownDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
        let vc = DocumentViewController(document: document)
        _ = vc.view
        #expect(document.isDocumentEdited == false)

        try "two\n".write(to: url, atomically: true, encoding: .utf8)
        try document.revert(toContentsOf: url, ofType: "net.daringfireball.markdown")
        // The reload notification hops the main queue twice; drain it.
        for _ in 0..<3 { await Task.yield(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }

        #expect(vc.textView?.string == "two\n")
        #expect(document.isDocumentEdited == false, "a reload is not a user edit")
    }

    // MARK: F2 — the edited paragraph must stay visible right after an insertion

    @Test("paragraph stays drawn between an insertion and the highlight pass")
    func editedParagraphStaysVisible() throws {
        let storage = MarkdownTextStorage()
        storage.highlighter = SyntaxHighlighter(parser: MarkdownParser())
        storage.highlightContext = makeContext()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Title\n\nSome paragraph text here.\n")
        storage.applyHighlightingNow()
        let view = MarkdownTextView(storage: storage)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        view.backgroundColor = .white
        view.layoutManager?.ensureLayout(for: view.textContainer!)

        func darkPixels(inLineOf location: Int) throws -> Int {
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let lm = try #require(view.layoutManager)
            let glyph = lm.glyphIndexForCharacter(at: location)
            var line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            line.origin.x += view.textContainerOrigin.x
            line.origin.y += view.textContainerOrigin.y
            var count = 0
            let scale = CGFloat(rep.pixelsWide) / view.bounds.width
            for y in stride(from: Int(line.minY * scale), to: Int(line.maxY * scale), by: 1) {
                for x in stride(from: Int(line.minX * scale), to: Int(line.maxX * scale), by: 2) {
                    if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.5 { count += 1 }
                }
            }
            return count
        }

        let paragraphLoc = ("# Title\n\n" as NSString).length
        let before = try darkPixels(inLineOf: paragraphLoc)
        #expect(before > 50)

        let end = ("# Title\n\nSome paragraph text here." as NSString).length
        view.setSelectedRange(NSRange(location: end, length: 0))
        view.insertText("x", replacementRange: NSRange(location: end, length: 0))
        // No runloop spin: this is the state the window can draw before the
        // deferred highlight pass lands.
        let during = try darkPixels(inLineOf: paragraphLoc)
        #expect(during > 50, "paragraph vanished right after the insertion")

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let after = try darkPixels(inLineOf: paragraphLoc)
        #expect(after > 50, "paragraph vanished after the highlight pass")
    }
}

// MARK: - Folder access (sandboxed Read-mode images) and printing

@Suite("Folder access")
@MainActor
struct FolderAccessTests {
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

    @Test("grant link round-trips the folder path")
    func grantLinkRoundTrip() throws {
        let folder = URL(fileURLWithPath: "/Users/someone/Notes/My Project", isDirectory: true)
        let link = try #require(FolderAccess.grantLink(for: folder))
        #expect(link.scheme == FolderAccess.grantScheme)
        #expect(FolderAccess.folder(fromGrantLink: link)?.path == folder.path)
        #expect(FolderAccess.folder(fromGrantLink: URL(string: "https://example.com")!) == nil)
    }

    @Test("unreadable local image offers the folder grant link; remote does not")
    func placeholderCarriesGrantLink() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let local = MarkdownReadRenderer().render("![pic](does-not-exist.png)\n", context: makeContext(), baseURL: base)
        var links: [URL] = []
        local.enumerateAttribute(.link, in: NSRange(location: 0, length: local.length)) { value, _, _ in
            if let url = value as? URL { links.append(url) }
        }
        #expect(links.contains(where: { $0.scheme == FolderAccess.grantScheme }))
        #expect(local.string.contains("Allow access to folder"))

        let remote = MarkdownReadRenderer().render("![pic](https://example.com/a.png)\n", context: makeContext(), baseURL: base)
        #expect(!remote.string.contains("Allow access to folder"))
    }

    @Test("a stored grant makes the folder readable and a sibling image render")
    func storedGrantLoadsSiblingImage() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("grant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("pic.png"))

        let suite = "test.\(UUID().uuidString)"
        let access = FolderAccess(defaults: UserDefaults(suiteName: suite)!)
        #expect(access.store(grantFor: dir))
        #expect(access.activateGrant(for: dir))
        #expect(access.activateGrant(for: dir.appendingPathComponent("sub", isDirectory: true)))

        let out = MarkdownReadRenderer().render("![pic](pic.png)\n", context: makeContext(), baseURL: dir)
        var hasAttachment = false
        out.enumerateAttribute(.attachment, in: NSRange(location: 0, length: out.length)) { value, _, _ in
            if value is NSTextAttachment { hasAttachment = true }
        }
        #expect(hasAttachment, "image next to the document should render inline")
    }
}

@Suite("Printing")
@MainActor
struct PrintingTests {
    @Test("Print… produces an operation over a laid-out rendered view")
    func printOperation() throws {
        let document = MarkdownDocument()
        document.text = "# Title\n\nSome **text**.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n"
        let operation = try document.printOperation(withSettings: [:])
        let view = try #require(operation.view as? NSTextView)
        #expect(view.frame.height > 40)
        #expect(view.string.contains("Title"))
        #expect(!view.string.contains("#"))
        #expect(view.frame.width <= operation.printInfo.imageablePageBounds.width + 1)
    }
}
