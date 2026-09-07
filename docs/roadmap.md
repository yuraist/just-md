# Roadmap & Production Readiness

Updated 2026-09-07 (release QA pass). Companion docs: [`known-issues.md`](known-issues.md) for open bug detail,
[`distribution.md`](distribution.md) for how to ship.

## What's done (the 2026-06 editor rework)

The editor went from "renders raw markdown with a 0.5–1 s lag" to a Bear-class hybrid editor:

- **Instant typing** — incremental highlighting restyles only the edited block window
  (`BlockDiff`), with per-block inline-span caching and async cached code highlighting.
  Guarded by a perf regression test (<100 ms on a ~30 KB document).
- **Markers hide off the active paragraph** — `#`, `*`, `` ` ``, `>`, link URLs vanish via
  glyph generation; the caret reveals them dimmed for editing.
- **Lists render natively** — dashes become • bullets, `- [ ]`/`- [x]` become □/☑
  checkboxes that are **clickable** (toggle goes through the undo stack), hanging indent,
  inline bold/italic/links/code inside items.
- **Tables** — aligned mono grids in the editor (pixel-padded columns); real `NSTextTable`
  grids in Read mode.
- **Blockquotes / HR** — accent bar and hairline rules drawn by the layout manager.
- **Cmd+B / Cmd+I** — wrap/unwrap with selection trimming, undo-safe (the template
  Format menu that swallowed the shortcuts was removed).
- **Read mode (⇧⌘E)** — fully rendered viewer: tables, checkboxes, local inline images,
  clickable links.
- **App Store prep** — icon set, sandbox + hardened runtime, productivity category,
  copyright, encryption-exemption key.
- **137 tests** (Swift Testing), green at every commit, including offscreen-render
  visual verification.
- **Release QA pass (2026-09)** — line height and reading width wired, nested
  lists, Read-mode rule/code-block fixes, Welcome/Settings/menu polish,
  Print → PDF, and sandbox folder grants for Read-mode images.

## Mini-roadmap

### v1.0 — ship it

Code is feature-complete for 1.0. What remains is release work, not engineering:

1. Pick the distribution channel(s) — see [`distribution.md`](distribution.md).
2. App Store Connect record: name, subtitle, description, keywords, screenshots,
   privacy "Data Not Collected" labels, support + privacy-policy URLs.
3. ~~Manual QA pass~~ — done 2026-09-07 (16 defects fixed, Print/PDF and
   folder access for Read-mode images added; see [`known-issues.md`](known-issues.md)).
4. Decide the license line in README (currently TBD) and pricing (free / paid / freemium).

### v1.1 — polish

- Remote images in Read mode (async download + cache).
- Table editing ergonomics: Tab to next cell, auto-format column widths.
- IME (Japanese/Korean) marked-text testing.

### v1.2+ — bigger rocks

- Inline images in the editor (needs TextKit 2 custom fragments or display-string mapping).
- TextKit 2 migration — fixes slow window-resize reflow on 100 KB+ files.
- Sparkle auto-updates, if the Developer ID (own-site) channel is used.

## Production readiness checklist

| Area | Status |
|---|---|
| Typing performance | ✅ incremental restyle, perf regression test |
| Test suite | ✅ 137 tests green |
| Undo correctness | ✅ all programmatic edits via `shouldChangeText`/`didChangeText` |
| App Sandbox | ✅ `ENABLE_APP_SANDBOX`, user-selected files read/write |
| Hardened runtime | ✅ |
| Icon / category / copyright | ✅ |
| Export compliance | ✅ `ITSAppUsesNonExemptEncryption = false` |
| Signing | ✅ automatic, team `N2HCJ99WYH`, bundle `com.nuta.JustMD` |
| Version | ✅ `MARKETING_VERSION = 1.0`, build 1 |
| App Store metadata | ⬜ screenshots, description, keywords, privacy labels |
| Privacy policy + support URL | ⬜ required by App Store review |
| License / pricing decision | ⬜ |
| Manual QA pass | ✅ 2026-09-07, all findings fixed or documented |
| Known non-blockers | see [`known-issues.md`](known-issues.md) — none block 1.0 |
