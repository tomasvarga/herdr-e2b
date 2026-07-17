// Unit tests for config resolution — no E2B calls, no filesystem config.
// resolveTemplate/resolveLifecycle take a cfg object, so they're pure and offline.
import { test } from "node:test"
import assert from "node:assert/strict"
import { resolveTemplate, resolveLifecycle } from "../src/config.js"

test("resolveTemplate: no rules → default template", () => {
  const cfg = { template: "base", templateRules: [] }
  assert.equal(resolveTemplate("main", cfg), "base")
  assert.equal(resolveTemplate("", cfg), "base")
  assert.equal(resolveTemplate(undefined, cfg), "base")
})

test("resolveTemplate: first matching rule wins, else default", () => {
  const cfg = {
    template: "base",
    templateRules: [
      { pattern: "^e2b/cc/", template: "claude" },
      { pattern: "^e2b/", template: "opencode" },
    ],
  }
  assert.equal(resolveTemplate("e2b/cc/feature", cfg), "claude") // first match wins
  assert.equal(resolveTemplate("e2b/other", cfg), "opencode") // second rule
  assert.equal(resolveTemplate("feature/x", cfg), "base") // no rule → default
})

test("resolveTemplate: a bad regex is skipped, not fatal", () => {
  const cfg = {
    template: "base",
    templateRules: [
      { pattern: "[unterminated", template: "broken" },
      { pattern: "^feat/", template: "codex" },
    ],
  }
  assert.equal(resolveTemplate("feat/x", cfg), "codex")
  assert.equal(resolveTemplate("main", cfg), "base")
})

test("resolveLifecycle: autoPause off → kill", () => {
  assert.deepEqual(resolveLifecycle({ autoPause: false }), { onTimeout: "kill" })
})

test("resolveLifecycle: autoPause on → pause + autoResume", () => {
  assert.deepEqual(resolveLifecycle({ autoPause: true, autoResume: true }), {
    onTimeout: "pause",
    autoResume: true,
  })
  assert.deepEqual(resolveLifecycle({ autoPause: true, autoResume: false }), {
    onTimeout: "pause",
    autoResume: false,
  })
  // autoResume defaults to true when unset
  assert.deepEqual(resolveLifecycle({ autoPause: true }), {
    onTimeout: "pause",
    autoResume: true,
  })
})
