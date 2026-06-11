# Known Issues

Updated 2026-06-11 after the editor rework (see `docs/plans/2026-06-11-editor-rework.md`).

## Resolved in the rework

- **6-A Hybrid inline hide** — markers now fully hide off the active paragraph via
  `NSLayoutManagerDelegate.shouldGenerateGlyphs` + `.null` glyph properties
  (`MarkerVisibilityController`). Caret reveals them dimmed. No garbled glyphs —
  guarded by `MarkerHidingLayoutTests`.
- **6-B Typing latency** — incremental restyling (`BlockDiff` window), per-block
  inline-span cache, O(line) byte→UTF-16 mapping, cached/async Highlightr, and
  next-runloop-pass scheduling replaced the 200 ms debounce + full-document pass.
  Guarded by `HighlightPipelineTests.largeDocIncremental`.
- **6-C Visual completeness** — lists (accent bullets + hanging indent), task
  lists (tinted), HR (drawn rule), blockquote (accent bar, hidden `>`), tables
  (dimmed pipes in editor; real `NSTextTable` grid in Read mode).
- **Cmd+B/Cmd+I** — the template Format menu in MainMenu.xib was swallowing the
  shortcuts into `NSFontManager.addFontTrait:`; removed. Formatter edits now go
  through the undo stack and trim whitespace/newlines from selections.
- **App Store blockers** — app icon generated and installed; sandbox + hardened
  runtime + category + copyright + encryption-exemption all set.

## Open

### Inline images in the editor

`![alt](path)` shows as dimmed raw markdown in Edit mode. Read mode renders
local images inline (`NSTextAttachment`) when the path is readable; remote
URLs and paths outside the sandbox grant fall back to dimmed alt text.

**Next step:** async download/cache for remote images in Read mode; editor-mode
inline rendering still needs a character-substitution mechanism (TextKit 2
custom fragment or display-string mapping).

### Slow window resize on large documents

TextKit 1 reflows the whole attributed text on container-width changes. Not
affected by the highlighting rework (no re-parse on resize), but still visible
on ~100KB+ files.

**Approaches:** TextKit 2 migration; defer reflow during live resize.

### Table editing ergonomics

Editor mode shows raw pipes (dimmed, mono). No auto-formatting of column
widths, no Tab-to-next-cell. Read mode renders the true grid.

### IME / marked-text styling

The per-keystroke restyle pass touches the edited paragraph while composition
(Japanese/Korean input) is active. Not observed to break composition, but
marked-text edge cases are untested.
