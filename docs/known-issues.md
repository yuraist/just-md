# Known Issues

Updated 2026-09-07 after the 1.0 release QA pass: launch/document flows,
editor rendering, Read mode, preferences/themes, menus, dark mode, edge-case
files (empty, no trailing newline, CRLF, 120 KB), and App Store binary
settings were checked live; the regressions found are pinned by
`JustMDTests/ReleaseQATests.swift`.

## Resolved in the QA pass (2026-09-07)

- **Read-mode rule misplaced** — the `---` rule drew through the first line
  of the following block. The rule attribute no longer spans the newline.
- **Edited paragraph flashed blank** — after an insertion the paragraph could
  disappear until the next event: the highlight pass invalidated glyphs and
  layout but never display. `invalidateDisplay` added on both paths.
- **Nested lists rendered raw** — the parser only walked top-level items;
  nested items now get bullets, checkboxes and hanging indents.
- **`***bold italic***` kept its inner asterisks** — cmark-gfm reports the
  nested node with its parent's source range; the child range is inset by
  the parent delimiters before marker lookup.
- **Line height and Reading width preferences were inert** — wired to the
  editor, Read mode and printing. Reading width centers the text column.
- **Reload from disk dirtied the document** and every edit called
  `updateChangeCount` (undo could never return to clean). Change counting is
  now driven by the document's undo manager only.
- **Read mode** — consecutive code blocks merged into one band; language-less
  blocks got Highlightr's auto-detected colors; links kept the previous
  theme's accent after a theme change.
- **Welcome window** — Recent list never refreshed; the window stayed open
  behind a freshly opened document; it appeared on top of restored windows
  at launch; its New… save panel was a floating panel instead of a sheet.
- **Menus** — dead `Show Sidebar`, `Customize Toolbar…` and `JustMD Help`
  items removed; Edit → Find uses the inline find bar; the Preferences
  window is titled "Settings" and sized to its content; document windows
  cascade.
- **New** — File → Print… (and Save as PDF via the print dialog) prints the
  rendered document; Read mode offers "Allow access to folder…" so images
  next to a document can load under the sandbox.
- **Found while shooting the App Store assets (2026-09-07)** — printing was
  refused in the sandboxed build ("This application does not support
  printing"): the `com.apple.security.print` entitlement was off
  (`ENABLE_RESOURCE_ACCESS_PRINTING`), and File → Print… now sends
  `printDocument:`. Read mode: images inside table cells never loaded (no
  base URL) and are now scaled to the column; an image-only paragraph no
  longer gets the line-height multiple (blank band above pictures); the
  folder grant is asked for the document's folder, so an image in a
  subfolder loads on later launches too. Covered by `ReadRendererTests`,
  `FolderAccessTests`, `PrintingTests`.

## Resolved in the 2026-06 rework

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

## Open (none block 1.0)

### Inline images in the editor

`![alt](path)` shows as dimmed raw markdown in Edit mode. Read mode renders
local images inline once the document's folder is allowed (the placeholder
offers the grant); remote URLs fall back to dimmed alt text.

**Next step:** async download/cache for remote images in Read mode; editor-mode
inline rendering still needs a character-substitution mechanism (TextKit 2
custom fragment or display-string mapping).

### Hidden fence lines keep their height

A fenced code block's opening and closing fence lines are hidden off the
active paragraph but still occupy a (code-height) line each, so a code block
reads with a blank line above and below. Collapsing them needs per-line
height control that attribute styling can't express in TextKit 1.

### Indented (4-space) code blocks

Rendered as plain indented text in both modes; only fenced blocks get the
code font, background and token colors.

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

### External change while edited

When the file changes on disk and the document has unsaved edits, the
"File changed on disk" alert offers Revert / Keep. With autosave-in-place the
document counts as edited until ⌘S, so the alert also appears after edits
that autosave already wrote. Harmless, but could be smarter (compare
contents before asking).
