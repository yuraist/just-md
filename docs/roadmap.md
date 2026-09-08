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

Code is feature-complete for 1.0; the QA pass is done (2026-09-07). The
remaining release work is tracked in Linear, project
[JustMD 1.0 Release](https://linear.app/nuta-life/project/justmd-10-release-cc787e86c15d)
(Prism App team):

| Issue | Step |
|---|---|
| [PRI-42](https://linear.app/nuta-life/issue/PRI-42) | ✅ 1.0 release QA pass (16 defects fixed, Print/PDF, folder access for Read-mode images) |
| [PRI-43](https://linear.app/nuta-life/issue/PRI-43) | Create the App Store Connect app record, bump the build number, re-archive, upload |
| [PRI-44](https://linear.app/nuta-life/issue/PRI-44) | App Store metadata, screenshots, privacy labels (texts in [`appstore-metadata.md`](appstore-metadata.md)) |
| [PRI-45](https://linear.app/nuta-life/issue/PRI-45) | Fix the GitHub Pages domain so support / privacy-policy URLs resolve |
| [PRI-50](https://linear.app/nuta-life/issue/PRI-50) | ✅ License MIT, price Free |
| [PRI-46](https://linear.app/nuta-life/issue/PRI-46) | Launch marketing: landing page, preview video, PR |
| [PRI-47](https://linear.app/nuta-life/issue/PRI-47) | Submit for App Store review |
| [PRI-48](https://linear.app/nuta-life/issue/PRI-48) | ✅ Developer ID build + notarization — [v1.0 DMG on GitHub Releases](https://github.com/yuraist/justmd/releases/tag/v1.0) (`scripts/release-devid.sh`) |

### v1.1 — polish

Tracked as [PRI-49](https://linear.app/nuta-life/issue/PRI-49) (backlog from [`known-issues.md`](known-issues.md)).

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
| App Store metadata | ✅ texts, categories, privacy labels, availability ([PRI-44](https://linear.app/nuta-life/issue/PRI-44)); screenshots/preview in [PRI-51](https://linear.app/nuta-life/issue/PRI-51) |
| Privacy policy + support URL | ✅ https://justmd.nuta.life/ ([PRI-45](https://linear.app/nuta-life/issue/PRI-45)) |
| License / pricing decision | ✅ MIT, free on the App Store ([PRI-50](https://linear.app/nuta-life/issue/PRI-50)) |
| Manual QA pass | ✅ 2026-09-07, all findings fixed or documented |
| Known non-blockers | see [`known-issues.md`](known-issues.md) — none block 1.0 |
