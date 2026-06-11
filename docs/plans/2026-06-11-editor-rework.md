# Editor Rework Implementation Plan

> **Status: COMPLETE (2026-06-11).** All tasks landed; 113 tests green; Release build verified. Remaining follow-ups tracked in `docs/known-issues.md`.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make typing instant, fix Cmd+B/Cmd+I, hide markdown syntax Bear-style, render links/tables/HR/lists properly, add a Read mode, and remove App Store blockers (sandbox, icon).

**Architecture:** Keep TextKit 1 + `MarkdownTextStorage` attribute pipeline. Performance comes from (a) per-block inline-span caching, (b) O(line) byte→UTF-16 mapping, (c) incremental attribute application via block-list diffing, (d) async+cached Highlightr, (e) immediate (next-tick) re-highlight instead of 200 ms debounce. Marker hiding via `NSLayoutManagerDelegate.shouldGenerateGlyphs` with `.null` glyph properties, active-paragraph reveal. Read mode is a separate display-only `NSAttributedString` renderer (cmark AST → attributed string with `NSTextTable` for tables).

**Tech Stack:** Swift 6, AppKit/TextKit 1, cmark-gfm (swift-cmark), Highlightr.

---

## Root causes (Phase 1 findings)

1. **Cmd+B/I broken:** `MainMenu.xib` still contains the Xcode template `Format → Font → Bold/Italic` items (⌘B/⌘I → `addFontTrait:` → NSFontManager). `AppDelegate.installFormatMenu()` sees a menu titled "Format" and bails — custom `toggleBold`/`toggleItalic` are never installed. In a plain-text NSTextView `addFontTrait:` restyles the *entire* text; the debounced highlighter then wipes it. Also `applyFormatter` bypasses `shouldChangeText`/`didChangeText` → broken undo.
2. **Latency:** every keystroke (after 200 ms debounce) does: full cmark parse + a *second* cmark parse per block (`inlineSpans`) + O(doc) UTF-8→UTF-16 conversion per range + synchronous Highlightr (JSContext) per code block on main + `setAttributes` over the whole document (full relayout).
3. **Not App Store ready:** no entitlements file (no sandbox), empty `AppIcon.appiconset`, no `LSApplicationCategoryType`.

## Tasks

### Task 1: Fix Cmd+B/Cmd+I dispatch + undo + selection normalization
- Modify: `JustMD/JustMD/Base.lproj/MainMenu.xib` — delete the template "Format" menu item entirely.
- Modify: `MarkdownTextView.applyFormatter` — wrap the edit in `shouldChangeText(in:replacementString:)` / `didChangeText()` so undo works.
- Modify: `MarkdownFormatter.wrap` — before wrapping, shrink the selection to exclude leading/trailing whitespace+newlines (triple-click selections include the trailing `\n`, producing `**para\n**` which cmark rejects). Unwrap checks run on the trimmed range.
- Tests: `MarkdownFormatterTests` — selection with trailing newline/space wraps the trimmed range; round-trip toggle returns original string.

### Task 2: Fast byte↔UTF-16 mapping
- Modify: `MarkdownParser.swift` `ByteOffsetTable` — precompute per-line UTF-16 start offsets in the same O(n) pass; add `utf16Offset(forByte:)` that binary-searches the line then walks only within the line; ASCII fast-path (utf8.count == utf16.count → identity). Replace all `utf16Offset(byteOffset:in:)` call sites.
- Tests: mapping correctness with emoji/Cyrillic multi-byte content.

### Task 3: Inline-span caching
- Modify: `MarkdownParser.inlineSpans` → split into pure `inlineSpans(forBlockContent:)` returning block-relative spans; add an LRU-ish dictionary cache keyed by block substring; shift cached spans by block location at apply time.
- Tests: cache hit returns identical spans; differing content misses.

### Task 4: Incremental highlight application
- Modify: `SyntaxHighlighter.apply` — accept `previousBlocks` + edit delta; compute changed-block window (prefix/suffix match on (type, range adjusted by delta)); reset base attributes and re-apply block+inline attributes only on the changed window. Fall back to full apply on first run / theme change.
- Modify: `MarkdownTextStorage` — track accumulated edited range + delta between highlight passes; pass to highlighter; store last block list.
- Tests: editing one paragraph leaves attribute fingerprints of distant blocks untouched; typing ``` re-applies below (structure change).

### Task 5: Async + cached code-block highlighting
- Modify: `CodeBlockHighlighter` — content+language hash → NSAttributedString cache; `highlightAsync` on a dedicated serial queue, completion on main re-validates content hash before applying token colors.
- Tests: cache behavior; async completion applies only when content unchanged.

### Task 6: Immediate re-highlight + typing attributes
- Modify: `MarkdownTextStorage` — replace 200 ms debounce with next-runloop-tick scheduling (coalesced).
- Modify: `MarkdownTextView.typingAttributes` — inherit neighbor attributes but sanitize (strip marker dimming color and inline-code background at span edges) instead of forcing base font (kills the heading/code style "pop").

### Task 7: Bear-style marker hiding
- Create: `JustMD/JustMD/Editor/MarkerVisibilityController.swift` — `NSLayoutManagerDelegate` implementing `layoutManager(_:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)`: chars carrying `MarkdownAttribute.marker` whose paragraph does not intersect the active selection get `.null` glyph property. Exposes `activeRange` (caret/selection paragraphs); invalidates glyphs+layout for old/new active paragraphs on selection change.
- Modify: `MarkdownTextView` — wire delegate, update `activeRange` in `setSelectedRange`/`selectionDidChange`.
- Tables keep pipes visible (dim) — hiding only applies to inline/heading/fence/link/image/HR markers.
- Tests: pure helper that classifies char indexes hide/dim given attributes + active range.

### Task 8: Visual completeness in editor
- `SyntaxHighlighter`: list hanging indent (paragraph style; indent = measured marker width), task checkbox coloring, table pipe/separator dimming (tag as marker but exempt from hiding), HR tagged with custom attribute.
- Create: drawing of HR separator line + blockquote accent bar in a `NSLayoutManager` subclass `drawBackground` override.
- Tests: paragraph-style and attribute application.

### Task 9: Read mode (viewer)
- Create: `JustMD/JustMD/Reader/MarkdownReadRenderer.swift` — cmark AST → display NSAttributedString: headings, emphasis, code (Highlightr cached), lists/task lists (bullets, ☑), blockquote, links (clickable, single-click opens), HR, images (best-effort load relative to doc URL), **tables via NSTextTable** (header bold + hairline borders).
- Modify: `DocumentViewController` — second read-only TextKit-1 NSTextView swapped in/out; re-render on switch + doc reload + preferences change.
- Modify: `AppDelegate` — View menu "Toggle Edit/Read" ⌘⇧E; window toolbar segmented control.
- Tests: renderer emits NSTextTable blocks for table markdown; link attributes present; heading fonts sized.

### Task 10: App Store readiness
- Create: `JustMD/JustMD/JustMD.entitlements` — app-sandbox + user-selected read-write.
- Modify: `project.pbxproj` — `CODE_SIGN_ENTITLEMENTS`, `ENABLE_HARDENED_RUNTIME = YES`.
- Info.plist: `LSApplicationCategoryType = public.app-category.productivity`, `ITSAppUsesNonExemptEncryption = false`.
- Generate app icon (gemini-image MCP), fill all appiconset slots via sips.
- Verify Release build succeeds.

### Task 11: Verification + docs
- Full test suite green; launch app on a fixture file with headings/links/table/code; screenshot smoke check; update `docs/known-issues.md` and README.
