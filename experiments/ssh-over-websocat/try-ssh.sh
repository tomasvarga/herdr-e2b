#!/usr/bin/env bash
# Hands-on test of SSH-over-websocat into a real E2B sandbox.
#
# E2B has no native SSH — sandboxes run envd (a PTY over a websocket). This proves
# out real OpenSSH tunnelled through a websocat WS<->TCP bridge, which measured
# ~33% lower keystroke-echo latency than `e2b sandbox connect` (median ~211ms vs
# ~316ms, and far steadier) — see README.md.
#
# It provisions a throwaway `base` box, sets up sshd + the websocat bridge, drops
# you into the SSH shell over the tunnel, and KILLS the box when you `exit`.
#
# Requires: websocat + ssh on PATH, and an E2B API key configured for the plugin.
set -uo pipefail
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

command -v websocat >/dev/null || { echo "need websocat on PATH (brew install websocat)"; exit 1; }
command -v ssh      >/dev/null || { echo "need ssh"; exit 1; }

TMP="$(mktemp -d)"; SID=""
cleanup() {
  echo; echo "── tearing down ──"
  [ -n "$SID" ] && node "$PLUGIN/src/kill.js" "$SID"
  rm -rf "$TMP"
}
trap cleanup EXIT

ssh-keygen -t ed25519 -N "" -f "$TMP/key" -q -C e2b-ssh-try
PUB="$(cat "$TMP/key.pub")"
KEY="$(cd "$PLUGIN" && node src/resolve-key.js)"
[ -n "$KEY" ] || { echo "no E2B API key configured (set [secrets].e2b_api_key or E2B_API_KEY)"; exit 1; }

echo "provisioning a throwaway E2B box + sshd + websocat bridge (~20-40s)…"
read -r SID WSS < <(cd "$PLUGIN" && PUB="$PUB" E2B_API_KEY="$KEY" node --input-type=module -e '
import {Sandbox} from "e2b"
const s = await Sandbox.create("base", {apiKey: process.env.E2B_API_KEY, timeoutMs: 900000})
const setup = [
  "sudo ssh-keygen -A >/dev/null 2>&1",
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh",
  `printf "%s\\n" ${JSON.stringify(process.env.PUB)} > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`,
  "sudo mkdir -p /run/sshd && sudo /usr/sbin/sshd",
  "sudo curl -sSL https://github.com/vi/websocat/releases/download/v1.13.0/websocat.x86_64-unknown-linux-musl -o /usr/local/bin/websocat && sudo chmod +x /usr/local/bin/websocat",
].join(" && ")
await s.commands.run(setup, {timeoutMs: 180000})
await s.commands.run("websocat -b ws-l:0.0.0.0:8022 tcp:127.0.0.1:22", {background: true, timeoutMs: 0})
await new Promise(r => setTimeout(r, 900))
process.stdout.write(s.sandboxId + " wss://" + s.getHost(8022) + "\n")
process.exit(0)
') || true
[ -n "$SID" ] || { echo "provisioning failed"; exit 1; }

echo "box: $SID"
echo "tunnel: $WSS"
echo
echo "→ Dropping you into an SSH shell over the websocat tunnel."
echo "  Type around — this should feel snappier than 'e2b sandbox connect $SID'."
echo "  (Try that in another terminal to compare.)  Type 'exit' to tear it all down."
echo
ssh -o "ProxyCommand=websocat -b $WSS" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -i "$TMP/key" user@sandbox
# (trap cleanup runs on exit → kills the box)
