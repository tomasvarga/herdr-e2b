import { readFileSync } from "node:fs"
import path from "node:path"
import os from "node:os"
import TOML from "@iarna/toml"

const CONFIG_DIR = process.env.XDG_CONFIG_HOME
  ? path.join(process.env.XDG_CONFIG_HOME, "herdr/plugins/config/herdr-e2b")
  : path.join(os.homedir(), ".config/herdr/plugins/config/herdr-e2b")

const DEFAULTS = {
  // trigger: how a worktree opts in to auto-provisioning on worktree.created
  triggerMode: "marked", // "manual" | "marked" | "all"
  branchPrefix: "e2b/",
  branchPattern: null, // optional JS regex string; wins over branchPrefix
  template: "base",
  templateRules: [], // [{pattern, template}] per-branch overrides
  sandboxTimeoutMs: 60 * 60 * 1000, // 1h
  projectPath: "/home/user/project", // E2B's conventional working dir
  serverPort: 3000,
  batchSize: 40,
  ignore: [
    ".git",
    "node_modules",
    ".next",
    "dist",
    "build",
    ".turbo",
    ".cache",
    "target",
    ".venv",
    "__pycache__",
    ".DS_Store",
    ".env",
    ".env.local",
  ],
}

/** Load config.toml (all keys optional) merged over the defaults above. */
export function loadConfig() {
  let file = {}
  try {
    file = TOML.parse(readFileSync(path.join(CONFIG_DIR, "config.toml"), "utf8"))
  } catch {
    // No config file (or unreadable) — defaults are fine.
  }
  const sandbox = file.sandbox || {}
  const upload = file.upload || {}
  const trigger = file.trigger || {}
  const secrets = file.secrets || {}
  const mode = ["manual", "marked", "all"].includes(trigger.mode)
    ? trigger.mode
    : DEFAULTS.triggerMode
  return {
    triggerMode: mode,
    branchPrefix: trigger.branch_prefix ?? DEFAULTS.branchPrefix,
    branchPattern:
      typeof trigger.branch_pattern === "string" ? trigger.branch_pattern : DEFAULTS.branchPattern,
    template: sandbox.template ?? DEFAULTS.template,
    sandboxTimeoutMs: Number(sandbox.timeout_ms ?? DEFAULTS.sandboxTimeoutMs),
    projectPath: sandbox.project_path ?? DEFAULTS.projectPath,
    serverPort: Number(sandbox.server_port ?? DEFAULTS.serverPort),
    batchSize: Number(upload.batch_size ?? DEFAULTS.batchSize),
    ignore: Array.isArray(upload.ignore) ? upload.ignore : DEFAULTS.ignore,
    // Per-branch template overrides: first matching rule wins, else `template`.
    templateRules: Array.isArray(sandbox.template_rules)
      ? sandbox.template_rules.filter((r) => r && r.pattern && r.template)
      : DEFAULTS.templateRules,
    // Env wins over config so you can still export it if you prefer.
    apiKey: process.env.E2B_API_KEY?.trim() || secrets.e2b_api_key || null,
  }
}

/** Resolve the E2B template for a branch: first matching rule, else default. */
export function resolveTemplate(branch, cfg) {
  for (const rule of cfg.templateRules) {
    try {
      if (new RegExp(rule.pattern).test(branch || "")) return rule.template
    } catch {
      // bad regex in config → skip this rule
    }
  }
  return cfg.template
}
