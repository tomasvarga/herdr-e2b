# Architecture

A map of the codebase for reviewers. herdr-e2b mirrors a git worktree into an E2B
cloud sandbox on demand. This doc explains the layers, the data flow, the state
model, and the invariants worth checking during review.

## Three layers (and why)

```
┌─ herdr ─────────────────────────────────────────────────────────────┐
│  manifest (herdr-plugin.toml): actions · panes · events · build      │
└───────────────┬──────────────────────────────────────────────────────┘
                │ invokes
        ┌───────▼────────┐   control plane (bash)      resolves node/e2b, TTY
        │  bin/e2b-box   │──────────────────────────►  handling, spinner, prompts
        │  bin/e2b-dash  │
        └───────┬────────┘
                │ shells out to
        ┌───────▼────────┐   data plane (Node ESM)     the ONLY place the E2B SDK
        │   src/*.js     │──────────────────────────►  is called (SDK is JS-only)
        └───────┬────────┘
                │ SDK
        ┌───────▼────────┐
        │  E2B sandbox   │   getHost() preview URL · files.write/read · commands.run
        └────────────────┘

        tui/ (Rust/Ratatui)  ─ optional dashboard; reads the same JSON records,
                               shells back out to `e2b-box` for actions.
```

**Why bash + Node + Rust:** E2B's SDK is **JavaScript-only** (no official Rust SDK),
so every sandbox call lives in `src/*.js` — that's the data plane. Bash (`bin/`) is
the control plane herdr actually invokes: it resolves a Node ≥22 and the `e2b` CLI
onto PATH (herdr itself may run on an older Node), handles TTY quirks, renders the
spinner, and runs the interactive shell. The Rust TUI is an optional dashboard that
reads the same state and delegates actions back to `e2b-box`.

## The core flow — `e2b-box open`

1. **herdr** invokes the `open` action/pane → `bin/e2b-box open`.
2. `e2b-box` resolves the worktree (from `$PWD`, or `HERDR_PLUGIN_CONTEXT_JSON`'s
   focused-pane cwd) and computes the **box key** = `<folder>-<sha8(abs path)>`.
3. **Optimistic connect** (only with a TTY): if a `ready` record already has a
   sandbox id, attach immediately via `e2b sandbox connect` — the connect attempt is
   itself the liveness check; a fast failure falls through to (4).
4. Otherwise `provision_from_cwd` launches `src/provision.js` (detached, logging to
   the record's `.log`) with `op=ensure`:
   - reconnect to the tracked sandbox (auto-resumes a paused one), **or** create a
     fresh one on `NotFoundError` (a transient error rethrows — never a second box);
   - upload the worktree **only for a fresh box** (`uploadSnapshot`, git-aware);
   - `git init` + shell personalization; write `status: ready` + preview URL.
5. `spin_until_ready` polls the record (spinner on a TTY; quiet when headless) until
   `ready` / `failed` / timeout.
6. `connect_shell` prints the box details and `e2b sandbox connect <id>`. On exit it
   offers **[p]ull / [k]ill / [L]eave**. Headless callers get instructions and exit
   (never a bare local shell).

`worktree.removed` (herdr event) → `bin/teardown-worktree` → `src/kill.js` (kills the
box; keeps the record if the kill fails, so nothing billable is silently orphaned).

## Component reference

### Control plane — `bin/`
| File | Responsibility |
| --- | --- |
| `e2b-box` | The CLI. Subcommands `open/up/shell/status/list/url/logs/sync/pull/kill`. Key derivation, optimistic connect, `spin_until_ready`, `connect_shell`, on-close prompt, `pull` safety gate. |
| `e2b-dash` | Launcher for the Rust dashboard: resolves the prebuilt/built binary, seeds the theme, guards on a TTY, execs it. |
| `teardown-worktree` | `worktree.removed` handler — kills the box for the removed path (matched by stored `worktreePath`). |
| `lib/paths.sh` | Shared helpers: state-dir resolution, `e2b_node` (find Node ≥22), `ensure_e2b_path`/`ensure_e2b_key`, `sdk_kill`, `box_key`. |

### Data plane — `src/` (ESM, uses `e2b` + `@iarna/toml`)
| File | Responsibility |
| --- | --- |
| `provision.js` | The worker. `ensure` (reconnect-or-create) / `sync` (ensure + always upload). Single source of truth for sandbox liveness. Persists the resolved template. |
| `upload.js` | `uploadSnapshot` — git-aware file selection (`git ls-files --cached --others --exclude-standard`, honoring `.gitignore`), additive, symlinks skipped, batched `sandbox.files.write`. |
| `download.js` | `pull` — reverse of upload. **Path-safety guards** (`relIsUnsafe`, `safeDest`) so a write can never escape the worktree. Only writes files that differ; reports each. |
| `kill.js` | `Sandbox.kill` (bounded), idempotent — "already gone" vs "killed". |
| `store.js` | The record model: atomic (temp+rename) shallow-merge `writeRecord`, `readRecord`, `listRecords`. Defines `BOXES_DIR`. |
| `config.js` | `loadConfig` (TOML over defaults, `posInt`-clamped), `resolveTemplate` (per-branch rules), `resolveLifecycle` (auto_pause → SDK lifecycle). |
| `shared.js` | `requireApiKey`, best-effort `notify` (herdr desktop notification). |
| `resolve-key.js` / `resolve-theme.js` | Tiny helpers the bash layer calls to print the key / theme (toml-only, run on any Node). |

### Dashboard — `tui/src/` (Rust/Ratatui, optional)
`main.rs` (app + event loop + draw), `state.rs` (record loading + shell-quoting),
`theme.rs` (palette presets), `actions.rs` (verbs → `e2b-box` commands). Shipped as
committed prebuilt binaries; source build is the fallback.

## State model — one JSON record per box

`$STATE_DIR/boxes/<key>.json` (+ `<key>.log`), where `STATE_DIR` resolves the same
way in `store.js`, `paths.sh`, and the TUI: `HERDR_PLUGIN_STATE_DIR` →
`HERDR_E2B_STATE_DIR` → XDG. The record is the contract between the writer
(`provision.js`), the reader (`e2b-box` spinner / `status` / `list`), and the
dashboard. Key fields: `key`, `label`, `status` (`provisioning`/`ready`/`failed`),
`step`, `sandboxId`, `template`, `url`, `projectPath`, `worktreePath`, `files`.
Writes are atomic so a concurrent poll never reads a half-written file.

## Invariants worth checking in review

- **No orphaned billable boxes.** A failed kill keeps the record (retryable);
  `provision_from_cwd` carries `sandboxId` (and `template`) across its wholesale
  record rewrite; a transient reconnect error never creates a second box.
- **`pull` never escapes the worktree.** `relIsUnsafe` (traversal/absolute) +
  `safeDest` (won't follow a dest symlink; realpath-parent must stay within the
  root). Covered by `test/download.test.js`.
- **`pull` never silently clobbers.** Dirty/non-git tree → prompt (interactive) or
  abort (headless) unless `--force`. Covered by `test/cli.test.sh`.
- **Upload honors git/.gitignore.** Inside a repo it always trusts git (even an empty
  selection) — never FS-walks and leaks ignored files; the `ignore` list is an extra
  filter (keeps `.env` out even if tracked).
- **Liveness is reconciled before use.** Headless `open`/`shell` route through
  `ensure` (SDK reconnect/recreate) rather than trusting a possibly-stale `ready`.
- **Node/CLI resolution.** herdr may run on Node < 22; `e2b_node`/`ensure_e2b_path`
  find a ≥22 Node and the `e2b` CLI before any SDK/CLI call.

## Where to look for X

- *"Is a box ever leaked?"* → `bin/e2b-box` (`kill`, `provision_from_cwd`),
  `src/provision.js` (reconnect/create branch), `src/kill.js`, `bin/teardown-worktree`.
- *"Can pull damage local files?"* → `src/download.js` (`safeDest`/`relIsUnsafe`) +
  `bin/e2b-box` `pull` case.
- *"What gets uploaded?"* → `src/upload.js` (`gitFiles`, `isIgnored`).
- *"Sandbox lifecycle / pause / template"* → `src/config.js`
  (`resolveLifecycle`/`resolveTemplate`) + `src/provision.js`.
- *"How do the CLI, worker, and TUI agree on state?"* → `src/store.js` +
  the `STATE_DIR` resolution note above.

## Tests

`npm test` is fully offline (no E2B, no key): `node --test test/*.test.js` covers the
pure logic (config resolution, pull path guards); `test/cli.test.sh` lints every
script (`bash -n` / `node --check`) and asserts CLI exit-code behavior. Live E2B
round-trips are verified by hand. CI runs this on Ubuntu + macOS × Node 22/24.
