# Changelog

All notable changes to herdr-e2b are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-07-18

### Fixed
- On-close `[p]ull` now guards a dirty / non-git tree with the same confirm as
  `e2b-box pull` (shared `pull_risk` helper) — no more unprompted overwrite of
  uncommitted local work after a sandbox session.
- Headless `open` / `shell` no longer exits non-zero when the `e2b` CLI is absent
  but the sandbox was successfully provisioned (exits 0 with attach instructions;
  interactive callers still get a non-zero "can't attach" exit).
- `download.js`'s script-entry guard realpaths both sides, so a symlinked
  invocation path can't silently turn a `pull` into a no-op that reports success.
- The boot/sync spinner indexes an array of frames (locale-safe) instead of a
  byte-offset substring that garbled the braille glyphs under non-UTF-8 locales.

### Changed
- `isIgnored` is defined once in `shared.js` and imported by both `upload.js` and
  `download.js` (was duplicated), so upload and pull can't drift apart.

## [0.1.0] - 2026-07-16

First public release.

### Added
- Snapshot-upload a git worktree (uncommitted changes and all) into a fresh E2B
  cloud sandbox on demand — no push, no clone. File selection follows git
  (`git ls-files --cached --others --exclude-standard`), honoring `.gitignore`,
  with an extra `[upload].ignore` safety filter (keeps `.env` out even if tracked).
- `e2b-box` CLI: `open`, `up`, `shell`, `status`, `list`, `url`, `logs`, `sync`,
  `pull [--force]`, `kill`.
- herdr integration: actions (`open` / `sync` / `pull` / `status` / `kill` /
  `dashboard`), a zoomed sandbox pane, and a `worktree.removed` → teardown event
  that kills the box (no orphaned, billable sandboxes).
- Dashboard TUI (Ratatui) — a live board of every tracked box with per-box
  open/sync/pull/kill and theming; shipped as prebuilt binaries (macOS universal,
  Linux x64/arm64) so no toolchain is required.
- One sandbox per worktree, keyed by folder path; `auto_pause` (pause instead of
  kill at the idle timeout — free-tier friendly); per-branch template rules with
  fallback to `base`.

### Security
- `pull` writes only inside the worktree — rejects path traversal and absolute
  paths, refuses to follow a destination symlink, and verifies the real parent
  directory stays within the worktree root.
- `pull` aborts (rather than silently overwriting) on a dirty git tree or a
  non-git folder when run non-interactively, unless `--force` is passed.
- Failed sandbox kills keep their record so a billable box is never silently
  orphaned.

[Unreleased]: https://github.com/tomasvarga/herdr-e2b/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/tomasvarga/herdr-e2b/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tomasvarga/herdr-e2b/releases/tag/v0.1.0
