// Worker: spawn (or reconnect to) an E2B sandbox for a worktree and mirror the
// tree into it. Launched detached by bin/e2b-box.
// Writes live progress into the box record so the pane can render a spinner.
//
// Usage: node provision.mjs '<json>'
//   json: { key, branch, worktreePath, workspaceId, reuse? }
import { appendFile } from "node:fs/promises"
import { Sandbox } from "e2b"

import { loadConfig, resolveTemplate } from "./config.mjs"
import { requireApiKey, notify } from "./shared.mjs"
import { writeRecord, readRecord, logPath } from "./store.mjs"
import { uploadSnapshot } from "./upload.mjs"

const input = JSON.parse(process.argv[2] || "{}")
const { key, branch, worktreePath, workspaceId, reuse } = input
if (!key || !worktreePath) {
  console.error("provision: missing key/worktreePath")
  process.exit(2)
}

const cfg = loadConfig()
// Where the worktree lands inside the box. Defaults to /home/user/<box-key> so
// `pwd` in the box reflects what you uploaded (not a generic "project" dir).
const projectPath = cfg.projectPath || `/home/user/${key}`
// Metadata is stored on E2B's servers — keep it to non-sensitive identifiers.
// No absolute local path here (it would leak your username / machine layout);
// the full path stays only in the local record on your machine.
const metadata = {
  app: "herdr-e2b",
  herdrWorktreeKey: key,
  herdrBranch: branch || "",
}

async function log(msg) {
  try {
    await appendFile(logPath(key), `[${new Date().toISOString()}] ${msg}\n`)
  } catch {
    // best effort
  }
}

async function step(label, extra = {}) {
  await writeRecord(key, {
    status: "provisioning",
    step: label,
    branch,
    worktreePath,
    workspaceId,
    ...extra,
  })
  await log(label)
}

async function main() {
  const apiKey = requireApiKey(cfg)
  notify("E2B", `${reuse ? "Syncing" : "Booting"} box for ${branch || key}…`)

  let sandbox
  const prev = await readRecord(key)
  if (reuse && prev?.sandboxId) {
    await step("reconnecting to box")
    sandbox = await Sandbox.connect(prev.sandboxId, { apiKey, timeoutMs: cfg.sandboxTimeoutMs })
  } else {
    const template = resolveTemplate(branch, cfg)
    await step(`creating sandbox (${template})`)
    const opts = { apiKey, timeoutMs: cfg.sandboxTimeoutMs, metadata }
    try {
      sandbox = await Sandbox.create(template, opts)
    } catch (e) {
      // If a custom template isn't built yet, don't hard-fail — fall back to base.
      const msg = (e && e.message) || String(e)
      if (template !== "base" && /template|not\s*found|404|does not exist/i.test(msg)) {
        await log(`template '${template}' unavailable (${msg}); falling back to 'base'`)
        notify("E2B", `Template '${template}' not found — using base`)
        await step("creating sandbox (base — fallback)")
        sandbox = await Sandbox.create("base", opts)
      } else {
        throw e
      }
    }
    await writeRecord(key, { sandboxId: sandbox.sandboxId })
  }

  await step("preparing project dir", { sandboxId: sandbox.sandboxId })
  await sandbox.commands.run(`mkdir -p '${projectPath}'`)

  const { count, viaGit } = await uploadSnapshot({
    sandbox,
    localRoot: worktreePath,
    remoteRoot: projectPath,
    ignore: cfg.ignore,
    batchSize: cfg.batchSize,
    onProgress: (done, total) => step(`uploading ${done}/${total} files`),
  })
  await log(`uploaded ${count} files (${viaGit ? "git-tracked, .gitignore honored" : "filesystem walk"})`)

  await step("initializing git")
  const safeBranch = (branch || "main").replace(/'/g, "") // git needs a real ref
  const label = key.replace(/'/g, "") // prompt shows the folder/project name
  await sandbox.commands.run(
    `cd '${projectPath}' && ` +
      `(git rev-parse --git-dir >/dev/null 2>&1 || git init -b '${safeBranch}') && ` +
      `git add -A >/dev/null 2>&1 || true`,
  )

  // Make it obvious you're in the box: a cyan [e2b:branch] prompt, HERDR_E2B
  // env markers, and land in the project dir instead of $HOME on connect.
  await step("personalizing shell")
  const rc =
    "# herdr-e2b\n" +
    "export HERDR_E2B=1\n" +
    `export HERDR_E2B_BRANCH='${label}'\n` +
    `PS1='\\[\\033[1;36m\\][e2b:${label}]\\[\\033[0m\\] \\w \\$ '\n` +
    `cd '${projectPath}' 2>/dev/null || true\n`
  await sandbox.files.write("/home/user/.herdr-e2b.sh", rc)
  await sandbox.commands
    .run(
      'for f in .bashrc .bash_profile .profile; do ' +
        'grep -q herdr-e2b "$HOME/$f" 2>/dev/null || ' +
        "echo '[ -f ~/.herdr-e2b.sh ] && . ~/.herdr-e2b.sh' >> \"$HOME/$f\"; done",
    )
    .catch(() => {})

  const url = `https://${sandbox.getHost(cfg.serverPort)}`
  await writeRecord(key, {
    status: "ready",
    step: "ready",
    sandboxId: sandbox.sandboxId,
    url,
    projectPath: projectPath,
    files: count,
  })
  await log(`ready · ${sandbox.sandboxId} · ${count} files · ${url}`)
  notify("E2B", `Box ready for ${branch || key}`)
  console.log(JSON.stringify({ ok: true, sandboxId: sandbox.sandboxId, url, files: count }))
}

main().catch(async (err) => {
  const msg = (err && err.message) || String(err)
  await writeRecord(key, { status: "failed", step: msg })
  await log(`FAILED: ${(err && err.stack) || msg}`)
  notify("E2B", `Box failed for ${branch || key}: ${msg}`)
  process.exit(1)
})
