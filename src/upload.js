import { readFile, readdir, lstat, realpath } from "node:fs/promises"
import { execFile } from "node:child_process"
import path from "node:path"
import { posix } from "node:path"

import { isIgnored } from "./shared.js"

/**
 * Upload the local worktree into the sandbox project directory. This is additive
 * (a re-sync writes current files but does NOT delete sandbox files you removed
 * locally) — it's a snapshot copy, not a destructive mirror.
 *
 * File selection honors git: `git ls-files --cached --others --exclude-standard`
 * gives exactly what git sees — tracked files (including your uncommitted edits)
 * plus new untracked files, while respecting `.gitignore`. So build output,
 * caches, coverage, etc. don't get uploaded. Falls back to a filesystem walk
 * (with the ignore list) ONLY when the worktree isn't a git repo — inside a repo
 * we always trust git, even when the selection is empty, so a repo whose files
 * are all git-ignored uploads nothing rather than leaking ignored files.
 *
 * The ignore list is applied on top of both, so entries like `.env` stay out
 * even if a repo happens to track them.
 */
export async function uploadSnapshot({
  sandbox,
  localRoot,
  remoteRoot,
  ignore,
  batchSize = 40,
  onProgress,
}) {
  const gitList = await gitFiles(localRoot) // null ⇒ not a git repo
  const viaGit = gitList !== null
  let files
  if (viaGit) {
    // Drop directory/submodule boundary entries git emits for nested untracked
    // repos (e.g. "sub/") — they're not files and carry no content here.
    files = gitList.filter((p) => !p.endsWith("/"))
  } else {
    // Not a git repo → walk the folder directly (ignore list is the only filter).
    const rootReal = await realpath(localRoot)
    files = await collect(localRoot, localRoot, ignore, { rootReal, seen: new Set() })
  }
  files = files.filter((rel) => !isIgnored(rel, ignore))

  let done = 0
  for (const batch of chunk(files, batchSize)) {
    const entries = []
    for (const rel of batch) {
      const abs = path.join(localRoot, rel)
      let st
      try {
        st = await lstat(abs)
      } catch {
        continue // listed but gone (e.g. race) — skip
      }
      if (!st.isFile()) continue // skip dirs, symlinks, submodule gitlinks
      entries.push({ path: posix.join(remoteRoot, rel), data: await readFileAsArrayBuffer(abs) })
    }
    if (entries.length) await sandbox.files.write(entries)
    done += entries.length
    if (onProgress) await onProgress(done, files.length)
  }
  return { count: done, viaGit }
}

/**
 * git-tracked + untracked-but-not-ignored files under `root` (relative, posix),
 * or null if not a repo. The trailing `-- .` scopes the listing to `root` — so
 * when `root` is a subfolder of a larger repo (e.g. a loose folder inside a
 * mono-checkout), we upload only that folder, not the entire enclosing repo.
 */
function gitFiles(root) {
  return new Promise((resolve) => {
    execFile(
      "git",
      ["-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "."],
      { maxBuffer: 256 * 1024 * 1024 },
      (err, stdout) => {
        if (err) return resolve(null)
        resolve(
          stdout
            .split("\0")
            .filter(Boolean)
            .map((p) => p.split(path.sep).join("/")),
        )
      },
    )
  })
}

async function collect(dir, root, ignore, state) {
  const dirReal = await realpath(dir)
  if (state.seen.has(dirReal)) return [] // symlink cycle guard
  state.seen.add(dirReal)

  const out = []
  for (const ent of await readdir(dir, { withFileTypes: true })) {
    const abs = path.join(dir, ent.name)
    const rel = path.relative(root, abs).split(path.sep).join("/")
    if (isIgnored(rel, ignore)) continue

    const st = await lstat(abs)
    if (st.isSymbolicLink()) continue
    if (st.isDirectory()) {
      out.push(...(await collect(abs, root, ignore, state)))
      continue
    }
    if (st.isFile()) out.push(rel)
  }
  return out
}

function chunk(items, size) {
  const out = []
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size))
  return out
}

async function readFileAsArrayBuffer(abs) {
  const b = await readFile(abs)
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength)
}
