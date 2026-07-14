#!/usr/bin/env bash
# Build step for `herdr plugin install` (and manual local dev):
# install node deps and link the e2b-box CLI onto PATH.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "herdr-e2b: installing node deps…"
if command -v npm >/dev/null 2>&1; then
  npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 || npm install
else
  echo "  ! npm not found — install Node.js (>=18), then re-run ./install.sh" >&2
fi

chmod +x bin/e2b-box bin/e2b-dash bin/teardown-worktree 2>/dev/null || true

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
ln -sf "$DIR/bin/e2b-box" "$BIN/e2b-box"
echo "herdr-e2b: linked e2b-box -> $BIN/e2b-box"

command -v e2b >/dev/null 2>&1 || echo "  ! e2b CLI not found — 'npm i -g @e2b/cli' (needed for the sandbox shell)"

# Optional dashboard TUI (Rust/Ratatui). Prefer a committed PREBUILT binary so no
# dev tools are needed; else build from source with cargo; else skip. The core
# plugin works without it. The launcher always resolves tui/target/release/e2b-dash.
ln -sf "$DIR/bin/e2b-dash" "$BIN/e2b-dash"
prebuilt=""
case "$(uname -s)" in
  Darwin) prebuilt="e2b-dash-darwin-universal" ;;
  Linux)  case "$(uname -m)" in
            aarch64|arm64) prebuilt="e2b-dash-linux-arm64" ;;
            x86_64)        prebuilt="e2b-dash-linux-x64" ;;
          esac ;;
esac
mkdir -p "$DIR/tui/target/release"
# Clear any stale/wrong-platform binary so we never run a leftover from another
# machine; each branch below re-creates it (or leaves it absent → launcher errors).
rm -f "$DIR/tui/target/release/e2b-dash"
if [ -n "$prebuilt" ] && [ -f "$DIR/tui/prebuilt/$prebuilt" ]; then
  chmod +x "$DIR/tui/prebuilt/$prebuilt" 2>/dev/null || true
  ln -sf "../../prebuilt/$prebuilt" "$DIR/tui/target/release/e2b-dash"
  echo "herdr-e2b: dashboard ready (prebuilt: $prebuilt) — run 'e2b-dash' or open the 'dashboard' pane."
elif command -v cargo >/dev/null 2>&1; then
  echo "herdr-e2b: no prebuilt for this platform — building the dashboard from source (cargo)…"
  (cd "$DIR/tui" && cargo build --release >/dev/null 2>&1) \
    && echo "  built — run 'e2b-dash'." \
    || echo "  ! dashboard build failed (optional) — skipping; 'e2b-dash' will hint how to build."
else
  echo "herdr-e2b: no prebuilt dashboard for $(uname -sm) and Rust not found — skipping (optional)."
  echo "  to enable it: install rustup (https://rustup.rs), then (cd tui && cargo build --release)."
fi

# API key: if we don't already have one (env or config), prompt to save it into
# the plugin config. Interactive only — the `herdr plugin install` build step
# has no TTY, so it skips silently (set the key later). Never clobbers a config.
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/herdr-e2b"
CFG="$CONFIG_DIR/config.toml"
have_key=0
[ -n "${E2B_API_KEY:-}" ] && have_key=1
[ -f "$CFG" ] && grep -q 'e2b_api_key' "$CFG" && have_key=1
if [ "$have_key" -eq 1 ]; then
  echo "herdr-e2b: E2B API key already configured."
elif [ -t 0 ]; then
  printf 'herdr-e2b: paste your E2B API key to save it (blank = skip · https://e2b.dev/dashboard): '
  read -rs E2B_KEY_INPUT; echo
  if [ -n "$E2B_KEY_INPUT" ]; then
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CFG" ]; then
      echo "  $CFG exists — add under a [secrets] section:  e2b_api_key = \"…\""
    else
      printf '[secrets]\ne2b_api_key = "%s"\n' "$E2B_KEY_INPUT" > "$CFG"
      chmod 600 "$CFG"
      echo "  saved key to $CFG"
    fi
  else
    echo "  skipped — set [secrets].e2b_api_key in $CFG later, or export E2B_API_KEY"
  fi
else
  echo "  ! No E2B API key — set [secrets].e2b_api_key in $CFG, or export E2B_API_KEY"
fi

# The e2b SDK needs Node >= 22. herdr may launch under an older node; the plugin
# auto-resolves a newer one (nvm/Homebrew) at runtime, but warn if PATH is old.
if command -v node >/dev/null 2>&1 && ! node -e 'process.exit(+process.versions.node.split(".")[0]>=22?0:1)' 2>/dev/null; then
  echo "  ! Node $(node -v) on PATH is < 22 (e2b SDK needs >=22). The plugin will use a newer node if one is installed; else set HERDR_E2B_NODE=/path/to/node."
fi

# Template recommendation — "base" (the default) is minimal & tight on disk.
echo "herdr-e2b: tip — sandboxes default to the 'base' template (minimal). For real"
echo "  work, build a bigger CUSTOM template (more disk/CPU + your toolchain) and"
echo "  set [sandbox].template in $CFG. Build with 'e2b template build'"
echo "  (https://e2b.dev/docs/sandbox-template) — or ask your coding agent to set"
echo "  one up. Public agent templates (claude, codex, opencode, amp, grok) also work."

echo "herdr-e2b: done. Bind prefix+shift+e (open sandbox) and prefix+shift+d (dashboard) in your herdr config."
