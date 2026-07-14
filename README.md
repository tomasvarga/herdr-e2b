# herdr-e2b

Send a [herdr](https://herdr.dev) git worktree to a fresh [E2B](https://e2b.dev)
cloud sandbox **on demand** — a **snapshot upload of the live tree, uncommitted
changes and all** (no push, no clone, no creds). Press `prefix+shift+e` in a
worktree to boot its box and drop into a shell; the box is torn down when you
remove the worktree.

![herdr-e2b demo](assets/demo.gif)

> Status: early (v0.1). macOS + Linux.

## The loop

Creating a worktree does **nothing** by itself — you decide which worktrees go
to the cloud. When you want one up:

```
prefix+shift+e  (or: e2b-box open) ──▶ e2b-box provisions on the spot
                                   │  marks the box "provisioning"
                                   ▼
                             node provision.js (detached)
                               create E2B sandbox  ·  metadata: herdrWorktreeKey=<folder>
                               upload the worktree (batched sandbox.files.write)
                               git init  ·  record sandbox id + preview URL
                                   │
              spinner while booting ▼
                             exec `e2b sandbox connect <id>`   ← shell in the box

herdr worktree remove ──▶ worktree.removed event ──▶ teardown-worktree ──▶ e2b sandbox kill
```

Each worktree/folder gets its own box, keyed by folder name. Nothing is
auto-merged or pushed; the box is scratch cloud compute that starts as an exact
copy of your worktree.

## Requirements

- **herdr ≥ 0.7.0**, **Node.js ≥ 18**, **jq**
- **E2B**: the `@e2b/cli` (`e2b` on PATH, for the box shell) and an API key
  ([dashboard](https://e2b.dev/dashboard)). Provide the key **either** way:
  - `[secrets].e2b_api_key` in the plugin config (herdr-native, out of your
    shell profile and the repo, picked up by the running server — **recommended**), or
  - export **`E2B_API_KEY`** in the env herdr launches from (wins if both set).

## Install

    herdr plugin install tomasvarga/herdr-e2b

Local dev: `herdr plugin link /path/to/herdr-e2b` then `./install.sh`.
Then bind a key to the `plugin.herdr-e2b.open` action — e.g. `prefix+shift+e`.
(Avoid plain `prefix+e`: that's herdr's built-in `edit_scrollback`.)

The build step runs `npm install` (pulls the `e2b` SDK) and links `e2b-box`
onto your PATH. Run interactively (`./install.sh` from a terminal), it also
**prompts for your E2B API key** and saves it to the plugin config (hidden
input, `chmod 600`); it skips this silently during `herdr plugin install`
(no TTY) — set the key later then. It won't overwrite an existing config.

## Use

Create worktrees the way you normally do — nothing happens until you send one
up. In the worktree you want in the cloud:

    e2b-box            # provision (if needed) + open the box shell (spinner while booting)
    e2b-box up         # provision in the background, don't attach
    e2b-box status     # this worktree's box record (status, sandbox id, url)
    e2b-box list       # every tracked box
    e2b-box url        # preview URL (https://<port>-<id>.e2b.app)
    e2b-box logs       # tail provisioning progress
    e2b-box sync       # re-upload the current worktree into its box (local → box)
    e2b-box pull       # download the box's files back into this folder (box → local)
    e2b-box kill       # kill this worktree's box

`e2b-box` (no args) also works in a plain worktree that predates the plugin — it
provisions a box on the spot.

## How code gets in

File selection follows **git**: `git ls-files --cached --others --exclude-standard`
— tracked files (**including your uncommitted edits**) plus new untracked files,
**honoring `.gitignore`**. So build output, caches, `node_modules`, coverage, etc.
are *not* uploaded — only what git considers part of the repo. The files are sent
via the E2B SDK's `files.write` in batches; `.git` itself is skipped and the box
runs `git init -b <branch>`. The `[upload].ignore` list is an extra safety filter
on top (keeps `.env` out even if tracked); for non-git folders it's the only
filter. Re-run `e2b-box sync` to push local changes up again.

## Templates

Boxes default to **`base`** — E2B's minimal image, always available. Fine for
trying the flow, but tight on disk with no toolchain.

### Recommended: a bigger custom template

For real work, build a custom E2B template once — **more disk + CPU**, with your
toolchain (node/pnpm/etc. or a coding agent) baked in — and point the config at it:

```toml
[sandbox]
template = "my-herdr-box"
```

E2B fixes resources at build time, so a custom template is how you get a roomier
box that boots ready. Build it with `e2b template build` (E2B's
[template docs](https://e2b.dev/docs/sandbox-template)) — or ask your coding
agent to set one up. `install.sh` prints this reminder.

### Public agent templates

E2B also ships public agent templates you can name directly (handy, though they
can be tight on disk):

| Agent | Template | E2B docs |
| --- | --- | --- |
| Claude Code | `claude-code` | [docs](https://e2b.dev/docs/agents/claude-code) |
| Codex | `codex` | [docs](https://e2b.dev/docs/agents/codex) |
| OpenCode | `opencode` | [docs](https://e2b.dev/docs/agents/opencode) |
| Amp | `amp` | [docs](https://e2b.dev/docs/agents/amp) |
| Grok Build | `grok` | [docs](https://e2b.dev/docs/agents/grok) |
| Devin | `devin` | [docs](https://e2b.dev/docs/agents/devin) |

Route per branch with rules:

```toml
[[sandbox.template_rules]]        # e.g. e2b/cx/* → Codex
pattern  = "^e2b/cx/"
template = "codex"
```

If a configured template isn't available, provisioning falls back to `base` with
a notification rather than failing.

## Configuration

Copy `config/config.example.toml` to
`~/.config/herdr/plugins/config/herdr-e2b/config.toml`. Everything has sane
defaults; set only what you want to change (template, timeout, project path,
preview port, upload batch size, ignore list).

## Limitations (v0.1)

- **Sync is on-demand, not continuous** — `e2b-box sync` pushes local → box and
  `e2b-box pull` brings box → local (git-aware, honors `.gitignore`). `pull` only
  writes files that differ and **reports each one** (`+ new` / `~ overwrote`),
  leaves unchanged files untouched, never deletes local-only files, and warns
  before clobbering a dirty git tree or a non-git folder. Review with `git diff`.
- **Symlinks are skipped** during upload.
- **One box per worktree/folder**, keyed by folder name; two folders with the
  same name would collide.
- Removing a worktree **kills** its box (cost control) — this is intentional.
- **Boxes idle-time-out** after `[sandbox].timeout_ms` (default 1h, and the cap
  on E2B's hobby plan). If the box has died, `e2b-box open` detects it and
  **reprovisions** a fresh one rather than failing. Bump `timeout_ms` (paid plan)
  for longer-lived boxes.

## License

MIT.
