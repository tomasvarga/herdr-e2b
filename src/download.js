// Pull the box's project files back down into the local folder (reverse of the
// upload). git-aware in the box (tracked + untracked, honors .gitignore), so
// build output/node_modules don't come back. Writes files in place; review the
// result with your local `git diff`.
//
// Usage: node download.js '{"key":"...","destRoot":"/abs/local/folder"}'
import { writeFile, readFile, mkdir, appendFile } from "node:fs/promises"
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
    console.error(`no box for '${key}'`)
    process.exit(1)
  }
  const projectPath = rec.projectPath || "/home/user/project"
  const sandbox = await Sandbox.connect(rec.sandboxId, { apiKey, timeoutMs: cfg.sandboxTimeoutMs })

  // List the box's files (git-aware; fall back to find for a non-repo box dir).
  const listed = await sandbox.commands.run(
    `cd '${projectPath}' && ` +
      "(git ls-files --cached --others --exclude-standard 2>/dev/null " +
      "|| (find . -type f -not -path './.git/*' | sed 's|^\\./||'))",
  )
  let files = listed.stdout
    .split("\n")
    .map((s) => s.replace(/\r$/, "").trim())
    .filter(Boolean)
    .filter((f) => !f.endsWith("/"))
    .filter((rel) => !isIgnored(rel, cfg.ignore))

  // Classify each file against the local copy: new / overwritten / unchanged.
  // Only write what actually differs (so unchanged files aren't touched), and
  // report exactly what changed — the "message in case of overwrites".
  const added = []
  const overwritten = []
  let unchanged = 0
  const batchSize = cfg.batchSize || 40
  for (let i = 0; i < files.length; i += batchSize) {
    const batch = files.slice(i, i + batchSize)
    await Promise.all(
      batch.map(async (rel) => {
        const data = Buffer.from(await sandbox.files.read(posix.join(projectPath, rel), { format: "bytes" }))
        const dest = path.join(destRoot, rel)
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
        await mkdir(path.dirname(dest), { recursive: true })
        await writeFile(dest, data)
      }),
    )
  }

  added.sort()
  overwritten.sort()
  for (const f of added) console.log(`  + ${f}  (new)`)
  for (const f of overwritten) console.log(`  ~ ${f}  (overwrote local)`)
  const changed = added.length + overwritten.length
  console.log(
    changed === 0
      ? `nothing to pull — local already matches the box (${unchanged} files)`
      : `pulled ${changed} file(s): ${added.length} new, ${overwritten.length} overwritten, ${unchanged} unchanged`,
  )
  await log(`pull: ${added.length} new, ${overwritten.length} overwritten, ${unchanged} unchanged → ${destRoot}`)
}

main().catch((err) => {
  console.error((err && err.message) || String(err))
  process.exit(1)
})
