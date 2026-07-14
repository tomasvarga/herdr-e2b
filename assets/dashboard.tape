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

# ── Caption overlay (post-process; VHS can't do timed overlays) ─────────────
# After recording, captions are composited with ImageMagick + ffmpeg:
#   cap(){ magick -background '#1a1b26' -fill '#c0caf5' -font /System/Library/Fonts/Menlo.ttc \
#      -pointsize 26 label:"$1" -bordercolor "$2" -border 3 -bordercolor '#1a1b26' -border 15 "$3"; }
#   cap "▸  a live board of your E2B sandboxes"  '#7aa2f7' c1.png
#   cap "T  ·  cycle themes (remembered)"         '#bb9af7' c2.png
#   cap "actions confirm + show the target path"  '#9ece6a' c3.png
#   ffmpeg -i dashboard.gif -i c1.png -i c2.png -i c3.png -filter_complex \
#    "[0:v]fps=12,scale=1100:-1:flags=lanczos[v];\
#     [v][1:v]overlay=(main_w-overlay_w)/2:main_h*0.60:enable='between(t,0.5,3.8)'[o1];\
#     [o1][2:v]overlay=(main_w-overlay_w)/2:main_h*0.60:enable='between(t,4.2,7.7)'[o2];\
#     [o2][3:v]overlay=(main_w-overlay_w)/2:main_h*0.60:enable='between(t,8.0,10.0)'[o3];\
#     [o3]split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
#    -y dashboard.gif
