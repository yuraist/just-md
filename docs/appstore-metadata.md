# App Store Metadata — v1.0

Live in App Store Connect (app `6779422717`, version 1.0) since 2026-09-07; this
file mirrors it. Update both when the listing changes.

## App record

- **Platform:** macOS · **Bundle ID:** `com.nuta.JustMD` · **SKU:** `just.md.nuta.life`
- **Primary language:** English (U.S.)
- **Category:** Productivity, secondary Developer Tools
- **Price:** Free (USA base territory)
- **Age rating:** 4+

## Version info

- **Name** (≤30): `JustMD – Markdown Editor`
- **Subtitle** (≤30): `Markdown, without the noise`
- **Promotional text** (≤170): `Open a .md file and read it like a page. The syntax shows up only on the line you're editing, then gets out of the way again.`
- **Keywords** (≤100): `md,notes,readme,writing,writer,plain text,wysiwyg,distraction free,document,mdown,technical,focus`
- **Support / marketing URL:** `https://justmd.nuta.life/`
- **Privacy Policy URL:** `https://justmd.nuta.life/privacy`
- **What's New:** `First release.` (ASC refuses the field before the first release; set it on 1.0.1)

## Description

```
Open a README and you get the document, not the markup. Headings look like headings, bold reads as bold, links show their text. Put the caret on a line and its markdown comes back, dimmed, so you can edit it. Move on and it hides again.

JustMD is a native Mac editor for the .md files you already have. There is no library to import into, no vault, no account. Double-click a file in Finder, or drop it on the icon, and start typing. Autosave and Versions work the way they do in TextEdit.

While you write:
• Lists get real bullets, and task lists get checkboxes you can click.
• Tables line up into a grid as you type.
• Fenced code gets syntax colors.
• ⌘B and ⌘I for bold and italic, full undo, inline find.
• Files stay plain markdown on disk. Nothing is rewritten or reformatted.

Reading mode (⇧⌘E) turns the file into a finished page: table grids, inline images, clickable links. Print it, or save it as a PDF from the print dialog.

Make it yours: serif, sans or mono type, font size, line height and reading width. Five built-in themes, and custom palettes you can export as a small file and share.

JustMD is sandboxed and collects no data. It works with files anywhere on your Mac and needs macOS 14 or later.

Built for people who keep notes, journals, READMEs and docs in markdown and want a Mac app that treats those files as documents.
```

## Privacy labels (App Privacy section)

- **Data Not Collected** — no analytics, no network calls with user content, no identifiers.

## Review notes

```
JustMD is a local markdown editor/viewer. No account is needed. To test:
create or open any .md file (File → New / Open). Markdown syntax hides on
inactive lines; click a task checkbox to toggle it; ⇧⌘E switches Read mode.
```

## Screenshots and preview

Uploaded 2026-09-07 (Linear PRI-51); sources and the capture procedure are in
`marketing/README.md`. Four `APP_DESKTOP` screenshots, 2880×1800, real
captures of the app on a flat background, one caption each:

| File | Caption |
|------|---------|
| `marketing/screenshots/appstore-1-editor.png` | Syntax appears only on the line you edit. |
| `marketing/screenshots/appstore-2-read.png` | Reading mode, one shortcut away. |
| `marketing/screenshots/appstore-3-tasks.png` | Checkboxes you click. Themes you can share. |
| `marketing/screenshots/appstore-4-print.png` | Print, or save as PDF. |

One `DESKTOP` preview, `marketing/preview/preview-1.mp4` (1920×1080, H.264,
30 fps, 30 s, silent with an empty stereo track, which ASC requires), poster
frame at 00:00:11:00 (`marketing/preview/poster.png`).

Upload: `scripts/asc-upload-screenshot.py` and `scripts/asc-upload-preview.py`
(JWT from `scripts/asc-jwt.py`; localization id `024ce06a-ddd3-44ff-91ee-fab52e498947`).

## Writing rules for this listing

No competitor names (guideline 2.3.7). No em-dash tricolons, no CAPS section
headers, no exclamation marks. One concrete scene first, features second,
what the app deliberately does not do said once.
