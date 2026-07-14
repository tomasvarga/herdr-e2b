# VHS tape — herdr-e2b dashboard (Ratatui TUI).
# Record: vhs assets/dashboard.tape   (needs the built poc binary + sample data)
Output assets/dashboard.gif
Require bash
Set Shell bash
Set Theme "TokyoNight"
Set FontSize 14
Set Width 1180
Set Height 680
Set Padding 18
Set TypingSpeed 55ms

# hidden: seed sample boxes, isolate the theme state to a scratch dir (so the
# demo never touches real state and always starts on the default theme), and
# launch the dashboard — so the gif opens straight on the board.
Hide
Type 'cd /Users/tomasvarga/Documents/GitHub/herdr-e2b' Enter
Type 'bash tui/demo/seed.sh >/dev/null 2>&1' Enter
Type 'export HERDR_E2B_STATE_DIR=/tmp/e2b-dash-demo; rm -rf "$HERDR_E2B_STATE_DIR"; mkdir -p "$HERDR_E2B_STATE_DIR"' Enter
Type 'clear' Enter
Type 'tui/target/release/e2b-dash tui/demo/sample-boxes' Enter
Sleep 2s
Show
Sleep 1600ms

# walk the fleet — the "target:" line tracks the selected box's worktree
Down
Sleep 750ms
Down
Sleep 750ms
Down
Sleep 950ms

# cycle themes with T (solarized-light → tokyonight → dracula) — saved per choice
Type "t"
Sleep 1200ms
Type "t"
Sleep 1200ms
Type "t"
Sleep 1400ms

# arm a sync confirm — spells out direction + the exact target path, then cancel
Type "s"
Sleep 2200ms
Type "n"
Sleep 800ms

# quit
Type "q"
Sleep 500ms
