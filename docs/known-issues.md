# Known Issues — to revisit after MVP

Tracking debt accumulated while shipping MVP. Each phase introduced something we'll need to come back to.

## Phase 6 — Editor rendering

### Issue 6-A: Hybrid inline hide not working (UI)

**Status:** Workaround in place. Markers are visible-but-dim instead of fully hidden on inactive lines.

**What's wrong:** The original `HiddenMarkerLayoutManager` overrode `setGlyphs` and inserted `.null` GlyphProperty bits. This caused garbled Unicode chars on the just-typed character and on initial file open (until window resize). Replaced with attribute-based dimming (`secondaryColor` on all markers).

**What we want (per design doc):**
- Markers fully hidden on inactive lines (not just dim).
- Heading hashes always hidden.
- Bear-style — caret on a line reveals the markers dimmed.

**Approaches to try:**
1. **Zero-width `NSTextAttachment`** — for marker chars off active line, attach a custom attachment with `attachmentBounds` returning `.zero`. The underlying chars stay in `storage.string` (so file save round-trips perfectly), but rendering shows nothing. Toggle attachment on/off as caret moves.
2. **TextKit 2 (`NSTextLayoutFragment`)** — modern replacement for `NSLayoutManager`. Far more flexible for character substitution. Bigger refactor.
3. **`.font` size 0 + `.kern` adjustment** — fragile but simpler than attachments.

**Why deferred:** Layout-manager approach was crashing the rendering. Attachments need careful undo/typing-attribute handling. Both > 1 day of focused work.

### Issue 6-B: Typing isn't real-time (Performance)

**Status:** Improved with 200ms debounce. Still feels laggy on large files.

**What's wrong:**
- Every edit triggers a full `cmark` re-parse of the entire document.
- For each block, inline-span extraction does a SECOND cmark parse (substring re-parse via `inlineSpans(in:source:)`).
- For each fenced code block, Highlightr runs a JSContext call (~5-50ms).
- Newly typed characters show in default font weight until 200ms after last keystroke (debounce delay).

**Visible symptom:** typing in a large file (~30KB) shows the just-typed characters in a different visual weight than the rest until the highlighter catches up.

**Approaches to try:**
1. **Incremental block re-parse (Task 4.5 from plan).** Compute the affected block range from `editedRange`, re-parse only that block, apply attributes only to that range. cmark gives us the AST cheaply per block.
2. **Cache `inlineSpans` per block.** Hash the block's substring; only re-parse on hash mismatch.
3. **Async Highlightr.** Run code-block highlighting on a background queue, apply results back on main when ready. Code blocks won't have colored tokens for ~50ms after typing inside them — acceptable.
4. **Set typing attributes after each highlight pass** so new chars at the caret inherit the right style without waiting for the next debounce tick.
5. **Reduce debounce to ~50ms for short edits, keep 200ms for paste/large changes.**

**Why deferred:** Each requires careful state tracking. Incremental re-parse is the biggest win and would warrant a dedicated subagent task.

### Issue 6-C: Several markdown elements not rendered visually (Functionality)

**Status:** Parsed but not styled.

**Currently rendered well:**
- Headings (bold, larger sizes by level).
- Bold (after font-trait fix).
- Italic.
- Strikethrough.
- Inline code (mono + light bg).
- Fenced code blocks (mono + bg + Highlightr token colors).
- Links (color + clickable).
- Blockquote (indent + dimmer color).

**Currently NOT visually distinct:**
- **Lists** — bullet/number markers visible (dim) but no hanging indent applied. List items wrap under the bullet column instead of under the text column.
- **Task lists** (`- [ ]` / `- [x]`) — same as lists. Checkbox not rendered as a glyph.
- **Tables** — pipes and `---` separators visible as plain text. No grid rendering.
- **HR (`---`)** — shown as three dashes (dim). No separator-line rendering.
- **Images** — `![alt](path)` shown as raw markdown text with marker dimming. Should be replaced by inline `NSTextAttachment` (Task 10.4).

**Approaches to try:**
1. **List hanging indent** — for `.list` blocks, build an `NSParagraphStyle` with `headIndent` matching marker width.
2. **Task checkbox** — for items with `taskState`, replace marker range with a Unicode `☐ / ☑` char or a custom attachment.
3. **HR separator line** — paragraph style with a top border, OR a custom `NSTextAttachment` that draws a horizontal line.
4. **Tables** — significant work. Custom `NSTextAttachment` for the whole table OR a separate inline view via `NSAccessory`. Defer to post-MVP.
5. **Inline images** — Task 10.4 in the plan; not yet implemented.

**Why deferred:** Each is a polish item. Plan tasks 10.x cover several of these explicitly.

---

## Phase 10 — Polish

### Issue 10-A: Inline images not rendered (Phase 10)

`![alt](path.png)` syntax is parsed (parser emits `.image` span) but not rendered as inline images in the editor. Markdown text shows as raw with marker dimming.

**Why deferred:** Proper inline image rendering requires character substitution — replacing the markdown span with a single NSTextAttachment containing the image. Doing this without mutating the source string requires either a custom layout fragment (TextKit 2) or a delegate-based approach. Both are non-trivial and weren't blockers for MVP.

**Approach to try:** Convert image markdown range into a contiguous "attachment region" via custom layout manager — replace the entire range with a single attachment glyph at render time, restore source on save.

---

## How we'll address these

After we finish a complete pass through the MVP scope (Phases 7-10), we'll create a **"v0.2 polish"** plan that prioritizes these issues:

1. **Issue 6-B** (performance) — highest user impact. Tackle via incremental re-parse.
2. **Issue 6-A** (true hide) — second highest, the "magic" UX. Try zero-width attachments first.
3. **Issue 6-C** (visual completeness) — bite-sized. Address element-by-element.

Each issue will get its own design + plan once we hit it.
