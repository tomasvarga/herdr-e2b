# SSH over websocat — experiment

Status: **experiment, not wired into the plugin.** The default connect path stays
`e2b sandbox connect` (optimistic connect against a live box). This directory just
captures the SSH-tunnel spike so we can revisit it.

## Why

E2B sandboxes have no native SSH. They run `envd`, a PTY exposed over a websocket,
and the only externally reachable ports are WSS at `<port>-<id>.e2b.app`. Real
OpenSSH can still ride on top by tunnelling through a [websocat](https://github.com/vi/websocat)
WS↔TCP bridge:

- **box side:** `websocat -b ws-l:0.0.0.0:8022 tcp:127.0.0.1:22`
- **client side:** `ssh -o ProxyCommand='websocat -b wss://8022-<id>.e2b.app' user@sandbox`

## Measured latency (keystroke echo RTT)

PTY harness: send one char, measure the echo round-trip, drop warmup, report median.

| transport                    | median | range        | feel      |
| ---------------------------- | -----: | ------------ | --------- |
| SSH over websocat            | 211 ms | 173–246 ms   | steady    |
| `e2b sandbox connect` (envd) | 316 ms | 311–790 ms   | jittery   |

SSH is ~33% faster per keystroke and much steadier — noticeable while typing.
On top of that, real SSH unlocks `ControlMaster`/`ControlPersist` for instant
reconnects and `rsync -e ssh` for faster tree sync.

## Try it

```
bash experiments/ssh-over-websocat/try-ssh.sh
```

Provisions a throwaway `base` box, installs `sshd` + the websocat bridge, drops you
into the SSH shell, and kills the box on `exit`. It prints `box: <id>` — connect to
the same box the old way in another terminal to compare:

```
e2b sandbox connect <id>
```

Requires `websocat` and `ssh` on PATH, plus an E2B API key configured for the plugin.

## What a production version would need (deferred)

- A `herdr-e2b-ssh` custom template with websocat baked in (sshd already ships in `base`).
- Vendored websocat **client** binaries in `bin/lib/` per platform (like the prebuilt dashboard binaries), so there's no `brew install` dependency.
- Provisioning step: write the pubkey + start sshd/bridge on boot.
- An opt-in `e2b-box ssh` transport using `ProxyCommand` + `ControlMaster=auto ControlPersist=10m`.
- `rsync -e ssh` for sync/pull.
