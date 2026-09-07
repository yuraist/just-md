# App Store Metadata — v1.0

Ready to paste / push via the ASC MCP once the app record exists
([PRI-43](https://linear.app/nuta-life/issue/PRI-43)); filling it in is
[PRI-44](https://linear.app/nuta-life/issue/PRI-44).

## App record (create at appstoreconnect.apple.com → My Apps → ＋ → New App)

- **Platform:** macOS
- **Name:** `JustMD` (fallbacks if taken: `JustMD — Markdown Editor`, `JustMD: Markdown, Just Clean`)
- **Primary language:** English (U.S.)
- **Bundle ID:** `com.nuta.JustMD` (already registered, shows in the dropdown)
- **SKU:** `com.nuta.JustMD`

## Version info

- **Subtitle** (≤30 chars): `Markdown, without the noise`
- **Promotional text** (≤170 chars):
  `Open any .md file and see a clean document — syntax hides while you write, reappears on the line you edit. Native, instant, no account.`
- **Keywords** (≤100 chars):
  `markdown,md,editor,text,writing,notes,readme,viewer,bear,typora,plain text,writer,document`
- **Support URL:** `https://yuraist.github.io/justmd/`
- **Privacy Policy URL:** `https://yuraist.github.io/justmd/privacy.html`
- **Category:** Productivity (already set in the binary)
- **Price:** Free (decide before submit; can add paid later)

## Description

```
JustMD opens your markdown files the way TextEdit opens text — instantly,
natively, and without a library, a vault, or an account.

Instead of raw markup you see the document. Syntax markers hide on every
line except the one you're editing: headings look like headings, bold reads
as bold, links show their text. Move the caret onto a line and the markdown
reappears, dimmed and editable.

WRITE
• Syntax hides as you type, Bear-style — the caret line reveals it
• Lists get real bullets; task lists get clickable checkboxes
• Tables align into clean grids while you edit them
• Fenced code blocks with syntax highlighting
• ⌘B / ⌘I formatting, full undo, autosave, macOS Versions

READ
• One shortcut (⇧⌘E) flips to a fully rendered page
• Real table grids, inline images, clickable links

YOURS
• Plain .md files on disk — no lock-in, no sync, no subscription
• Five built-in themes plus custom palettes you can export and share
• Serif, sans, or mono typography with adjustable size and line height
• Sandboxed and private: the app collects no data at all

JustMD is for people who live in markdown — notes, READMEs, journals,
docs — and want a Mac app that treats those files like documents, not
source code.
```

## What's New (v1.0)

```
Initial release — write markdown without seeing it.
```

## Privacy labels (App Privacy section)

- **Data Not Collected** — the app has no analytics, no network calls with
  user content, no identifiers.

## Review notes

```
JustMD is a local markdown editor/viewer. No account is needed. To test:
create or open any .md file (File → New / Open). Markdown syntax hides on
inactive lines; click a task checkbox to toggle it; ⇧⌘E switches Read mode.
```

## Screenshots

`marketing/screenshots/appstore-1-editor.png`, `appstore-2-read.png`
(2880×1800, regenerate any time: `xcodebuild … -only-testing:JustMDTests/AppStoreScreenshots test`,
then copy from `~/Library/Containers/com.nuta.JustMD/Data/tmp/`).
