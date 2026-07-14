#!/usr/bin/env bash
# Shared paths for herdr-e2b scripts. Source this from bin/* scripts.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Keep IN SYNC with src/store.js and tui/src/main.rs so the writer, e2b-box, and
# the dashboard all agree on where box records live.
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${HERDR_E2B_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/herdr-e2b}}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/herdr-e2b"
BOXES_DIR="$STATE_DIR/boxes"
mkdir -p "$BOXES_DIR" 2>/dev/null || true

# Sanitize a string to filesystem/metadata-safe chars.
e2b_key() {
  local raw="$1"
  printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//'
}

# Collision-free box key for an absolute path: "<folder>-<hash8>". The folder
# name keeps records readable; the hash of the full path disambiguates two
# folders that share a basename (which would otherwise collide on one record and
# let removing one kill the other's box). Keep in sync with e2b-box/teardown.
box_key() {
  local p base h
  p="$1"
  base=$(e2b_key "$(basename "$p")")
  h=$(printf '%s' "$p" | shasum -a 256 2>/dev/null | cut -c1-8)
  [ -n "$h" ] || h=$(printf '%s' "$p" | cksum | tr -cd '0-9' | cut -c1-8)
  printf '%s-%s' "${base:-box}" "$h"
}

# Resolve a Node >= 22. The `e2b` SDK require()s an ESM-only chalk, which older
# node (e.g. herdr may launch under v20) can't load — provision.js then dies at
# import. Prefer $HERDR_E2B_NODE, then PATH node if new enough, then newest nvm.
# Prints the node path, or exits non-zero if none is >= 22.
e2b_node() {
  local ok='process.exit(+process.versions.node.split(".")[0]>=22?0:1)'
  if [ -n "${HERDR_E2B_NODE:-}" ] && "$HERDR_E2B_NODE" -e "$ok" 2>/dev/null; then
    printf '%s' "$HERDR_E2B_NODE"; return 0
  fi
  if command -v node >/dev/null 2>&1 && node -e "$ok" 2>/dev/null; then
    command -v node; return 0
  fi
  local d best=""
  for d in "$HOME"/.nvm/versions/node/v*/bin/node /usr/local/bin/node /opt/homebrew/bin/node; do
    [ -x "$d" ] || continue
    if "$d" -e "$ok" 2>/dev/null; then best="$d"; fi
  done
  [ -n "$best" ] && { printf '%s' "$best"; return 0; }
  return 1
}

# Put a Node >= 22 (and the `e2b` CLI beside it) first on PATH, so the CLI is
# found AND runs under a node its SDK supports. herdr may launch under an older
# node whose PATH lacks both — without this, `e2b sandbox connect` isn't found
# (pane exits) or crashes at import. Safe to call repeatedly.
ensure_e2b_path() {
  local n d e
  n=$(e2b_node 2>/dev/null) && d=$(dirname "$n") || d=""
  # Best case: one bin dir has both a good node and e2b (e.g. an nvm version).
  if [ -n "$d" ] && [ -x "$d/e2b" ]; then
    case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH"; export PATH ;; esac
    return 0
  fi
  [ -n "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH"; export PATH ;; esac
  command -v e2b >/dev/null 2>&1 && return 0
  for e in "$HOME"/.nvm/versions/node/v*/bin/e2b /opt/homebrew/bin/e2b /usr/local/bin/e2b; do
    [ -x "$e" ] && { PATH="$(dirname "$e"):$PATH"; export PATH; return 0; }
  done
  return 1
}

# Kill a sandbox via the SDK (node kill.js), not the e2b CLI — so the CLI is only
# needed for the interactive shell. Best-effort; needs a Node >= 22. Returns
# non-zero only if a real kill error occurred (already-gone counts as success).
sdk_kill() {
  local sid="$1" node_bin
  [ -n "$sid" ] || return 0
  node_bin=$(e2b_node) || return 0   # no usable node: skip (nothing we can do)
  "$node_bin" "$PLUGIN_DIR/src/kill.js" "$sid"
}

# Make sure the `e2b` CLI has a key: env first, else the plugin config
# ([secrets].e2b_api_key). Lets the config dir be the single source of truth.
ensure_e2b_key() {
  if [ -z "${E2B_API_KEY:-}" ] && command -v node >/dev/null 2>&1; then
    local k
    k="$(node "$PLUGIN_DIR/src/resolve-key.js" 2>/dev/null || true)"
    [ -n "$k" ] && export E2B_API_KEY="$k"
  fi
}
