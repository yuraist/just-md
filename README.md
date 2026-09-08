# JustMD

A native macOS markdown editor. Open a `.md` file and the syntax disappears: markers hide on every line except the one you're editing (Bear-style), links show their text only, lists get real bullets, rules become hairlines. Flip to **Read mode** (⇧⌘E) for a fully rendered view with real table grids, checkboxes, and inline images. Print (or Save as PDF) prints that rendered view. No file browser, no cloud, no sync, no tabs, no sidebars — inspired by Bear, iA Writer, and Medium.

> **Status:** 1.0 submitted for App Store review on 2026-09-08 (build 5); the release is tracked in Linear, project [JustMD 1.0 Release](https://linear.app/nuta-life/project/justmd-10-release-cc787e86c15d). See [`docs/roadmap.md`](docs/roadmap.md) for what's done, the mini-roadmap, and the production-readiness checklist; [`docs/distribution.md`](docs/distribution.md) for App Store / direct-download shipping options; [`docs/known-issues.md`](docs/known-issues.md) for open non-blockers.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 26.3+ with Swift 6.2.3 for development

## Build

```bash
open JustMD/JustMD.xcodeproj
# ⌘R to run, ⌘U to test
```

Or from CLI:

```bash
xcodebuild -project JustMD/JustMD.xcodeproj -scheme JustMD -destination 'platform=macOS' build
xcodebuild -project JustMD/JustMD.xcodeproj -scheme JustMD -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:JustMDTests test
```

## Continuous integration

Xcode Cloud builds every push to `master` (workflow **Release**: tests, then a Mac App Store archive). The shared scheme lives in `JustMD/JustMD.xcodeproj/xcshareddata/xcschemes/`. See [`docs/distribution.md`](docs/distribution.md).

## Architecture

AppKit document-based app (`NSDocument` per file) with SwiftUI for the Welcome and Preferences windows.

| Module | Role |
|---|---|
| `App/` | `@main` AppDelegate; menu wiring (Format, View → Reading Mode + Theme, Show Welcome). |
| `Document/` | `MarkdownDocument: NSDocument`, window controller (Read/Edit toolbar), view controller. Autosave + versions via `NSDocument`. |
| `Editor/` | `NSTextStorage` subclass with incremental highlighting (`BlockDiff` restyles only the edited window). `MarkerVisibilityController` hides syntax glyphs off the active paragraph. `MarkdownLayoutManager` draws HR rules and quote bars. `swift-cmark` for GFM parsing, `Highlightr` (cached, async) for fenced-code tokens. |
| `Reader/` | `MarkdownReadRenderer` — AST → display attributed string: real `NSTextTable` grids, checkboxes, inline images. |
| `Theme/` | `Theme` / `Palette` Codable models; builtin + user presets; `.justmd-theme` JSON export/import. |
| `Welcome/` | SwiftUI Welcome window: New / Open / Drop / Recent. |
| `Preferences/` | SwiftUI Preferences + Manage Themes (colorpickers). Persistence via `UserDefaults`. |
| `Support/` | "Support JustMD" window (Help menu, Welcome link): newsletter signup posted to Supabase, and a repeatable "Buy me a coffee" StoreKit 2 consumable. The purchase code is compiled out with `DIRECT_DISTRIBUTION` (set by `scripts/release-devid.sh`), so the DMG build ships only the newsletter form. |

Product scope and shortcuts: [`docs/product.md`](docs/product.md).

## Dependencies (SPM)

- [`swift-cmark`](https://github.com/apple/swift-cmark) — Apple's CommonMark + GFM parser.
- [`Highlightr`](https://github.com/raspu/Highlightr) — syntax highlighting for code blocks.

## Tests

153 tests as of the 1.1 Support work (2026-09-08) (see [`docs/known-issues.md`](docs/known-issues.md) for what it covered). Swift Testing (`@Test`, `@Suite`, `#expect`).

Run: `xcodebuild ... -parallel-testing-enabled NO -only-testing:JustMDTests test` (parallel test hosts deadlock xcodebuild for an app-hosted bundle).

## License

MIT, see [LICENSE](LICENSE). The App Store build is free; it offers an optional, repeatable "Buy me a coffee" in-app purchase ($2.99) that the direct-download build does not.
