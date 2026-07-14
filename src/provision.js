// Worker: ensure an E2B sandbox exists for a worktree (reconnect to the tracked
// one, or create a fresh one), and optionally mirror the local tree into it.
// Launched by bin/e2b-box. Writes live progress into the box record so the pane
// can render a spinner.
//
// Usage: node provision.js '<json>'
//   json: { key, branch, worktreePath, workspaceId, op? }
//   op:  "ensure" (default) — reconnect-or-create; upload only a FRESH box, so
//                             reconnecting never clobbers in-box edits.
//        "sync"             — ensure, then always re-upload the local tree.
import { appendFile } from "node:fs/promises"
import { Sandbox, NotFoundError } from "e2b"

import { loadConfig, resolveTemplate, resolveLifecycle } from "./config.js"
import { requireApiKey, notify } from "./shared.js"
import { writeRecord, readRecord, logPath } from "./store.js"
import { uploadSnapshot } from "./upload.js"

const input = JSON.parse(process.argv[2] || "{}")
const { key, branch, worktreePath, workspaceId } = input
const op = input.op === "sync" ? "sync" : "ensure"
if (!key || !worktreePath) {
  console.error("provision: missing key/worktreePath")
  process.exit(2)
}

const cfg = loadConfig()
// Where the worktree lands inside the box. Defaults to /home/user/project
// (config [sandbox].project_path); falls back to /home/user/<key> only if that
// is explicitly blanked.
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

  let sandbox = null
  let created = false
  const prev = await readRecord(key)
  if (prev?.sandboxId) {
    notify("E2B", `${op === "sync" ? "Syncing" : "Reconnecting"} box for ${branch || key}…`)
    await step("reconnecting to box")
    try {
      // connect() auto-resumes a paused box (from auto_pause) on its own.
      sandbox = await Sandbox.connect(prev.sandboxId, {
        apiKey,
        timeoutMs: cfg.sandboxTimeoutMs,
      })
    } catch (e) {
      if (e instanceof NotFoundError) {
        // The box is genuinely gone (idle-timed-out / killed) — make a fresh one.
        await log(`box ${prev.sandboxId} not found (${(e && e.message) || e}); creating a fresh one`)
        sandbox = null
      } else {
        // Transient (network / rate-limit / auth). Do NOT create a second box
        // behind the old one (it may still be alive and billable) — surface the
        // error and leave the record intact so the next open retries the reconnect.
        throw e
      }
    }
  }

  if (!sandbox) {
    notify("E2B", `Booting box for ${branch || key}…`)
    const template = resolveTemplate(branch, cfg)
    await step(`creating sandbox (${template})`)
    const opts = {
      apiKey,
      timeoutMs: cfg.sandboxTimeoutMs,
      metadata,
      lifecycle: resolveLifecycle(cfg),
    }
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
    created = true
    await writeRecord(key, { sandboxId: sandbox.sandboxId })
  }

  await step("preparing project dir", { sandboxId: sandbox.sandboxId })
  await sandbox.commands.run(`mkdir -p '${projectPath}'`)

  // Upload the local tree only for a FRESH box (it's empty) or an explicit sync.
  // Reconnecting to an existing box must NOT overwrite in-box edits — pull them
  // down first (`e2b-box pull`) if you want them locally.
  let files = prev?.files ?? 0
  if (created || op === "sync") {
    const { count, viaGit } = await uploadSnapshot({
      sandbox,
      localRoot: worktreePath,
      remoteRoot: projectPath,
      ignore: cfg.ignore,
      batchSize: cfg.batchSize,
      onProgress: (done, total) => step(`uploading ${done}/${total} files`),
    })
    files = count
    await log(`uploaded ${count} files (${viaGit ? "git-tracked, .gitignore honored" : "filesystem walk"})`)

    await step("initializing git")
    const safeBranch = (branch || "main").replace(/'/g, "") // git needs a real ref
    await sandbox.commands.run(
      `cd '${projectPath}' && ` +
        `(git rev-parse --git-dir >/dev/null 2>&1 || git init -b '${safeBranch}') && ` +
        `git add -A >/dev/null 2>&1 || true`,
    )
  }

  // Shell personalization is one-time box setup — a cyan [e2b:label] prompt,
  // HERDR_E2B markers, and landing in the project dir on connect. Only a fresh
  // box needs it (a reconnected box already has it).
  if (created) {
    await step("personalizing shell")
    const label = key.replace(/'/g, "") // prompt shows the folder/project name
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
  }

  const url = `https://${sandbox.getHost(cfg.serverPort)}`
  await writeRecord(key, {
    status: "ready",
    step: "ready",
    sandboxId: sandbox.sandboxId,
    url,
    projectPath: projectPath,
    files,
  })
  await log(`ready · ${sandbox.sandboxId} · ${files} files · ${url}`)
  notify("E2B", `Box ready for ${branch || key}`)
  console.log(JSON.stringify({ ok: true, sandboxId: sandbox.sandboxId, url, files }))
}

main().catch(async (err) => {
  const msg = (err && err.message) || String(err)
  await writeRecord(key, { status: "failed", step: msg })
  await log(`FAILED: ${(err && err.stack) || msg}`)
  notify("E2B", `Box failed for ${branch || key}: ${msg}`)
  process.exit(1)
})
