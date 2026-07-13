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

# hidden: PATH + seed a fresh demo project & clean state
Hide
Type 'export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.14.1/bin:$PATH"' Enter
Type 'bash assets/seed-demo.sh' Enter
Sleep 2s
Type 'clear' Enter
Show
Sleep 500ms

# start an isolated herdr session (Tokyo Night via HERDR_CONFIG_PATH)
Type "herdr --session e2bdemo" Enter
Sleep 4.5s
Type "clear" Enter
Sleep 700ms

# a normal local project, on herdr
Type "cd demo" Enter
Sleep 500ms
Type "git log --oneline -1" Enter
Sleep 1.8s

# one command: mirror this worktree into a fresh E2B box and drop into it
Type "e2b-box open" Enter
Sleep 13s

# we're inside the cloud box now — prompt reads [e2b:demo]
Type "pwd" Enter
Sleep 1.3s
Type "ls" Enter
Sleep 2.2s
Type "cat README.md" Enter
Sleep 2.6s

# leave the box (it keeps running) and tear it down
Type "exit" Enter
Sleep 1.6s
Type "e2b-box kill" Enter
Sleep 2.6s
