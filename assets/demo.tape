# VHS tape — herdr-e2b.  Record: see assets/DEMO.md (needs the HERDR_* unset +
# HERDR_CONFIG_PATH env). Starts a fresh herdr session inside VHS and mirrors a
# local project into a real E2B box, then drops into the box shell.
Output assets/demo.gif
Require bash
Set Shell bash
Set Theme "TokyoNight"
Set FontSize 13
Set Width 1200
Set Height 720
Set Padding 18
Set TypingSpeed 45ms

# hidden: PATH + delete any persisted demo session + seed a fresh project,
# then cd into it so herdr opens *in the demo project* (workspace "demo").
Hide
Type 'export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.14.1/bin:$PATH"' Enter
Type 'herdr session delete e2bdemo >/dev/null 2>&1; true' Enter
Type 'bash assets/seed-demo.sh' Enter
Type 'cd demo' Enter
Sleep 2s
Type 'clear' Enter
Show
Sleep 500ms

# fresh herdr session, opened in the demo project
Type "herdr --session e2bdemo" Enter
Sleep 4.5s
Type "clear" Enter
Sleep 800ms
Type "git log --oneline -1" Enter
Sleep 2s

# boot the box with the KEYBIND — no typed command. VHS can't emit a standalone
# Shift, so we drive the prefix (Ctrl+Space) + a plain-char proxy (u); the gif is
# captioned "prefix+shift+e" in post. See assets/DEMO.md.
Ctrl+Space
Sleep 500ms
Type "u"
Sleep 1.6s
# zoom the box pane to full-screen so it's a single pane, not a split
Ctrl+Space
Sleep 400ms
Type "z"
Sleep 12s

# inside the cloud box [e2b:demo] — make a change on "the other side"
Type "ls" Enter
Sleep 2.4s
Type 'echo "hello from the other side" > HELLO.md' Enter
Sleep 1.8s
Type "ls" Enter
Sleep 2.6s

# leave the box, then pull that change back down to the local folder
Type "exit" Enter
Sleep 2s
Type "e2b-box pull" Enter
Sleep 6s
Type "cat HELLO.md" Enter
Sleep 3.4s

# tear the box down
Type "e2b-box kill" Enter
Sleep 3s
