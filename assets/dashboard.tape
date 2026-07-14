# VHS tape — herdr-e2b dashboard (Ratatui TUI), tokyo-night, with the full
# open → work → return-to-the-board flow against a REAL sandbox.
# Needs an E2B API key configured (seed-live-demo.sh provisions a real 'web').
# Record: vhs assets/dashboard.tape
Output assets/dashboard.gif
Require bash
Set Shell bash
Set Theme "TokyoNight"
Set FontSize 14
Set Width 1180
Set Height 680
Set Padding 18
Set TypingSpeed 55ms

# hidden: PATH (e2b CLI + node), isolate demo state, seed 5 placeholders + one
# REAL 'web' sandbox (blocks until ready), force tokyo-night, launch the board.
Hide
Type 'export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.14.1/bin:$PATH"' Enter
Type 'cd /Users/tomasvarga/Documents/GitHub/herdr-e2b' Enter
Type 'export HERDR_E2B_STATE_DIR=/tmp/e2b-dash-demo E2B_DASH_THEME=tokyo-night' Enter
Type 'bash tui/demo/seed-live-demo.sh "$HERDR_E2B_STATE_DIR" >/dev/null 2>&1' Enter
Type 'clear' Enter
Type 'tui/target/release/e2b-dash' Enter
Sleep 2s
Show
Sleep 1600ms

# walk the fleet down to the real 'web' sandbox (statuses + target line update)
Down
Sleep 700ms
Down
Sleep 700ms
Down
Sleep 700ms
Down
Sleep 1000ms

# open it — the board hands its pane to the sandbox shell (E2B_DASH quiet mode)
Type "o"
Sleep 5s
Type "ls" Enter
Sleep 2s
Type 'echo "made in the sandbox" > NOTE.md' Enter
Sleep 1800ms

# exit the shell — and you land right back on the board, which offers pull/kill/leave
Type "exit" Enter
Sleep 3s
Type "l"
Sleep 1500ms

# quit
Type "q"
Sleep 500ms
