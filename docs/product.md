# JustMD — Product Overview

A minimalist native macOS markdown editor. Like Microsoft Word, but for markdown — and nothing more.

## What it does

- **Open `.md` files.** Double-click in Finder, drag onto the app, or use `File → Open`. Also `.markdown`, `.mdown`, `.mkd`.
- **One window per file.** No tabs, no file browser, no sidebars. Multi-window is native macOS behavior.
- **Autosaves.** Edits persist automatically — no `⌘S` required. File versions work via `File → Revert To ▸`.
- **Renders markdown inline.** Headings, bold, italic, strikethrough, links, inline code, fenced code blocks with syntax highlighting, lists, blockquotes, tables — all styled as you type.
- **Quick formatting.** `⌘B` wraps the selection in `**…**`. `⌘I` wraps in `*…*`.
- **Themes.** Five builtin presets (Follow System, White, Sepia, Gray, Black) plus custom presets with a six-color palette. Import/export `.justmd-theme` JSON files to share with friends.
- **Typography.** Serif / Sans / Mono font families, adjustable size (`⌘+` / `⌘−` / `⌘0`) and line height.

## What it doesn't do (on purpose)

- No file browser or sidebar — use Finder.
- No cloud sync — files live where you put them.
- No tabs — one window per file, like a real document.
- No tag system, no project management, no plugins.
- No outline/TOC, no split view, no preview-only mode.
- No Find & Replace (yet).
- No export to PDF/HTML (yet).
- No mermaid diagrams or LaTeX (yet).

These are intentional MVP trade-offs. Some may ship in future versions, but the core principle stays: **one file, one window, one focused writing surface.**

## Design inspiration

- **Bear / iA Writer** — markdown markers kept subtle, not front-and-center.
- **Medium** — distraction-free canvas, reading-width bounded.
- **Pages / TextEdit** — document-based, autosave, Versions, native file associations.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New document (asks where to save) |
| `⌘O` | Open file |
| `⌘W` | Close window |
| `⌘,` | Preferences |
| `⌃⌘W` | Show Welcome window |
| `⌘B` | Toggle **bold** for selection |
| `⌘I` | Toggle *italic* for selection |
| `⌘+` | Bigger font |
| `⌘−` | Smaller font |
| `⌘0` | Reset font size |
| `⌃⌘1` / `⌃⌘2` / `⌃⌘3` | Serif / Sans / Mono |
| `⌘`-click a link | Open in browser |

## File formats

- **`.md`** and friends — plain UTF-8 text. Round-trips perfectly; your markdown stays as markdown.
- **`.justmd-theme`** — plain JSON, shareable. Contains a theme name, an optional author, a light palette, and an optional dark palette.

Example `.justmd-theme`:

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
  }
}
```

Double-click a `.justmd-theme` file to import it into JustMD.

## Privacy

JustMD reads and writes only the files you open. No network activity, no telemetry, no accounts, no cloud services. Your writing never leaves your Mac.
