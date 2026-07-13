# Recording the herdr-e2b demo GIF

`assets/demo.gif` is recorded with [VHS](https://github.com/charmbracelet/vhs).
The tape (`assets/demo.tape`) starts a *fresh, isolated herdr session inside
VHS's own terminal*, seeds a tiny sample project (`assets/seed-demo.sh` → `demo/`),
and runs the real flow: `e2b-box open` provisions a **live E2B box**, mirrors the
worktree, and drops into the box shell — all in the captured frame.

## Prerequisites

- `vhs` and `ffmpeg` on `PATH`.
- An E2B API key configured (`[secrets].e2b_api_key` in the plugin config, or
  `E2B_API_KEY`) — the demo boots a real sandbox.
- Node ≥ 22 available (nvm/Homebrew); the plugin resolves it itself.

## The gotchas (each cost a take)

1. **Strip `HERDR_*`** — herdr refuses to start *nested*. Recording from inside
   herdr, unset those vars so the herdr *inside VHS* starts clean.
2. **Theme** — point the fresh session at `assets/demo-herdr.toml`
   (`[theme] name = "tokyo-night"`, `pane_history = false`) via `HERDR_CONFIG_PATH`.
3. **Real box** — the demo provisions and connects to an actual sandbox, then
   `e2b-box kill`s it at the end. `e2b sandbox connect` needs a raw TTY; VHS's
   terminal provides one, so it works inside the recording.
4. **Folder name = box name** — the sample project is a git repo named `demo/`,
   so the box keys as `demo` and the prompt reads `[e2b:demo]`.

## Record

```bash
# herdr rewrites the config it's pointed at — use a throwaway copy so the
# committed assets/demo-herdr.toml stays pristine.
cfg="$(mktemp).toml"; cp assets/demo-herdr.toml "$cfg"

# start from a clean session (the tape also does this): a persisted e2bdemo
# session would otherwise be reattached with its old panes restored.
herdr session delete e2bdemo 2>/dev/null || true

env -u HERDR_SOCKET_PATH -u HERDR_PANE_ID -u HERDR_SESSION -u HERDR_ENV \
    -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID \
    HERDR_CONFIG_PATH="$cfg" \
    vhs assets/demo.tape

herdr session stop e2bdemo 2>/dev/null || true
rm -f assets/release-notes.json   # herdr may drop its startup notes here
```

## Post-process (trim herdr boot + speed the idle)

```bash
cp assets/demo.gif /tmp/demo-raw.gif
ffmpeg -ss 1.4 -i /tmp/demo-raw.gif \
  -filter_complex "[0:v]setpts=0.62*PTS,fps=15,scale=1160:-1:flags=lanczos,\
split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer" \
  -y assets/demo.gif
```

Result: ~21s, ~565 KB.

## Verifying (you can't watch the recording live)

Extract frames and inspect — look for the `[e2b:demo]` prompt and `ls` showing
`README.md package.json src` (no `node_modules`, proving `.gitignore` is honored):

```bash
ffmpeg -i assets/demo.gif -vf fps=1 /tmp/f_%03d.png
```
