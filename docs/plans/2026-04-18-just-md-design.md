# JustMD — Design Document

**Date:** 2026-04-18
**Status:** Approved, ready for implementation planning

## Vision

A native macOS markdown editor. Open a `.md` file, see it rendered with hidden syntax markers, write more text. No file browser, no cloud, no sync, no tabs, no sidebars. Like Microsoft Word, but for markdown and minimalist — inspired by Bear, iA Writer, Medium.

## Principles

- **Native first.** AppKit document-based architecture. SwiftUI only where it's clearly simpler (Welcome + Preferences). No WebView.
- **Maximum minimalism.** Blank canvas. No navigation chrome in document windows. Settings stay minimal.
- **No file management.** One file per window. Never browse, never sync, never organize.
- **UX and performance over boilerplate.** We accept more code for nativefeel and responsiveness.

## Scope (MVP)

**In:**
- Open `.md` / `.markdown` / `.mdown` / `.mkd` (double-click, drag to app icon, File → Open).
- Multi-window: one `NSDocument` per file.
- Welcome window at launch (New / Open / Drop zone / Recent files).
- Hybrid inline editing: markdown syntax markers hidden on inactive lines, dimmed on active line (Bear-style). Heading hashes always hidden.
- GFM (GitHub Flavored Markdown): headings, bold, italic, strike, lists, task lists, blockquotes, links, inline code, fenced code blocks with language syntax highlighting, HR, tables, images.
- Inline local images (via `NSTextAttachment`).
- Clickable links (Cmd+click opens in browser).
- Autosave (1–2 second debounce, via `NSDocument` autosavesInPlace).
- Preferences: font family (Serif / Sans / Mono), font size, line height, reading width.
- Themes: 5 builtin presets + user custom presets with colorpicker.
- Theme export/import as `.justmd-theme` JSON files.
- Follows system Light/Dark by default (`Follow System` is default theme).
- `Cmd+B` / `Cmd+I` to wrap selection in `**…**` / `*…*`.
- Recent Files (via `NSDocumentController`).

**Out (explicitly deferred):**
- Word / char / line counter.
- Find & Replace.
- Export to PDF / HTML.
- Outline / TOC sidebar.
- Mermaid diagrams, math (LaTeX/KaTeX).
- Plugins / extensions.
- Split view, preview-only mode.
- Cloud sync.

## Architecture

### Tech stack

- **Language:** Swift 6.2.3, Swift 6 language mode (strict concurrency).
- **Toolchain:** Xcode 26.3, SDK macOS 26.2.
- **Deployment target:** macOS 14.0 (Sonoma). Supports 14 / 15 / 26+.
- **UI:** AppKit (programmatic, no `.xib`) for document windows. SwiftUI (programmatic, no storyboards) for Welcome and Preferences.
- **Dependencies (SPM):**
  - `swift-cmark` (Apple) — CommonMark + GFM parsing.
  - `Highlightr` — syntax highlighting for fenced code blocks.

### Module layout

```
JustMD/
├── App/
│   ├── JustMDApp.swift              // @main
│   └── AppDelegate.swift            // NSApplicationDelegate, welcome window handling
├── Document/
│   ├── MarkdownDocument.swift       // NSDocument subclass
│   └── MarkdownWindowController.swift
├── Editor/
│   ├── MarkdownTextView.swift       // NSTextView subclass (Cmd+B/I, link handling)
│   ├── MarkdownTextStorage.swift    // NSTextStorage subclass, incremental re-parse
│   ├── MarkdownParser.swift         // swift-cmark wrapper
│   ├── SyntaxHighlighter.swift      // applies NSAttributedString attributes
│   ├── InlineRenderer.swift         // caret-aware marker visibility
│   └── CodeBlockHighlighter.swift   // Highlightr wrapper
├── Welcome/
│   └── WelcomeWindow.swift          // SwiftUI in NSWindow
├── Preferences/
│   ├── PreferencesWindow.swift      // SwiftUI in NSWindow
│   ├── ThemeStore.swift             // builtin + user presets
│   └── Theme.swift                  // Codable
└── Resources/
    └── Themes/                      // embedded .justmd-theme files
```

### Document lifecycle

- `MarkdownDocument: NSDocument` with `autosavesInPlace = true`, `preservesVersions = true`.
- `read(from:ofType:)` reads UTF-8, normalizes line endings to LF, remembers original line endings for write-back.
- `data(ofType:)` serializes back, restoring original line endings.
- `NSFilePresenter` subscribes to external file changes (Git pull, external editor) and reloads the buffer. If there are unsaved local edits, show revert dialog (rare thanks to short autosave debounce).

### File type registration (Info.plist)

- `CFBundleDocumentTypes`: `.md`, `.markdown`, `.mdown`, `.mkd`. Conform to `public.plain-text` and custom `com.justmd.markdown`.
- `NSDocumentClass = MarkdownDocument`.
- Role: `Editor`.
- `LSHandlerRank = Alternate` (don't steal default handler from system; user opts in via Finder → Get Info).

## Editor: hybrid inline rendering

The text buffer always stores **raw markdown**. Rendering is a **visual overlay** — attributes, attachments, hidden ranges.

### `MarkdownTextStorage`

- Conforms to `NSTextStorage`.
- On each edit: compute `editedRange` + `changeInLength`, re-parse only affected blocks (cmark gives block-level AST: paragraph, heading, code block, list item).
- After re-parse, call `SyntaxHighlighter.apply(ast:to:range:)`.

### `SyntaxHighlighter`

Applies `NSAttributedString` attributes to the storage:

| Element | Visual treatment | Markers |
|---|---|---|
| `# Heading 1…6` | Font larger + bold, hierarchical sizes | Hashes marked `.markdownMarker = true` (always hidden) |
| `**bold**` | Bold font variant | `**` marked as marker |
| `*italic*` | Italic font variant | `*` marked as marker |
| `~~strike~~` | Strikethrough attribute | `~~` marked as marker |
| `` `inline code` `` | Mono font + subtle background | Backticks marked as marker |
| `[text](url)` | `.link` attribute + accent color | URL part + brackets dimmed, marked as marker |
| Lists `- / 1.` | Standard text + hanging indent | Marker visible (it's already minimal) |
| `> quote` | Left border via paragraph style, secondary text color | `>` visible |
| Fenced code block | Mono font, code background color, Highlightr tokens | Fence `` ``` `` lines marked as marker |
| `---` HR | Rendered as thin separator line via `NSParagraphStyle` | The dashes marked as marker |
| Tables | Monospace alignment, subtle borders via paragraph style | Pipes `|` and `---` visible (structural) |
| `![](local.png)` | Replaced by `NSTextAttachment` with `NSImage` | Entire markdown hidden; attachment rendered |
| Task list `- [x]` | Checkbox glyph | Brackets marked as marker |

### `InlineRenderer` — marker visibility

- Subscribes to `NSTextViewDelegate.textViewDidChangeSelection`.
- Computes **active line** = line containing the caret (or intersecting selection).
- For every range attributed as `.markdownMarker = true`:
  - On active line → `.foregroundColor` = theme's `secondary` (dim, visible).
  - Off active line → applied via a custom `NSLayoutManager` that collapses hidden glyphs to zero width.
  - Heading hashes: always hidden regardless of active line (Bear-style).
- No animation on active-line change — animation distracts while typing.

### Cmd+B / Cmd+I

`MarkdownTextView` overrides command handlers:

- **Cmd+B:** wrap selection in `**…**`. Empty selection → insert `****` and place caret between.
- **Cmd+I:** same with `*…*`.
- If the selection is already wrapped in the same delimiter, toggle (unwrap).

### Performance

- Incremental re-parse at block level scales to hundreds of thousands of characters.
- `NSTextView` uses TextKit 2 (default on macOS 14+) — lazy layout, efficient for large docs.
- Undo/redo via `NSTextStorage` + `undoManager` — native.
- Spellcheck, dictation, Services, emoji picker — free from `NSTextView`.

## Welcome window

Appears on fresh launch (no files opened) or via `File → Show Welcome` (`⌃⌘W`). Not shown automatically when the last document window closes.

Layout (SwiftUI, programmatic):

```
┌─────────────────────────────────────┐
│                                     │
│            just.md                  │   wordmark, large
│                                     │
│   ┌──────┐  ┌──────┐  ┌──────┐      │
│   │ New  │  │ Open │  │ Drop │      │
│   └──────┘  └──────┘  └──────┘      │
│                                     │
│   Recent                            │
│   • notes.md         2 min ago      │
│   • article.md       yesterday      │
│   • ideas.md         last week      │
│                                     │
└─────────────────────────────────────┘
```

- **New** → `NSSavePanel` → on confirm, `NSDocumentController.newDocument` at path → autosave active immediately. On cancel, nothing happens.
- **Open** → `NSOpenPanel` filtered to `.md` / `.markdown` / `.mdown` / `.mkd`.
- **Drop** — whole window accepts `.md` drag-and-drop.
- **Recent** — from `NSDocumentController.recentDocumentURLs`.

Closing the Welcome window does not quit the app: `NSApplication.terminateAfterLastWindowClosed = false`.

## Preferences

Single-pane SwiftUI window:

```
Appearance
  Theme:          [Follow System ▾]
  Custom themes:  [Manage Presets…]

Typography
  Font family:    ( ) Serif   (•) Sans   ( ) Mono
  Size:           [ 16 ]  ◂━━●━━━▸  12–24
  Line height:    [1.5]   ◂━●━━━━━▸  1.2–2.0

Editor
  Reading width:  [ 720 ] pt
```

Changes broadcast via `NotificationCenter.default.post(name: .justMDPreferencesDidChange)`; open document windows subscribe and re-render live.

Persistence: `UserDefaults` (`suiteName` = app bundle id).

### Default fonts

- Serif: **New York** (system)
- Sans: **SF Pro** (system)
- Mono: **SF Mono** (system)

## Themes

### Model

```swift
struct Theme: Codable, Identifiable {
    let id: String             // "builtin.white" or "user.<uuid>"
    var name: String
    var isBuiltin: Bool
    var light: Palette         // required
    var dark: Palette?         // optional — if nil, light is used in dark mode too
}

struct Palette: Codable {
    var background: String     // hex
    var text: String
    var accent: String         // links, active heading hint
    var secondary: String      // markers on active line, metadata
    var codeBackground: String
    var selection: String
}
```

### Resolution rules

- `Follow System` (builtin) picks `light` or `dark` based on `NSAppearance.current`.
- A user theme without `dark` uses `light` in both appearance modes.
- A user theme with `dark` respects system mode.

### Builtin presets

1. **Follow System** (default) — `#FFFFFF / #1A1A1A` light, `#1A1A1A / #E5E5E5` dark.
2. **White** — pure white, always.
3. **Sepia** — `#F4ECD8 / #5B4636`, always.
4. **Gray** — `#EDEDED / #2A2A2A`, always.
5. **Black** — `#0A0A0A / #E5E5E5`, always.

### `.justmd-theme` file format

Plain JSON, schema versioned. Font settings intentionally not included — shareable color-only presets, so a recipient without the author's custom font still sees sane typography.

```json
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
  },
  "dark": {
    "background": "#2E3440",
    "text": "#ECEFF4",
    "accent": "#88C0D0",
    "secondary": "#4C566A",
    "codeBackground": "#3B4252",
    "selection": "#5E81AC"
  }
}
```

- Extension: `.justmd-theme`, UTI `com.justmd.theme`.
- Double-click → `NSDocumentController` handler shows alert: "Import theme 'Nord Focus'?" → writes to `~/Library/Application Support/JustMD/Themes/<uuid>.justmd-theme`.
- **Manage Presets…** window: list of user themes with `Import…`, `Export…`, `Duplicate`, `Edit` (colorpickers for each palette field), `Delete`.

## Menus and shortcuts

```
JustMD
  About JustMD
  Settings…                    ⌘,
  Services ▸
  Hide / Quit                  ⌘H / ⌘Q

File
  New                          ⌘N
  Open…                        ⌘O
  Open Recent ▸
  Close                        ⌘W
  Revert To ▸
  Show Welcome Window          ⌃⌘W

Edit
  Undo / Redo / Cut / Copy / Paste / Select All
  Paste and Match Style        ⇧⌥⌘V

Format
  Bold                         ⌘B
  Italic                       ⌘I
  ──
  Font Size: Bigger            ⌘+
  Font Size: Smaller           ⌘−
  Font Size: Actual            ⌘0
  ──
  Font Family: Serif           ⌃⌘1
  Font Family: Sans            ⌃⌘2
  Font Family: Mono            ⌃⌘3

View
  Theme ▸                      (presets + user themes, flat list)
  Enter Full Screen            ⌃⌘F

Window
  Minimize / Zoom / Tile / Bring All to Front

Help
  JustMD Help
```

No markdown-insertion commands in the menu beyond Bold/Italic — the user types syntax by hand; that's part of the philosophy.

## Packaging

- Xcode project, Swift 6.2.3, Swift 6 language mode.
- Hardened Runtime: on.
- App Sandbox: on. Entitlement `com.apple.security.files.user-selected.read-write` — document-based apps get file access automatically through `NSOpenPanel` / `NSSavePanel`. Apps outside MAS can drop sandbox if it causes friction; for now, keep it on.
- Code signing + notarization for distribution outside MAS.
- App icon: placeholder for MVP.

## Out-of-scope (deferred, for reference)

- Word / char / line counter in window footer.
- Find & Replace.
- Export to PDF / HTML.
- Outline / TOC sidebar.
- Mermaid, KaTeX.
- Plugins.
- Split view, preview-only mode.
- Any cloud sync or file browser.

## Open questions deferred to implementation

- Which exact hidden-text mechanism in `NSLayoutManager` survives TextKit 2 reliably — needs a spike. Fallback: `NSAttributedString.Key("NSHidden")` + custom layout manager override.
- Exact autosave debounce (1s vs 2s) — tune during implementation.
- Whether user themes panel needs side-by-side light/dark preview — decide after building basic Edit UI.
