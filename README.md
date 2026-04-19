# JustMD

A native macOS markdown editor. Open a `.md` file, see it rendered with dimmed syntax markers, write more text. No file browser, no cloud, no sync, no tabs, no sidebars — inspired by Bear, iA Writer, and Medium.

> **Status:** MVP (v0.1.0). See [`docs/product.md`](docs/product.md) for what it does; [`docs/known-issues.md`](docs/known-issues.md) for what's deferred to v0.2.

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
xcodebuild -project JustMD/JustMD.xcodeproj -scheme JustMD -destination 'platform=macOS' -only-testing:JustMDTests test
```

## Architecture

AppKit document-based app (`NSDocument` per file) with SwiftUI for the Welcome and Preferences windows.

| Module | Role |
|---|---|
| `App/` | `@main` AppDelegate; menu wiring (Format, View → Theme, Show Welcome). |
| `Document/` | `MarkdownDocument: NSDocument`, window controller, view controller. Autosave + versions via `NSDocument`. |
| `Editor/` | `NSTextStorage` subclass with debounced syntax highlighter. `swift-cmark` for GFM parsing, `Highlightr` for fenced-code tokens. |
| `Theme/` | `Theme` / `Palette` Codable models; builtin + user presets; `.justmd-theme` JSON export/import. |
| `Welcome/` | SwiftUI Welcome window: New / Open / Drop / Recent. |
| `Preferences/` | SwiftUI Preferences + Manage Themes (colorpickers). Persistence via `UserDefaults`. |

Full design: [`docs/plans/2026-04-18-just-md-design.md`](docs/plans/2026-04-18-just-md-design.md).
Implementation plan: [`docs/plans/2026-04-18-just-md-implementation.md`](docs/plans/2026-04-18-just-md-implementation.md).

## Dependencies (SPM)

- [`swift-cmark`](https://github.com/apple/swift-cmark) — Apple's CommonMark + GFM parser.
- [`Highlightr`](https://github.com/raspu/Highlightr) — syntax highlighting for code blocks.

## Tests

72 tests across 14 suites as of v0.1.0. Swift Testing (`@Test`, `@Suite`, `#expect`).

Run: `xcodebuild ... -only-testing:JustMDTests test`.

## License

TBD.
