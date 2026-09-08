#!/bin/zsh
# Records the App Store preview: a real-time screen recording of JustMD driven
# by real pointer and keyboard input (see marketing/README.md for the script).
#
# Expects, on a regular desktop Space of a 1728×1117 point display:
#   - JustMD not running; theme "Follow System"; the folder grant for
#     marketing/fixtures already stored (Read mode images);
#   - a Finder window on marketing/fixtures in list view at {80,120} 640×440,
#     so the lisbon-trip.md row sits at (342,235);
#   - nothing else on the left 1440×810 points of the screen.
# Coordinates below come from a dry run on that layout; re-measure them with
# System Events if the layout changes. The fixture is modified by the take
# (autosave) — restore it from git afterwards.
#
#   marketing/capture/record-preview.sh out.mov
set -e
OUT=${1:?output .mov}
HERE=${0:a:h}
MOUSE=${TMPDIR:-/tmp}/justmd-mouse
[[ -x $MOUSE ]] || swiftc -O "$HERE/mouse.swift" -o "$MOUSE" 2>/dev/null

# Types word by word: one keystroke call per character is too slow for a
# 30-second preview, whole-string typing looks pasted; bursts read as typing.
type_text() {
  osascript - "$1" <<'EOF'
on run argv
  tell application "System Events"
    repeat with w in words of (item 1 of argv)
      keystroke ((w as text) & " ")
      delay 0.12
    end repeat
    key code 51
    keystroke "."
  end tell
end run
EOF
}
key() { osascript -e "tell application \"System Events\" to $1"; }

osascript -e 'tell application "System Events" to tell process "Finder" to set frontmost to true'
sleep 0.5

screencapture -v -V 30 -x -R 0,0,1440,810 "$OUT" &
REC=$!
sleep 0.4

# 1. Open the file from Finder: select it, File → Open With → JustMD.
$MOUSE click 342 235 sleep 0.4 click 127 16 sleep 0.5 click 200 195 sleep 0.6 click 470 374
sleep 2.2

# 2. Type a sentence at the end of the first paragraph.
$MOUSE click 1049 333
sleep 0.3
key 'key code 124 using {command down}'
key 'keystroke " "'
type_text "We land at noon"
sleep 0.6

# 3. Caret onto the heading (its # appears), then away (it hides). Click past
#    the end of the line: revealed markers shift the text under the pointer,
#    and a click inside the word would end up selecting it.
$MOUSE click 1024 244
sleep 1.4
$MOUSE click 1049 333
sleep 0.7

# 4. Scroll to the packing list and tick a checkbox.
$MOUSE move 1164 636 0.4 scroll 1164 636 25
sleep 0.6
$MOUSE click 516 703
sleep 1.0

# 5. Read mode, scroll past the table, back to Edit.
key 'keystroke "e" using {command down, shift down}'
sleep 1.3
$MOUSE move 1164 500 0.3 scroll 1164 500 14
sleep 1.0
key 'keystroke "e" using {command down, shift down}'
sleep 0.7

# 6. View → Theme → Sepia.
$MOUSE click 288 16 sleep 0.5 click 330 134 sleep 0.5 click 500 182
sleep 1.6

kill -INT $REC
wait $REC || true
echo "recorded $OUT"
