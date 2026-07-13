import { spawn } from "node:child_process"

// Resolve the E2B key from env or plugin config ([secrets].e2b_api_key).
// Pass the loaded config so config-dir keys work without touching the env.
export function requireApiKey(cfg) {
  const k = process.env.E2B_API_KEY?.trim() || cfg?.apiKey
  if (!k) {
    throw new Error(
      "No E2B API key. Set [secrets].e2b_api_key in " +
        "~/.config/herdr/plugins/config/herdr-e2b/config.toml, or export E2B_API_KEY. " +
        "Get a key at https://e2b.dev/dashboard.",
    )
  }
  return k
}

/** Best-effort herdr desktop notification; never throws. */
export function notify(title, body) {
  try {
    const p = spawn("herdr", ["notification", "show", title, "--body", body], {
      stdio: "ignore",
      detached: true,
    })
    p.on("error", () => {})
    p.unref()
  } catch {
    // herdr not on PATH — fine.
  }
}
