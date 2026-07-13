#!/usr/bin/env bash
# Seed a clean, repeatable demo for the VHS recording:
#  - a fresh sample project at demo/ (its own git repo on main → box key "demo")
#  - a reset of any prior "demo" box record
# Run from the plugin root (the tape does this in a hidden block).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO="$ROOT/demo"
BOXES="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/herdr-e2b/boxes"

# Clear any previous demo box record (old box, if any, idle-times out on E2B).
rm -f "$BOXES/demo.json" "$BOXES/demo.log" 2>/dev/null || true

# Fresh sample project — a tiny CLI app.
rm -rf "$DEMO"
mkdir -p "$DEMO/src"
cat > "$DEMO/README.md" <<'EOF'
# weather-cli

A tiny sample app. herdr-e2b mirrors this worktree into an E2B cloud box,
honoring .gitignore (so node_modules never gets uploaded).
EOF
cat > "$DEMO/package.json" <<'EOF'
{
  "name": "weather-cli",
  "version": "1.0.0",
  "bin": { "weather": "src/index.js" }
}
EOF
cat > "$DEMO/src/index.js" <<'EOF'
#!/usr/bin/env node
console.log("weather-cli — running inside an E2B box")
EOF
printf 'node_modules/\ndist/\n' > "$DEMO/.gitignore"
# gitignored junk that must NOT be uploaded (proves .gitignore is honored).
mkdir -p "$DEMO/node_modules/left-pad"
echo "module.exports = () => {}" > "$DEMO/node_modules/left-pad/index.js"

git -C "$DEMO" init -q -b main
git -C "$DEMO" -c user.email=demo@e2b.dev -c user.name=demo add -A
git -C "$DEMO" -c user.email=demo@e2b.dev -c user.name=demo commit -qm "init weather-cli"
