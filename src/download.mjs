// Pull the box's project files back down into the local folder (reverse of the
// upload). git-aware in the box (tracked + untracked, honors .gitignore), so
// build output/node_modules don't come back. Writes files in place; review the
// result with your local `git diff`.
//
// Usage: node download.mjs '{"key":"...","destRoot":"/abs/local/folder"}'
import { writeFile, mkdir, appendFile } from "node:fs/promises"
import path from "node:path"
import { posix } from "node:path"
import { Sandbox } from "e2b"

import { loadConfig } from "./config.mjs"
import { requireApiKey } from "./shared.mjs"
import { readRecord, logPath } from "./store.mjs"

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

  let done = 0
  const batchSize = cfg.batchSize || 40
  for (let i = 0; i < files.length; i += batchSize) {
    const batch = files.slice(i, i + batchSize)
    await Promise.all(
      batch.map(async (rel) => {
        const data = await sandbox.files.read(posix.join(projectPath, rel), { format: "bytes" })
        const dest = path.join(destRoot, rel)
        await mkdir(path.dirname(dest), { recursive: true })
        await writeFile(dest, Buffer.from(data))
      }),
    )
    done += batch.length
  }

  await log(`pulled ${done} files from box → ${destRoot}`)
  console.log(JSON.stringify({ ok: true, files: done }))
}

main().catch((err) => {
  console.error((err && err.message) || String(err))
  process.exit(1)
})
