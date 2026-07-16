#!/usr/bin/env bash
# Offline tests for the e2b-box CLI: lint + exit-code/behavior assertions that
# don't touch E2B (they exercise the paths that return BEFORE any SDK call).
# Run via `npm test` or directly. Requires bash, jq, git, and node >= 22 on PATH.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2B="$ROOT/bin/e2b-box"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

for t in jq git node; do command -v "$t" >/dev/null || { echo "cli.test: '$t' not on PATH"; exit 1; }; done

echo "── lint: bash -n ──"
for f in "$ROOT"/bin/e2b-box "$ROOT"/bin/e2b-dash "$ROOT"/bin/teardown-worktree "$ROOT"/bin/lib/*.sh "$ROOT"/install.sh; do
  if bash -n "$f" 2>/dev/null; then ok "bash -n $(basename "$f")"; else bad "bash -n $(basename "$f")"; fi
done
echo "── lint: node --check ──"
for f in "$ROOT"/src/*.js; do
  if node --check "$f" 2>/dev/null; then ok "node --check $(basename "$f")"; else bad "node --check $(basename "$f")"; fi
done

# Isolated state dir so we never see or touch real box records.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HERDR_PLUGIN_STATE_DIR="$TMP/state"; mkdir -p "$HERDR_PLUGIN_STATE_DIR/boxes"
unset HERDR_PLUGIN_CONTEXT_JSON 2>/dev/null || true

echo "── behavior: no tracked box ──"
out=$(KEY=nobox "$E2B" url 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "no sandbox tracked"; } \
  && ok "url with no box → message + exit 1" || bad "url with no box (rc=$rc, out=$out)"

out=$(KEY=nobox "$E2B" status 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "no sandbox tracked"; } \
  && ok "status with no box → message + exit 0" || bad "status with no box (rc=$rc)"

out=$("$E2B" list 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "no sandboxes"; } \
  && ok "list empty → 'no sandboxes'" || bad "list empty (rc=$rc)"

echo "── behavior: pull safety (dirty tree, non-interactive → abort, no clobber) ──"
REPO="$TMP/repo"; mkdir -p "$REPO"
( cd "$REPO" && git init -q -b main && printf 'v1\n' > f.txt \
  && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -qm init )
# Fake a ready record for this box (KEY override), so pull reaches the safety gate.
printf '{"key":"pullbox","label":"repo","status":"ready","sandboxId":"idummy","url":"https://x","projectPath":"/home/user/project"}\n' \
  > "$HERDR_PLUGIN_STATE_DIR/boxes/pullbox.json"
# Make the tree dirty.
printf 'LOCAL UNCOMMITTED WORK\n' > "$REPO/f.txt"
before="$(cat "$REPO/f.txt")"
out=$(cd "$REPO" && KEY=pullbox "$E2B" pull < /dev/null 2>&1); rc=$?
after="$(cat "$REPO/f.txt")"
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "aborted (non-interactive)" && [ "$before" = "$after" ]; } \
  && ok "pull dirty+non-interactive → aborts, file untouched" \
  || bad "pull dirty+non-interactive (rc=$rc, changed=$([ "$before" = "$after" ] && echo no || echo YES))"

echo
echo "cli.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
