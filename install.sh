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

chmod +x bin/e2b-box bin/mirror-worktree bin/teardown-worktree 2>/dev/null || true

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
ln -sf "$DIR/bin/e2b-box" "$BIN/e2b-box"
echo "herdr-e2b: linked e2b-box -> $BIN/e2b-box"

command -v e2b >/dev/null 2>&1 || echo "  ! e2b CLI not found — 'npm i -g @e2b/cli' (needed for the box shell)"

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

echo "herdr-e2b: done. Bind prefix+e to plugin.herdr-e2b.open in your herdr config."
