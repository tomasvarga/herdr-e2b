# Recording the demo GIFs

Both GIFs are recorded with [VHS](https://github.com/charmbracelet/vhs) and use a
**real E2B sandbox** (so they need an API key configured). Each tape is
self-contained and carries its own caption-overlay recipe in a trailing comment.

- **`demo.tape` → `assets/demo.gif`** — the box-open flow: a throwaway git
  project is mirrored into a live sandbox, you work in its `[e2b:demo]` shell,
  then pull the change back. The launch is typed while `Hide`d so the gif shows
  the `prefix+shift+e` keybind (caption overlaid in post), not a command.
- **`dashboard.tape` → `assets/dashboard.gif`** — the dashboard TUI: the live
  board, then open a real sandbox, work in its shell, and land back on the board.
  Uses `tui/demo/seed-live-demo.sh` (5 placeholder records + one real `web`).

## Record

    vhs assets/demo.tape        # or: vhs assets/dashboard.tape

## Prerequisites

- `vhs`, `ffmpeg`, and `magick` (ImageMagick) on `PATH`.
- An E2B API key (`[secrets].e2b_api_key` or `E2B_API_KEY`) — the tapes provision
  real sandboxes and kill them at the end.
- Node ≥ 22 (nvm/Homebrew) and the built dashboard binary
  (`tui/target/release/e2b-dash`, or run `tui/build-prebuilt.sh`).

## Captions

VHS can't do timed overlays, so captions are composited afterward with
ImageMagick + `ffmpeg overlay` — the exact command is in each tape's trailing
comment. Keep gifs tokyo-night themed and use generic placeholder names only
(never real project names).
