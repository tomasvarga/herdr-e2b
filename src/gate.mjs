// Decide whether a worktree's branch should auto-provision a box, per config
// [trigger]. Exit 0 = provision, exit 1 = skip. Used by bin/mirror-worktree so
// the bash hook and the SDK share one config source.
//
// Usage: node gate.mjs "<branch>"
import { loadConfig } from "./config.mjs"

const branch = process.argv[2] || ""
const cfg = loadConfig()

let ok = false
if (cfg.triggerMode === "all") {
  ok = true
} else if (cfg.triggerMode === "manual") {
  ok = false
} else {
  // "marked": branch_pattern (regex) wins over branch_prefix.
  if (cfg.branchPattern) {
    try {
      ok = new RegExp(cfg.branchPattern).test(branch)
    } catch {
      ok = false
    }
  } else {
    ok = branch.startsWith(cfg.branchPrefix)
  }
}

process.exit(ok ? 0 : 1)
