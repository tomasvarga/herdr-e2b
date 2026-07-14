// Kill an E2B sandbox via the SDK, so the `e2b` CLI is only ever needed for the
// interactive shell (sandbox connect). Best-effort: a box that's already gone is
// treated as success. Usage: node kill.js <sandboxId>
import { Sandbox } from "e2b"

import { loadConfig } from "./config.js"
import { requireApiKey } from "./shared.js"

const sid = process.argv[2]
if (!sid) process.exit(0)

const apiKey = requireApiKey(loadConfig())
try {
  // Bound the request so a teardown hook can't hang on a flaky network.
  await Sandbox.kill(sid, { apiKey, requestTimeoutMs: 15000 })
  console.log(`killed ${sid}`)
} catch (e) {
  const msg = (e && e.message) || String(e)
  // Already gone (idle-timed-out / never existed) — nothing to do.
  if (/not\s*found|404/i.test(msg)) {
    console.log(`box ${sid} already gone`)
    process.exit(0)
  }
  console.error(`kill ${sid} failed: ${msg}`)
  process.exit(1)
}
