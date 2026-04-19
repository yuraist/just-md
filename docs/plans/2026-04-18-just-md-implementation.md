# JustMD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS markdown editor (JustMD) with hybrid inline rendering, theme system, and document-based architecture. Ships an MVP per `docs/plans/2026-04-18-just-md-design.md`.

**Architecture:** AppKit `NSDocument` per file. `NSTextView` with custom `NSTextStorage` that incrementally parses markdown and applies attributes. Inline marker visibility driven by caret position. SwiftUI programmatic UI for Welcome and Preferences. Themes are Codable JSON; builtin + user presets; exportable as `.justmd-theme`.

**Tech Stack:** Swift 6.2.3 (Swift 6 mode), Xcode 26.3, macOS 14 deployment target. SPM dependencies: `swift-cmark` (Apple fork with GFM), `Highlightr`. No storyboards beyond the default `MainMenu.xib`.

**Design source of truth:** `docs/plans/2026-04-18-just-md-design.md`

---

## Phase 0: Project bootstrap

> **Status:** ✅ Phase complete (0.1, 0.2, 0.3)

### Task 0.1: Configure build settings ✅

**Files:**
- Modify: `JustMD/JustMD.xcodeproj/project.pbxproj` (via Xcode GUI is fine; these are target settings)

**Step 1:** In Xcode, select target `JustMD` → General:
- Minimum Deployments → macOS: `14.0`
- Identity → Version: `0.1.0`, Build: `1`
- App Category: `Productivity`

**Step 2:** Build Settings:
- `SWIFT_VERSION` → `6.0`
- `SWIFT_STRICT_CONCURRENCY` → `complete`
- `MACOSX_DEPLOYMENT_TARGET` → `14.0`

**Step 3:** Signing & Capabilities (target `JustMD`):
- ✅ Automatically manage signing
- Add Capability → **App Sandbox**
  - File Access → User Selected File: **Read/Write**
- Add Capability → **Hardened Runtime** (if not already on)

**Step 4:** Build the project (`Cmd+B`). Expected: succeeds with no warnings about concurrency/version.

**Step 5:** Commit.

```bash
git add -A
git commit -m "chore: configure Swift 6, macOS 14 target, sandbox entitlements"
```

### Task 0.2: Add SPM dependencies ✅

**Files:**
- Modify: `JustMD/JustMD.xcodeproj` (via Xcode GUI: File → Add Package Dependencies…)

**Step 1:** Add `swift-cmark` — URL: `https://github.com/apple/swift-cmark`, branch `main`. Add products `cmark-gfm` and `cmark-gfm-extensions` to target `JustMD`.

**Step 2:** Add `Highlightr` — URL: `https://github.com/raspu/Highlightr`, "Up to Next Major Version" from `2.2.0`. Add product `Highlightr` to target `JustMD`.

**Step 3:** Build (`Cmd+B`). Expected: both packages resolve and link.

**Step 4:** Quick sanity import — temporarily add to `AppDelegate.swift`:

```swift
import cmark_gfm
import Highlightr
```

Build again. If it compiles, remove the imports from AppDelegate.

**Step 5:** Commit.

```bash
git add -A
git commit -m "chore: add swift-cmark and Highlightr SPM dependencies"
```

### Task 0.3: Create source folder structure ✅

**Files:**
- Create folders (Xcode groups AND on disk): `App`, `Document`, `Editor`, `Welcome`, `Preferences`, `Theme`, `Resources/Themes`

**Step 1:** In Xcode, right-click `JustMD` group → New Group. Create groups: `App`, `Document`, `Editor`, `Welcome`, `Preferences`, `Theme`. Ensure each creates a real folder on disk (use "New Group with Folder" if needed).

**Step 2:** Move `AppDelegate.swift` into `App/` group (drag in Project Navigator; confirm it moves on disk too).

**Step 3:** Build. Expected: succeeds.

**Step 4:** Commit.

```bash
git add -A
git commit -m "chore: scaffold source folder layout"
```

---

## Phase 1: Markdown parser wrapper (TDD)

> **Status:** ✅ Phase complete (1.1 – 1.6). 19 tests green.

### Task 1.1: MarkdownParser basic structure with a failing test ✅

**Files:**
- Create: `JustMD/JustMD/Editor/MarkdownParser.swift`
- Create: `JustMD/JustMDTests/MarkdownParserTests.swift`

**Step 1 — failing test:** Create `MarkdownParserTests.swift` using Swift Testing (`@Test`):

```swift
import Testing
@testable import JustMD

@Suite("MarkdownParser")
struct MarkdownParserTests {
    @Test("parses empty string to empty document")
    func parsesEmpty() {
        let parser = MarkdownParser()
        let doc = parser.parse("")
        #expect(doc.blocks.isEmpty)
    }
}
```

**Step 2 — run test:** `Cmd+U`. Expected: FAIL — `MarkdownParser` undefined.

**Step 3 — minimal implementation:** Create `MarkdownParser.swift`:

```swift
import Foundation
import cmark_gfm
import cmark_gfm_extensions

struct MarkdownDocument {
    let blocks: [Block]
}

enum Block {
    case paragraph(range: NSRange)
    case heading(level: Int, range: NSRange, markerRange: NSRange)
    case codeBlock(language: String?, range: NSRange, contentRange: NSRange, fenceRanges: [NSRange])
    case blockQuote(range: NSRange)
    case list(ordered: Bool, items: [ListItem], range: NSRange)
    case thematicBreak(range: NSRange)
    case table(range: NSRange)
    case html(range: NSRange)
}

struct ListItem {
    let range: NSRange
    let markerRange: NSRange
    let taskState: TaskState?
}

enum TaskState {
    case unchecked
    case checked
}

final class MarkdownParser {
    init() {
        cmark_gfm_core_extensions_ensure_registered()
    }

    func parse(_ source: String) -> MarkdownDocument {
        return MarkdownDocument(blocks: [])
    }
}
```

**Step 4 — test:** `Cmd+U`. Expected: PASS.

**Step 5 — commit:**

```bash
git add -A
git commit -m "feat(parser): bootstrap MarkdownParser with empty parse"
```

### Task 1.2: Parse headings ✅

**Step 1 — failing test:** Append to `MarkdownParserTests`:

```swift
@Test("parses ATX heading levels 1–6")
func parsesHeadings() {
    let parser = MarkdownParser()
    let source = "# H1\n## H2\n###### H6\n"
    let doc = parser.parse(source)
    #expect(doc.blocks.count == 3)

    if case let .heading(level, _, _) = doc.blocks[0] { #expect(level == 1) } else { Issue.record("not heading") }
    if case let .heading(level, _, _) = doc.blocks[1] { #expect(level == 2) } else { Issue.record("not heading") }
    if case let .heading(level, _, _) = doc.blocks[2] { #expect(level == 6) } else { Issue.record("not heading") }
}
```

**Step 2 — run:** Expected FAIL (returns empty).

**Step 3 — implement:** Flesh out `parse()`. Use `cmark_parse_document` with GFM extensions, walk the AST via `cmark_node_first_child` / `cmark_node_next`, and produce `Block` cases. Compute `NSRange` from source offsets via cmark's `cmark_node_get_start_line` + `cmark_node_get_start_column` — convert line/column to byte offsets by scanning the source. (This is the fiddly part; factor byte-offset computation into a helper.)

**Step 4 — run:** Expected PASS.

**Step 5 — commit:**

```bash
git add -A
git commit -m "feat(parser): emit Heading blocks with level and range"
```

### Task 1.3: Parse paragraphs, HR, code blocks ✅

Add three separate small tests + implementation passes, one per block type. Commit after each.

- Paragraphs: `"Hello\n\nWorld"` → 2 paragraph blocks.
- Thematic breaks: `"---\n"` → 1 `.thematicBreak`.
- Fenced code blocks: `"```swift\nlet x = 1\n```"` → 1 `.codeBlock(language: "swift", ...)`. Compute `contentRange` (inner text) and `fenceRanges` (two fence lines).

Commit message per sub-task: `feat(parser): parse X`.

### Task 1.4: Parse lists and task items ✅

- Unordered and ordered lists.
- Task-list GFM extension: `- [ ]` / `- [x]` → `ListItem.taskState` populated.

Commit: `feat(parser): parse lists and task items`.

### Task 1.5: Parse blockquotes, tables, inline HTML ✅

- `> quote` blocks.
- GFM tables (pipe tables).
- Raw HTML blocks.

Commit: `feat(parser): parse quotes, tables, html blocks`.

### Task 1.6: Inline span API ✅

Parsing inline spans (bold, italic, links, inline code, strike, images) is needed by the syntax highlighter. Add a separate method:

```swift
func inlineSpans(in block: Block, source: String) -> [InlineSpan]

enum InlineSpan {
    case bold(range: NSRange, markerRanges: [NSRange])
    case italic(range: NSRange, markerRanges: [NSRange])
    case strike(range: NSRange, markerRanges: [NSRange])
    case inlineCode(range: NSRange, markerRanges: [NSRange])
    case link(range: NSRange, urlRange: NSRange, markerRanges: [NSRange], url: URL?)
    case image(range: NSRange, urlRange: NSRange, url: URL?, alt: String)
}
```

Write focused tests for each span type on representative input. Implement by re-parsing the block's substring and walking cmark inline nodes.

Commit: `feat(parser): expose inline span extraction`.

---

## Phase 2: Theme model (TDD)

### Task 2.1: Palette and Theme Codable

**Files:**
- Create: `JustMD/JustMD/Theme/Palette.swift`
- Create: `JustMD/JustMD/Theme/Theme.swift`
- Create: `JustMD/JustMDTests/ThemeTests.swift`

**Step 1 — failing tests:**

```swift
import Testing
import Foundation
@testable import JustMD

@Suite("Theme codable")
struct ThemeTests {
    @Test("decodes example .justmd-theme JSON")
    func decodes() throws {
        let json = """
        {
          "schema": 1,
          "name": "Nord Focus",
          "author": "yuri",
          "light": {
            "background": "#ECEFF4",
            "text": "#2E3440",
            "accent": "#5E81AC",
            "secondary": "#D8DEE9",
            "codeBackground": "#E5E9F0",
            "selection": "#88C0D0"
          }
        }
        """.data(using: .utf8)!

        let theme = try JSONDecoder().decode(Theme.self, from: json)
        #expect(theme.name == "Nord Focus")
        #expect(theme.light.background == "#ECEFF4")
        #expect(theme.dark == nil)
    }

    @Test("round-trips encode/decode")
    func roundTrip() throws {
        let palette = Palette(background: "#FFFFFF", text: "#000000", accent: "#0066CC", secondary: "#888888", codeBackground: "#F5F5F5", selection: "#B3D4FC")
        let theme = Theme(id: "user.test", name: "T", isBuiltin: false, light: palette, dark: nil)
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded.name == "T")
    }
}
```

**Step 2 — fail:** run tests.

**Step 3 — implement:** `Palette` (all fields `String` hex), `Theme` (id default-generated UUID if missing when decoding). Custom Codable if needed (the `.justmd-theme` file has no `id` field; we generate at import time).

**Step 4 — pass.**

**Step 5 — commit.**

### Task 2.2: Color conversion (hex → NSColor)

**Files:**
- Create: `JustMD/JustMD/Theme/Palette+NSColor.swift`
- Modify test file with conversion tests.

Tests: `"#ECEFF4"` → `NSColor(red: 0.925..., green: 0.937..., blue: 0.957..., alpha: 1.0)` within small epsilon. Round-trip `nsColor.hexString` back to `"#ECEFF4"`.

Commit: `feat(theme): hex <-> NSColor conversion`.

### Task 2.3: Builtin presets embedded resource

**Files:**
- Create: `JustMD/JustMD/Resources/Themes/follow-system.justmd-theme`
- Create: same for `white`, `sepia`, `gray`, `black`
- Create: `JustMD/JustMD/Theme/BuiltinThemes.swift`

Hex values from `docs/plans/2026-04-18-just-md-design.md` §Themes.

**Step 1 — failing test:** `BuiltinThemes.all` returns 5 themes; their ids are `builtin.followSystem`, `builtin.white`, etc.

**Step 2 — implement:** Copy the JSON files into target (Build Phases → Copy Bundle Resources). `BuiltinThemes.all` loads each via `Bundle.main.url(forResource:withExtension:)` and decodes.

**Step 3 — pass.**

Commit: `feat(theme): embed 5 builtin theme presets`.

### Task 2.4: ThemeStore — persistence

**Files:**
- Create: `JustMD/JustMD/Theme/ThemeStore.swift`
- Tests in `ThemeTests.swift`.

Responsibilities:
- Directory: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("JustMD/Themes")`.
- `func loadAll() -> [Theme]` — builtins + user.
- `func save(_ theme: Theme) throws` — writes `<id>.justmd-theme`.
- `func delete(_ theme: Theme) throws`.
- `func importTheme(from url: URL) throws -> Theme` — decodes, assigns fresh `id = "user.<uuid>"`, persists.
- `func exportTheme(_ theme: Theme, to url: URL) throws` — strips `id`, keeps `schema`, `name`, `author`, `light`, `dark?`.

Tests: use a temporary directory (inject via init param). Write, load, delete, import, export. Assert filesystem state.

Commit per sub-step: `feat(theme): ThemeStore <operation>`.

---

## Phase 3: MarkdownDocument (NSDocument)

### Task 3.1: MarkdownDocument skeleton

**Files:**
- Create: `JustMD/JustMD/Document/MarkdownDocument.swift`

```swift
import AppKit

final class MarkdownDocument: NSDocument {
    var text: String = ""

    override class var autosavesInPlace: Bool { true }
    override class var preservesVersions: Bool { true }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        }
        self.text = string
    }

    override func data(ofType typeName: String) throws -> Data {
        return text.data(using: .utf8) ?? Data()
    }

    override func makeWindowControllers() {
        let controller = MarkdownWindowController(document: self)
        self.addWindowController(controller)
    }
}
```

Stub `MarkdownWindowController` (will flesh out later):

**Files:**
- Create: `JustMD/JustMD/Document/MarkdownWindowController.swift`

```swift
import AppKit

final class MarkdownWindowController: NSWindowController {
    init(document: MarkdownDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        self.contentViewController = DocumentViewController(document: document)
    }

    required init?(coder: NSCoder) { fatalError() }
}
```

Stub `DocumentViewController`:

**Files:**
- Create: `JustMD/JustMD/Document/DocumentViewController.swift`

```swift
import AppKit

final class DocumentViewController: NSViewController {
    let document: MarkdownDocument
    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.view = v
    }
}
```

Commit: `feat(doc): scaffold MarkdownDocument, window, view controller`.

### Task 3.2: Info.plist — document types

**Files:**
- Modify: `JustMD/JustMD/Info.plist` (create if missing)
- Modify: target build settings to point at Info.plist or use INFOPLIST_KEY_* entries

**Step 1:** Register document types:

```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key><string>Markdown Document</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>net.daringfireball.markdown</string>
      <string>public.plain-text</string>
    </array>
    <key>NSDocumentClass</key><string>$(PRODUCT_MODULE_NAME).MarkdownDocument</string>
  </dict>
</array>
<key>UTImportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string>
    <key>UTTypeConformsTo</key>
    <array><string>public.plain-text</string></array>
    <key>UTTypeDescription</key><string>Markdown Document</string>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array><string>md</string><string>markdown</string><string>mdown</string><string>mkd</string></array>
    </dict>
  </dict>
</array>
```

**Step 2:** Remove the default `@IBOutlet var window` + initial window creation from `AppDelegate` — `NSDocumentController` will manage windows.

**Step 3:** In `MainMenu.xib`, remove the "Window" dummy if template created one. Keep the menu bar; wire `File → New` to `newDocument:`, `Open…` to `openDocument:`, etc. (these are first-responder actions — Xcode template usually has them already).

**Step 4:** Build and run. Expected:
- Launches to no window (will add Welcome next phase).
- `File → Open…` works and opens a `.md` file in a blank window.

**Step 5 — commit:** `feat(doc): register .md file types and NSDocument class`.

### Task 3.3: Smoke test — open a file manually

**Step 1:** Create a test file `/tmp/test.md` with sample markdown.

**Step 2:** Run app, `File → Open…`, select `/tmp/test.md`. Expect: blank window titled `test.md`.

**Step 3:** Quit without changes (autosave inactive for empty editor yet).

**Step 4:** Also test: in Finder, Right-click `/tmp/test.md` → Open With → JustMD. Expect: opens in JustMD.

No commit needed — just verification.

---

## Phase 4: Text storage + syntax highlighting core

### Task 4.1: MarkdownTextStorage stub

**Files:**
- Create: `JustMD/JustMD/Editor/MarkdownTextStorage.swift`
- Create: `JustMD/JustMDTests/MarkdownTextStorageTests.swift`

**Step 1 — failing test:**

```swift
@Test("storage reports length and string match backing store")
func lengthMatches() {
    let storage = MarkdownTextStorage()
    storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "hello")
    #expect(storage.length == 5)
    #expect(storage.string == "hello")
}
```

**Step 2 — implement minimally:**

```swift
import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
}
```

**Step 3 — pass.**

**Step 4 — commit:** `feat(editor): MarkdownTextStorage backing NSMutableAttributedString`.

### Task 4.2: SyntaxHighlighter — heading attributes

**Files:**
- Create: `JustMD/JustMD/Editor/SyntaxHighlighter.swift`
- Test file.

Define a protocol-free struct:

```swift
struct HighlightContext {
    var baseFont: NSFont
    var textColor: NSColor
    var secondaryColor: NSColor
    var accentColor: NSColor
    var codeFont: NSFont
    var codeBackground: NSColor
}

final class SyntaxHighlighter {
    let parser: MarkdownParser
    init(parser: MarkdownParser) { self.parser = parser }

    func apply(to storage: NSTextStorage, context: HighlightContext) {
        let source = storage.string
        let doc = parser.parse(source)
        // reset attributes
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes([.font: context.baseFont, .foregroundColor: context.textColor], range: full)
        for block in doc.blocks {
            applyBlock(block, source: source, storage: storage, context: context)
        }
    }

    private func applyBlock(_ block: Block, source: String, storage: NSTextStorage, context: HighlightContext) {
        switch block {
        case .heading(let level, let range, let markerRange):
            let size = context.baseFont.pointSize + CGFloat(8 - level) * 2  // H1 biggest
            let font = NSFontManager.shared.convert(context.baseFont.withSize(size), toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: font, range: range)
            storage.addAttribute(MarkdownAttribute.marker, value: true, range: markerRange)
        default:
            break
        }
    }
}

enum MarkdownAttribute {
    static let marker = NSAttributedString.Key("com.justmd.marker")
    static let codeLanguage = NSAttributedString.Key("com.justmd.codeLanguage")
}
```

**Test (non-trivial):** given `"# Hi"`, after `apply`, character at index 0 has `MarkdownAttribute.marker == true` and index 2 has `.font.pointSize` > base. Commit.

Proceed block-by-block (paragraphs are no-op, code blocks → mono, blockquotes → secondary color, hr → separator paragraph style, lists → hanging indent, tables → mono alignment). One sub-commit per block type. Add tests per block.

### Task 4.3: Apply inline spans

Iterate inline spans for each paragraph/heading block and apply:
- bold → bold font
- italic → italic font
- inline code → mono font + codeBackground color
- strike → strikethrough attribute
- links → `.link = URL`, `.foregroundColor = accent`
- bold+italic combinations → resolved by combining traits

Tests per span type. Commits per span type.

### Task 4.4: Wire SyntaxHighlighter into MarkdownTextStorage

Override `processEditing`:

```swift
override func processEditing() {
    super.processEditing()
    highlighter?.apply(to: self, context: context)
}
```

Make it incremental later (see Task 4.5); for now full re-parse on every edit is fine for MVP.

Smoke test: create a test harness in the test file that creates a storage, a text view, types "# Hello", and asserts the heading font is applied. Commit.

### Task 4.5 (optional, defer if slow): Incremental re-parse

Measure parse time on a 50KB document. If < 5ms on M-series, full re-parse is OK for MVP — move on. If slower, add block-level incremental parse using `editedRange` → find enclosing block → re-parse from previous blank line to next.

Commit or skip with a note in the plan.

---

## Phase 5: Code block highlighting

### Task 5.1: CodeBlockHighlighter wrapper

**Files:**
- Create: `JustMD/JustMD/Editor/CodeBlockHighlighter.swift`
- Tests.

Wrap Highlightr:

```swift
import Highlightr

final class CodeBlockHighlighter {
    let engine: Highlightr

    init() {
        self.engine = Highlightr()!
        self.engine.setTheme(to: "github")  // placeholder, overridden from theme
    }

    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        if let lang = language, !lang.isEmpty {
            return engine.highlight(code, as: lang, fastRender: true)
        } else {
            return engine.highlight(code, as: nil, fastRender: true)
        }
    }
}
```

Test: `highlight("let x = 1", language: "swift")` returns non-nil `NSAttributedString` whose `string == "let x = 1"` and whose length has differentiated foreground color ranges.

Commit.

### Task 5.2: Apply code-block highlighting in SyntaxHighlighter

In `applyBlock` for `.codeBlock(let lang, let range, let contentRange, let fenceRanges)`:
1. Run `CodeBlockHighlighter.highlight(source[contentRange], language: lang)`.
2. For each distinct foreground color run in result, apply to `storage` at the corresponding offset.
3. Apply `.backgroundColor = context.codeBackground` to `range`.
4. Mark fence lines with `MarkdownAttribute.marker = true`.

Test: fenced Swift block gets mono font and color runs. Commit.

---

## Phase 6: Inline marker visibility

### Task 6.1: HiddenMarkerLayoutManager

**Files:**
- Create: `JustMD/JustMD/Editor/HiddenMarkerLayoutManager.swift`

```swift
import AppKit

final class HiddenMarkerLayoutManager: NSLayoutManager {
    // Active line range in character space — set by text view on selection change.
    var activeLineRange: NSRange = .init(location: 0, length: 0)

    override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count: Int, font: NSFont, textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key : Any] = [:], in CGContext: CGContext) {
        // Default behavior; hiding is handled via glyph generation + zero advancements.
        super.showCGGlyphs(glyphs, positions: positions, count: count, font: font, textMatrix: textMatrix, attributes: attributes, in: CGContext)
    }

    override func setGlyphs(_ glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange) {
        guard let storage = textStorage else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            return
        }
        let mutableProps = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: glyphRange.length)
        defer { mutableProps.deallocate() }
        for i in 0..<glyphRange.length {
            let charIndex = charIndexes[i]
            var property = props[i]
            let attrs = storage.attributes(at: charIndex, effectiveRange: nil)
            let isMarker = attrs[MarkdownAttribute.marker] as? Bool == true
            let isHeadingHash = attrs[MarkdownAttribute.headingHash] as? Bool == true
            let onActiveLine = NSLocationInRange(charIndex, activeLineRange)
            if isHeadingHash || (isMarker && !onActiveLine) {
                property.insert(.null)  // glyph not drawn, zero advancement
            }
            mutableProps[i] = property
        }
        super.setGlyphs(glyphs, properties: mutableProps, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
    }
}
```

Add `MarkdownAttribute.headingHash` constant.

**Test:** Because this touches layout, the test is a smoke test. Create an `NSTextView` with this layout manager, load a string, set `activeLineRange` to a range outside the first line, call `ensureLayout(for:)`, and measure bounding rect of the first character — it should be zero-width if marker and not on active line. This test is flaky and can be replaced by manual verification.

Commit: `feat(editor): HiddenMarkerLayoutManager collapses markers off active line`.

### Task 6.2: MarkdownTextView

**Files:**
- Create: `JustMD/JustMD/Editor/MarkdownTextView.swift`

```swift
import AppKit

final class MarkdownTextView: NSTextView {

    convenience init(storage: MarkdownTextStorage) {
        let lm = HiddenMarkerLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 720, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        lm.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        self.isRichText = false
        self.usesFindBar = false
        self.allowsUndo = true
        self.isAutomaticLinkDetectionEnabled = false
        self.isAutomaticSpellingCorrectionEnabled = false
        self.isAutomaticQuoteSubstitutionEnabled = false
        self.isAutomaticDashSubstitutionEnabled = false
        self.isAutomaticTextReplacementEnabled = false
    }

    override func didChangeText() {
        super.didChangeText()
        updateActiveLine()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateActiveLine()
    }

    private func updateActiveLine() {
        guard let lm = layoutManager as? HiddenMarkerLayoutManager else { return }
        let caret = selectedRange().location
        let storage = string as NSString
        let line = storage.lineRange(for: NSRange(location: min(caret, storage.length), length: 0))
        if !NSEqualRanges(lm.activeLineRange, line) {
            lm.activeLineRange = line
            lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
            lm.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: storage.length), changeInLength: 0, actualCharacterRange: nil)
            lm.ensureLayout(for: lm.textContainers.first!)
            needsDisplay = true
        }
    }
}
```

Hook into `DocumentViewController`: replace stub `NSView` with a `NSScrollView` containing `MarkdownTextView`. Set its text storage from a `MarkdownTextStorage` initialized with document text. Attach highlighter.

Smoke test: launch app, open a `.md` file with headings, bold, inline code. Verify:
- Headings render bold and larger, hashes invisible.
- Bold text is bold, asterisks hidden when caret elsewhere.
- Move caret onto a bold word — asterisks reappear (dim).

Commit: `feat(editor): MarkdownTextView with active-line marker visibility`.

### Task 6.3: Connect document → view → storage round trip

- Document `read` populates `storage` text.
- Edits in text view propagate to `document.text` (override `textStorage(_:didProcessEditing:range:changeInLength:)` in view controller, set `document.text = storage.string`, call `document.updateChangeCount(.changeDone)`).
- On window close, autosave flushes.

Smoke test: open a file, type, close, reopen → edits persisted.

Commit.

---

## Phase 7: Cmd+B / Cmd+I wrapping

### Task 7.1: MarkdownFormatter (TDD pure logic)

**Files:**
- Create: `JustMD/JustMD/Editor/MarkdownFormatter.swift`
- Tests: `JustMD/JustMDTests/MarkdownFormatterTests.swift`

Pure logic (no NSTextView):

```swift
struct MarkdownFormatter {
    enum Delimiter {
        case bold    // **
        case italic  // *
        var string: String { self == .bold ? "**" : "*" }
    }

    struct WrapResult {
        let newString: String
        let newSelection: NSRange
    }

    static func wrap(source: String, selection: NSRange, delimiter: Delimiter) -> WrapResult
}
```

Tests:

1. Empty selection inserts `****` and places caret between (selection location +2, length 0).
2. Selection `"foo"` becomes `"**foo**"`, new selection covers `"foo"`.
3. Selection already wrapped `"**foo**"` (including delimiters in selection) unwraps to `"foo"`.
4. Selection `"foo"` inside pre-wrapped `"**foo**"` (delimiters outside selection) unwraps to `"foo"` + expands source to remove `**`s, new selection on `"foo"`.
5. Italic variant with single `*` works the same way.

Write each test + implementation increment, commit each.

### Task 7.2: Wire into MarkdownTextView

Override `keyDown` or implement `doCommand(by:)` / bind menu items `toggleBold:` and `toggleItalic:` (inherited from NSResponder).

In `MainMenu.xib` add Format menu items:
- Bold → action `toggleBold:`, key `⌘B`
- Italic → action `toggleItalic:`, key `⌘I`

In `MarkdownTextView`:

```swift
override func toggleBold(_ sender: Any?) {
    applyFormatter(delimiter: .bold)
}
override func toggleItalic(_ sender: Any?) {
    applyFormatter(delimiter: .italic)
}
private func applyFormatter(delimiter: MarkdownFormatter.Delimiter) {
    let result = MarkdownFormatter.wrap(source: string, selection: selectedRange(), delimiter: delimiter)
    if let ts = textStorage {
        ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: result.newString)
    }
    setSelectedRange(result.newSelection)
}
```

(Note: the naive replace-all is lossy; a better implementation applies minimal diffs. For MVP, since documents are often small, naive is fine. Optimize later.)

Smoke test: open file, select word, `Cmd+B` → wrapped; `Cmd+B` again → unwrapped. Commit.

---

## Phase 8: Welcome window

### Task 8.1: WelcomeWindow SwiftUI view

**Files:**
- Create: `JustMD/JustMD/Welcome/WelcomeView.swift`
- Create: `JustMD/JustMD/Welcome/WelcomeWindowController.swift`

SwiftUI `WelcomeView`:

```swift
import SwiftUI

struct WelcomeView: View {
    @State private var recents: [URL] = []
    var onNew: () -> Void
    var onOpen: () -> Void
    var onOpenURL: (URL) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("just.md").font(.system(size: 48, weight: .light, design: .serif))
            HStack(spacing: 16) {
                Button("New", action: onNew)
                Button("Open", action: onOpen)
                DropZoneView(onURL: onOpenURL)
            }
            if !recents.isEmpty {
                RecentList(urls: recents, onSelect: onOpenURL)
            }
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { recents = NSDocumentController.shared.recentDocumentURLs }
    }
}
```

`DropZoneView`: small view using `.onDrop(of: [.fileURL])`.
`RecentList`: `List(urls) { url in ... }` with relative date formatter.

Wrap in `WelcomeWindowController: NSWindowController` that hosts the SwiftUI view via `NSHostingView`.

### Task 8.2: Wire up actions

`onNew` →
```swift
let panel = NSSavePanel()
panel.allowedContentTypes = [.init("net.daringfireball.markdown")!]
panel.nameFieldStringValue = "Untitled.md"
panel.begin { response in
    guard response == .OK, let url = panel.url else { return }
    // write empty file
    try? "".write(to: url, atomically: true, encoding: .utf8)
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _,_,_ in }
}
```

`onOpen` → `NSDocumentController.shared.openDocument(self)` (triggers standard Open panel).

`onOpenURL(url)` → `NSDocumentController.shared.openDocument(withContentsOf: url, display: true)`.

### Task 8.3: AppDelegate — show welcome on empty launch

```swift
func applicationDidFinishLaunching(_ aNotification: Notification) {
    if NSDocumentController.shared.documents.isEmpty {
        WelcomeWindowController.shared.showWindow(self)
    }
}
func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
```

Menu `File → Show Welcome Window ⌃⌘W` → calls `WelcomeWindowController.shared.showWindow(nil)`.

Smoke test: launch with no args → Welcome appears. Double-click `.md` → document window, no Welcome. Commit.

---

## Phase 9: Preferences + theme management

### Task 9.1: PreferencesStore

**Files:**
- Create: `JustMD/JustMD/Preferences/PreferencesStore.swift`
- Tests.

`ObservableObject` wrapping `UserDefaults`:

```swift
final class PreferencesStore: ObservableObject {
    @AppStorage("fontFamily") var fontFamily: FontFamily = .sans
    @AppStorage("fontSize") var fontSize: Double = 16
    @AppStorage("lineHeight") var lineHeight: Double = 1.5
    @AppStorage("readingWidth") var readingWidth: Double = 720
    @AppStorage("themeId") var themeId: String = "builtin.followSystem"
}

enum FontFamily: String, CaseIterable, Identifiable {
    case serif, sans, mono
    var id: String { rawValue }
    var nsFont: NSFont { ... }
}
```

Broadcast via `NotificationCenter` on changes (use `didSet` observers; SwiftUI `@AppStorage` doesn't auto-broadcast to AppKit).

Tests: set values, recreate instance, values persist (via injected UserDefaults suite).

Commit.

### Task 9.2: PreferencesView SwiftUI

**Files:**
- Create: `JustMD/JustMD/Preferences/PreferencesView.swift`
- Create: `JustMD/JustMD/Preferences/PreferencesWindowController.swift`

UI per design doc §Preferences. Bind all controls to `@EnvironmentObject var prefs: PreferencesStore`.

Hook `App → Settings… ⌘,` to show window.

Smoke test: change font size → all open editor windows update live. (This requires the editor window to subscribe to the notification and reapply highlighter context.)

Commit.

### Task 9.3: Manage Themes window

**Files:**
- Create: `JustMD/JustMD/Preferences/ManageThemesView.swift`

List of user themes, `Import…` via `NSOpenPanel` (filter `com.justmd.theme`), `Export…` via `NSSavePanel`, `Duplicate`, `Edit` (open color editor sheet), `Delete`.

Color editor: a form with 6 `ColorPicker` fields per palette (light + optional dark toggle).

Tests: end-to-end via `ThemeStore` in a tmp dir — import file, list, export, delete.

Commit.

### Task 9.4: Register .justmd-theme as document type

Add to Info.plist `UTExportedTypeDeclarations`:

```xml
<dict>
  <key>UTTypeIdentifier</key><string>com.justmd.theme</string>
  <key>UTTypeConformsTo</key>
  <array><string>public.json</string></array>
  <key>UTTypeDescription</key><string>JustMD Theme</string>
  <key>UTTypeTagSpecification</key>
  <dict>
    <key>public.filename-extension</key>
    <array><string>justmd-theme</string></array>
  </dict>
</dict>
```

In `CFBundleDocumentTypes`, add another entry for `com.justmd.theme`. In `AppDelegate.application(_:open:)`, if URL is a theme file, import via `ThemeStore` instead of opening as document.

Smoke test: export a theme, double-click it → alert "Import 'X'?" → confirm → theme appears in Manage Themes list.

Commit.

---

## Phase 10: Final polish

### Task 10.1: Theme applied to editor

Editor window observes `PreferencesStore.themeId` and `NSAppearance` → computes active `Palette` → rebuilds `HighlightContext` → re-applies highlighter.

Smoke test: toggle system Light/Dark → editor swaps palettes.

Commit.

### Task 10.2: Font size / family menu items

Format menu:
- `Font Size: Bigger ⌘+` → `prefs.fontSize += 1`
- `Font Size: Smaller ⌘−` → `prefs.fontSize -= 1` (floor at 10)
- `Font Size: Actual ⌘0` → `prefs.fontSize = 16`
- `Font Family: Serif/Sans/Mono ⌃⌘1/2/3` → sets `prefs.fontFamily`

Commit.

### Task 10.3: Theme picker submenu

Dynamic `View → Theme ▸` submenu populated at open from `BuiltinThemes.all + ThemeStore.loadUser()`. Check-mark current. Click → sets `prefs.themeId`.

Commit.

### Task 10.4: Inline image rendering

In `SyntaxHighlighter`, for each `.image(range, urlRange, url, alt)`:
1. If `url` is a file:// or relative (resolve against `document.fileURL.deletingLastPathComponent()`), load `NSImage`.
2. Create `NSTextAttachment`, set `image`, scale to max width = reading width × 0.9.
3. Replace image markdown with attachment character (`NSAttributedString.attachment`). Mark original range hidden (all-marker).

Smoke test: open a `.md` with `![](./pic.png)` next to a real PNG → image renders inline. Commit.

### Task 10.5: Clickable links via Cmd+click

`NSTextView` has `linkTextAttributes` + `clickableLinks`. Ensure:

```swift
textView.linkTextAttributes = [.foregroundColor: context.accentColor, .underlineStyle: 0]
```

Override `clicked(onLink:at:)` → if Cmd is held, `NSWorkspace.shared.open(url)`. Otherwise, move caret (default).

For Cmd detection, check `NSApp.currentEvent?.modifierFlags.contains(.command)`.

Smoke test. Commit.

### Task 10.6: External file changes (NSFilePresenter)

Hook `MarkdownDocument` as `NSFilePresenter`, implement `presentedItemDidChange` — if not dirty, reload from disk. If dirty, show alert "File changed on disk. Revert?".

Smoke test: open file, edit externally via `echo "new content" > file.md`, observe reload (or prompt).

Commit.

### Task 10.7: Full QA pass

Go through the MVP checklist from `docs/plans/2026-04-18-just-md-design.md` §Scope. For each in-scope item, verify manually. Make a checklist commit message: `chore: MVP QA pass`.

### Task 10.8: Tag v0.1.0

```bash
git tag -a v0.1.0 -m "JustMD MVP"
```

---

## Execution notes

- After each phase, run the full test suite. Expected: all green.
- After each phase, manually smoke-test the phase's feature.
- Do **not** start Phase N+1 before Phase N is verified end-to-end.
- If a UI behavior diverges from the design doc, update the design doc first, then implement.
- Keep commits small; one sub-task = one commit.
