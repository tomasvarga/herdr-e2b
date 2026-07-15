// Pull the sandbox's project files back down into the local folder (reverse of the
// upload). git-aware in the sandbox (tracked + untracked, honors .gitignore), so
// build output/node_modules don't come back. Writes files in place; review the
// result with your local `git diff`.
//
// Usage: node download.js '{"key":"...","destRoot":"/abs/local/folder"}'
import { writeFile, readFile, mkdir, appendFile, lstat, realpath } from "node:fs/promises"
import path from "node:path"
import { posix } from "node:path"
import { Sandbox } from "e2b"

import { loadConfig } from "./config.js"
import { requireApiKey } from "./shared.js"
import { readRecord, logPath } from "./store.js"

const input = JSON.parse(process.argv[2] || "{}")
const { key, destRoot } = input
if (!key || !destRoot) {
  console.error("download: missing key/destRoot")
  process.exit(2)
}

const cfg = loadConfig()

async function log(msg) {
  try {
    await appendFile(logPath(key), `[${new Date().toISOString()}] ${msg}\n`)
  } catch {
    // best effort
  }
}

function isIgnored(rel, ignore) {
  const segs = rel.split("/")
  return ignore.some((p) => rel === p || rel.startsWith(`${p}/`) || segs.includes(p))
}

async function main() {
  const apiKey = requireApiKey(cfg)
  const rec = await readRecord(key)
  if (!rec?.sandboxId) {
    console.error(`no sandbox for '${key}'`)
    process.exit(1)
  }
  const projectPath = rec.projectPath || "/home/user/project"
  const sandbox = await Sandbox.connect(rec.sandboxId, { apiKey, timeoutMs: cfg.sandboxTimeoutMs })

  // List the sandbox's files (git-aware; fall back to find for a non-repo sandbox
  // dir). NUL-delimited so filenames with spaces/newlines survive (matches upload).
  const listed = await sandbox.commands.run(
    `cd '${projectPath}' && ` +
      "(git ls-files -z --cached --others --exclude-standard 2>/dev/null " +
      "|| find . -type f -not -path './.git/*' -printf '%P\\0')",
  )
  let files = listed.stdout
    .split("\0")
    .filter(Boolean)
    .filter((f) => !f.endsWith("/"))
    .filter((rel) => !isIgnored(rel, cfg.ignore))

  // Never write outside the worktree. Reject traversal, refuse to follow a
  // symlink at the destination, and verify the (real) parent dir stays inside
  // the worktree root — so a pre-existing local symlink can't redirect a write.
  const rootReal = await realpath(destRoot)
  async function safeDest(rel) {
    if (path.isAbsolute(rel) || rel.split("/").includes("..")) return null
    const dest = path.join(destRoot, rel)
    try {
      if ((await lstat(dest)).isSymbolicLink()) return null // don't follow it
    } catch {
      // doesn't exist — fine
    }
    await mkdir(path.dirname(dest), { recursive: true })
    const parentReal = await realpath(path.dirname(dest))
    if (parentReal !== rootReal && !parentReal.startsWith(rootReal + path.sep)) return null
    return dest
  }

  // Classify each file against the local copy: new / overwritten / unchanged.
  // Only write what actually differs (so unchanged files aren't touched), and
  // report exactly what changed — the "message in case of overwrites".
  const added = []
  const overwritten = []
  const skipped = []
  let unchanged = 0
  const batchSize = cfg.batchSize > 0 ? cfg.batchSize : 40
  for (let i = 0; i < files.length; i += batchSize) {
    const batch = files.slice(i, i + batchSize)
    await Promise.all(
      batch.map(async (rel) => {
        const dest = await safeDest(rel)
        if (!dest) {
          skipped.push(rel)
          return // unsafe path (traversal / symlink) — never write it
        }
        const data = Buffer.from(await sandbox.files.read(posix.join(projectPath, rel), { format: "bytes" }))
        let local = null
        try {
          local = await readFile(dest)
        } catch {
          local = null // doesn't exist locally
        }
        if (local === null) {
          added.push(rel)
        } else if (!local.equals(data)) {
          overwritten.push(rel)
        } else {
          unchanged += 1
          return // identical — leave it alone
        }
        await writeFile(dest, data)
      }),
    )
  }

  added.sort()
  overwritten.sort()
  skipped.sort()
  for (const f of added) console.log(`  + ${f}  (new)`)
  for (const f of overwritten) console.log(`  ~ ${f}  (overwrote local)`)
  for (const f of skipped) console.log(`  ! ${f}  (skipped — unsafe path/symlink)`)
  const changed = added.length + overwritten.length
  console.log(
    changed === 0
      ? `nothing to pull — local already matches the sandbox (${unchanged} files)${skipped.length ? `, ${skipped.length} skipped` : ""}`
      : `pulled ${changed} file(s): ${added.length} new, ${overwritten.length} overwritten, ${unchanged} unchanged${skipped.length ? `, ${skipped.length} skipped` : ""}`,
  )
  await log(`pull: ${added.length} new, ${overwritten.length} overwritten, ${unchanged} unchanged, ${skipped.length} skipped → ${destRoot}`)
}

main().catch((err) => {
  console.error((err && err.message) || String(err))
  process.exit(1)
})
