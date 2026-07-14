# VHS tape — herdr-e2b box-open flow (prefix+shift+e).
# Mirrors a real worktree into a live E2B sandbox, drops into its shell, then
# pulls the change back. The launch command is typed while Hidden so the gif
# shows the keybind (caption overlaid in post), not a typed command.
# Needs an E2B API key configured. Record: vhs assets/demo.tape
Output assets/demo.gif
Require bash
Set Shell bash
Set Theme "TokyoNight"
Set FontSize 14
Set Width 1180
Set Height 680
Set Padding 18
Set TypingSpeed 55ms

# hidden: PATH + a throwaway git project in an isolated state dir
Hide
Type 'export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.14.1/bin:$PATH"' Enter
Type 'export HERDR_E2B_STATE_DIR=/tmp/e2b-demo-box; rm -rf "$HERDR_E2B_STATE_DIR" /tmp/e2b-demo-proj; mkdir -p /tmp/e2b-demo-proj/demo' Enter
Type 'cd /tmp/e2b-demo-proj/demo && git init -q -b main && printf "# demo\n" > README.md && printf "console.log(\"hi\")\n" > index.js && printf "node_modules/\n" > .gitignore && git add -A && git -c user.email=d@d.co -c user.name=d commit -qm init' Enter
Type 'clear' Enter
Show

# empty prompt — the "prefix+shift+e" caption is overlaid here in post
Sleep 2500ms

# drive the keybind (typed hidden so the gif shows the keybind, not a command)
Hide
Type 'e2b-box open' Enter
Show

# provisioning spinner → the sandbox shell [e2b:demo]
Sleep 10s

# work "in the cloud"
Type 'ls' Enter
Sleep 2s
Type 'echo "edited in the cloud" > NOTE.md' Enter
Sleep 1800ms

# leave the shell → the on-close prompt → pull the change back down
Type 'exit' Enter
Sleep 2800ms
Type 'p' Enter
Sleep 4s

# ── Caption overlay (post-process) ─────────────────────────────────────────
#   magick -background '#1a1b26' -fill '#c0caf5' -font /System/Library/Fonts/Menlo.ttc \
#     -pointsize 26 label:'⌨  prefix + shift + e' -bordercolor '#7aa2f7' -border 3 \
#     -bordercolor '#1a1b26' -border 15 cap.png
#   ffmpeg -i demo.gif -i cap.png -filter_complex \
#     "[0:v]fps=12,scale=1100:-1:flags=lanczos[v];\
#      [v][1:v]overlay=(main_w-overlay_w)/2:main_h*0.58:enable='between(t,0.6,2.4)'[o];\
#      [o]split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
#     -y demo.gif
