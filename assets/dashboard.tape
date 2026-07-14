# VHS tape — herdr-e2b dashboard (Ratatui TUI), rendered in tokyonight.
# Record: vhs assets/dashboard.tape   (needs the built tui binary + sample data)
Output assets/dashboard.gif
Require bash
Set Shell bash
Set Theme "TokyoNight"
Set FontSize 14
Set Width 1180
Set Height 680
Set Padding 18
Set TypingSpeed 55ms

# hidden: seed sample sandboxes, isolate theme state to a scratch dir, force the
# tokyonight theme, and launch — so the gif opens straight on the board.
Hide
Type 'cd /Users/tomasvarga/Documents/GitHub/herdr-e2b' Enter
Type 'bash tui/demo/seed.sh >/dev/null 2>&1' Enter
Type 'export HERDR_E2B_STATE_DIR=/tmp/e2b-dash-demo E2B_DASH_THEME=tokyonight; rm -rf "$HERDR_E2B_STATE_DIR"; mkdir -p "$HERDR_E2B_STATE_DIR"' Enter
Type 'clear' Enter
Type 'tui/target/release/e2b-dash tui/demo/sample-boxes' Enter
Sleep 2s
Show
Sleep 1600ms

# walk the fleet — colored statuses (● ready · ◐ provisioning · paused · failed);
# the "target:" line tracks the selected sandbox's worktree.
Down
Sleep 850ms
Down
Sleep 850ms
Down
Sleep 1000ms
Down
Sleep 900ms

# actions confirm and name the exact target — sync (local → sandbox) …
Type "s"
Sleep 2000ms
Type "n"
Sleep 700ms
# … and pull (sandbox → local), the other direction
Type "p"
Sleep 2000ms
Type "n"
Sleep 700ms

# quit
Type "q"
Sleep 500ms

# ── Caption overlay (post-process; VHS can't do timed overlays) ─────────────
# After recording, captions are composited with ImageMagick + ffmpeg:
#   cap(){ magick -background '#1a1b26' -fill '#c0caf5' -font /System/Library/Fonts/Menlo.ttc \
#      -pointsize 26 label:"$1" -bordercolor "$2" -border 3 -bordercolor '#1a1b26' -border 15 "$3"; }
#   cap "▸  a live board of your E2B sandboxes"    '#7aa2f7' c1.png
#   cap "every action confirms + names the target" '#9ece6a' c2.png
#   ffmpeg -i dashboard.gif -i c1.png -i c2.png -filter_complex \
#    "[0:v]fps=12,scale=1100:-1:flags=lanczos[v];\
#     [v][1:v]overlay=(main_w-overlay_w)/2:main_h*0.60:enable='between(t,0.5,4.5)'[o1];\
#     [o1][2:v]overlay=(main_w-overlay_w)/2:main_h*0.60:enable='between(t,6.5,11.5)'[o2];\
#     [o2]split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
#    -y dashboard.gif
