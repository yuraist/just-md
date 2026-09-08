#!/bin/zsh
# Records the source clips for the Remotion promo (marketing/promo): one
# scene per file, the JustMD window only (screen rectangle of the window at
# the display's 2× scale), driven by real pointer and keyboard input.
#
# Same environment as record-preview.sh: regular desktop Space, 1728×1117
# point display, Accessibility + Screen Recording for the shell, JustMD
# quit, theme "Follow System", the fixtures folder grant stored.
# Fixtures are modified by autosave — restore them from git afterwards.
#
#   marketing/capture/record-clips.sh <out-dir>
set -e
OUT=${1:?output directory}
mkdir -p "$OUT"
HERE=${0:a:h}
REPO=${HERE:h:h}
APP="$REPO/build/DerivedData/Build/Products/Release/JustMD.app"
FIX="$REPO/marketing/fixtures"
MOUSE=${TMPDIR:-/tmp}/justmd-mouse
[[ -x $MOUSE ]] || swiftc -O "$HERE/mouse.swift" -o "$MOUSE" 2>/dev/null

key() { osascript -e "tell application \"System Events\" to $1"; }
type_words() {
  osascript - "$1" <<'EOF'
on run argv
  tell application "System Events"
    repeat with w in words of (item 1 of argv)
      keystroke ((w as text) & " ")
      delay 0.14
    end repeat
    key code 51
    keystroke "."
  end tell
end run
EOF
}
# open_doc <file> <x> <y> <w> <h>: open a fixture and place its window.
open_doc() {
  open -a "$APP" "$1"; sleep 2
  osascript -e "tell application \"System Events\" to tell process \"JustMD\"
    set frontmost to true
    delay 0.3
    set position of window 1 to {$2, $3}
    set size of window 1 to {$4, $5}
  end tell"
  sleep 0.6
}
close_docs() {
  osascript -e 'tell application "System Events" to tell process "JustMD"
    repeat with w in windows
      try
        perform action "AXPress" of (first button of w whose subrole is "AXCloseButton")
        delay 0.3
      end try
    end repeat
  end tell' >/dev/null 2>&1 || true
  sleep 0.5
}
theme() { osascript -e "tell application \"System Events\" to tell process \"JustMD\" to click menu item \"$1\" of menu 1 of menu item \"Theme\" of menu 1 of menu bar item \"View\" of menu bar 1"; }
rec_start() { screencapture -v -V 25 -x -R "$1" "$OUT/$2.mov" & REC=$!; sleep 0.8; }
rec_stop() { kill -INT $REC 2>/dev/null || true; wait $REC 2>/dev/null || true; sleep 0.5; }
WIN=244,190,1240,720

# 1. Typing and the syntax reveal (walden-notes.md).
open_doc "$FIX/walden-notes.md" 244 190 1240 720
$MOUSE click 690 385; key 'key code 124 using {command down}'; sleep 0.3
rec_start $WIN typing
sleep 0.8
key 'keystroke " "'; type_words "Worth rereading in winter"
sleep 1.0
$MOUSE click 800 270          # past the end of the heading: "#" appears
sleep 1.8
$MOUSE click 690 385          # back into the paragraph: it hides
sleep 1.4
rec_stop

# 2. Ticking task checkboxes (same window).
$MOUSE move 900 600 0.4
rec_start $WIN checkboxes
sleep 0.8
$MOUSE click 516 758
sleep 1.1
$MOUSE click 516 785
sleep 1.6
rec_stop
close_docs

# 3a. Read mode: the trip plan's table renders (lisbon-trip.md).
open_doc "$FIX/lisbon-trip.md" 244 190 1240 720
$MOUSE click 900 385; key 'key code 124 using {command down}'; sleep 0.3
rec_start $WIN readmode
sleep 1.0
key 'keystroke "e" using {command down, shift down}'
sleep 2.4
$MOUSE move 1200 700 0.4 scroll 1200 700 10
sleep 1.6
rec_stop
close_docs

# 3b. Read mode with images: hyperfine README at "Exporting results".
open_doc "$FIX/hyperfine/README.md" 244 190 1240 720
osascript -e 'tell application "System Events" to tell process "JustMD"
  perform action "AXPress" of button 1 of toolbar 1 of window 1
end tell'
sleep 1.5
$MOUSE move 1200 700 0.3 scroll 1200 700 262
sleep 1.0
rec_start $WIN images
sleep 0.8
$MOUSE scroll 1200 700 26
sleep 2.0
rec_stop
close_docs

# 4. Themes: Settings beside the document, theme changes via the View menu.
open_doc "$FIX/lisbon-trip.md" 150 180 860 720
osascript -e 'tell application "System Events" to tell process "JustMD"
  click menu item "Settings…" of menu 1 of menu bar item "JustMD" of menu bar 1
  delay 1
  set position of window "Settings" to {1040, 300}
end tell'
sleep 0.8
rec_start 150,180,1370,720 themes
sleep 1.0
theme Sepia; sleep 1.6
theme Black; sleep 1.6
theme White; sleep 1.4
rec_stop
theme "Follow System"
close_docs

# 5. Print: the sheet with its PDF preview (lisbon-trip.md, Read mode).
open_doc "$FIX/lisbon-trip.md" 244 190 1240 720
osascript -e 'tell application "System Events" to tell process "JustMD"
  perform action "AXPress" of button 1 of toolbar 1 of window 1
end tell'
sleep 1.2
rec_start $WIN print
sleep 0.8
key 'keystroke "p" using {command down}'
sleep 4.0
key 'key code 53'
sleep 0.8
rec_stop
close_docs
echo "clips in $OUT"; /bin/ls -la "$OUT"
