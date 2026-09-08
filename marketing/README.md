# Marketing assets

Brief: Linear PRI-51. Screenshots and the preview are real captures of the
app on a Mac, not renders; the `AppStoreScreenshots` test suite that produced
the June images is superseded by the tools in `capture/`.

## Fixtures (`fixtures/`)

Real documents, written for a human reader.

- `hyperfine/README.md` — the README of [hyperfine](https://github.com/sharkdp/hyperfine)
  by David Peter and contributors, MIT licensed (`hyperfine/LICENSE-MIT`),
  with the three `doc/*.png` images it references. Fetched 2026-09-07,
  unmodified. Editor and Read mode shots.
- `walden-notes.md` — a reading note on *Walden*, chapter 2, with a quote
  (public domain) and a task list. Task list and theme shot.
- `lisbon-trip.md` — a four-day trip plan with a table and a packing list.
  Print dialog shot and the preview video.

## Screenshots (`screenshots/`)

2880×1800 PNG, display type `APP_DESKTOP`, en-US localization of version 1.0.

| File | Scene | Caption |
|------|-------|---------|
| `appstore-1-editor.png` | Editor, caret at the end of the "Features" heading of the hyperfine README | Syntax appears only on the line you edit. |
| `appstore-2-read.png` | Read mode of the same file at "Exporting results": table, images in cells, links | Reading mode, one shortcut away. |
| `appstore-3-tasks.png` | `walden-notes.md` in the Sepia theme, Settings window beside it | Checkboxes you click. Themes you can share. |
| `appstore-4-print.png` | `lisbon-trip.md` in Read mode with the print sheet and its PDF preview | Print, or save as PDF. |

Captions are set in the system font (SF Pro), semibold, sentence case, at
most eight words. The window sits on a flat `#EBEBED` background with the
shadow a Mac window normally casts.

### Capture

Everything runs from the shell; the host needs Accessibility (window
placement, keystrokes) and Screen Recording (`screencapture`).

1. Launch the Release build with a fixture:
   `open -n -a build/DerivedData/Build/Products/Release/JustMD.app marketing/fixtures/<file>.md`
2. Place the window with System Events, e.g.
   `set position of window 1 to {244, 190}` and `set size of window 1 to {1240, 720}`
   (860×720 for the shot that shares the canvas with Settings, placed at
   {150,180} with Settings at {1040,300}).
3. Put the document in the state the table describes. Scrolling: wheel
   events via `capture/mouse.swift` (`swiftc -O` it first); the caret: a real
   click, then ⌘→. Read mode images need the folder grant once per Mac (the
   "Allow access to folder…" link in the placeholder, Return in the panel).
4. `swift marketing/capture/compose.swift --list` prints JustMD's window ids.
5. `swift marketing/capture/compose.swift --out marketing/screenshots/<file>.png --caption "<caption>" --window <id> [--window <id>]`
   captures each window with `screencapture -l` and composes the canvas.
   For the print shot pass `--screen`: the sheet is a separate window with a
   glass backdrop, so the window's screen rectangle is grabbed instead and
   clipped to the window's rounded shape.
6. Upload with `scripts/asc-upload-screenshot.py <jwt> <localization id> APP_DESKTOP <png…>`
   after deleting the superseded ones (`DELETE /v1/appScreenshots/<id>`).

## Preview (`preview/`)

`preview-1.mp4`: 1920×1080, H.264, 30 fps, 30 s, silent. `poster.png` is the
frame at 00:00:11:00, the heading line with its `#` revealed.

What happens, in real time, cursor visible, no zoom or pan:

1. In Finder, select `lisbon-trip.md`, File → Open With → JustMD
   (`.md` files on the recording Mac belong to another editor).
2. Type a sentence at the end of the first paragraph.
3. Click past the end of the heading (its `#` appears), then back into the
   paragraph (it hides).
4. Scroll to the packing list, tick a checkbox.
5. ⇧⌘E to Read mode, scroll past the table, ⇧⌘E back.
6. View → Theme → Sepia.

`capture/record-preview.sh out.mov` drives it: `screencapture -v` on the
left 1440×810 points of the display (16:9), real pointer input from
`capture/mouse.swift`, keystrokes from System Events. The coordinates in the
script are for a 1728×1117 point display with the Finder window at {80,120}
640×440; the comments say how to re-measure. The take autosaves into the
fixture, so restore `lisbon-trip.md` from git afterwards.

Then `swift capture/scale-video.swift out.mov preview/preview-1.mp4`
(1920×1080, 30 fps), `swift capture/frames.swift preview/preview-1.mp4 <dir> 11`
for the poster, and
`scripts/asc-upload-preview.py <jwt> <localization id> DESKTOP preview/preview-1.mp4 00:00:11:00`.
