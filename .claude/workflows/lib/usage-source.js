// usage-source.js — the ONLY agent-specific module in the core path (the adapter seam,
// Constitution II). It maps the reference agent's local usage logs to neutral UsageEvent[]:
//   ~/.claude/projects/**/*.jsonl  (one JSON object per line, ccusage-style).
// A Codex/opencode adapter implements the same `readUsageSince` signature against its own logs.
//
// Works with telemetry OFF: it reads FILES, never the OTel collector (FR-006/FR-014).
import { readdirSync, statSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'

// Resolve the usage-log root. Overridable (opts.usageDir or $USAGE_SOURCE_DIR) so fixtures can
// inject a stub log without touching a real home directory.
function usageRoot(opts) {
  if (opts && opts.usageDir) return opts.usageDir
  if (process.env.USAGE_SOURCE_DIR) return process.env.USAGE_SOURCE_DIR
  return join(homedir(), '.claude')
}

// Recursively collect *.jsonl files under a directory.
function findJsonl(dir, acc = []) {
  let entries
  try {
    entries = readdirSync(dir, { withFileTypes: true })
  } catch {
    return acc
  }
  for (const e of entries) {
    const p = join(dir, e.name)
    if (e.isDirectory()) findJsonl(p, acc)
    else if (e.isFile() && e.name.endsWith('.jsonl')) acc.push(p)
  }
  return acc
}

// Which run does a log line belong to? ccusage logs carry a sessionId; we also accept an explicit
// runId field. The matcher is exact on either.
function lineRunId(obj) {
  return obj.runId || obj.sessionId || null
}

// Attribute usage to the responsible agent/subagent/skill (FR-005). Claude logs expose
// query_source (main vs subagent), agent.name, and skill.name; map them to a neutral agentId.
function agentIdOf(obj) {
  if (obj.skill && obj.skill.name) return `skill:${obj.skill.name}`
  if (obj.agent && obj.agent.name) return `subagent:${obj.agent.name}`
  if (obj.query_source && obj.query_source !== 'user' && obj.query_source !== 'main') {
    return `subagent:${obj.query_source}`
  }
  return 'main'
}

// Pull a usage block from a ccusage-style assistant message (or a top-level usage block).
function usageOf(obj) {
  if (obj.message && obj.message.usage) return { usage: obj.message.usage, model: obj.message.model }
  if (obj.usage) return { usage: obj.usage, model: obj.model }
  return null
}

// readUsageSince(runId, sinceTimestamp, opts?) -> UsageEvent[]
//   opts.usageDir overrides the log root (for fixtures).
export function readUsageSince(runId, sinceTimestamp, opts = {}) {
  const root = usageRoot(opts)
  const since = sinceTimestamp ? Date.parse(sinceTimestamp) : 0
  const events = []
  for (const file of findJsonl(root)) {
    let text
    try {
      // Skip files untouched since the cutoff for speed; still safe because we re-check per line.
      if (since && statSync(file).mtimeMs < since) { /* may still contain newer? statSync is the file's last write; keep reading to be safe */ }
      text = readFileSync(file, 'utf8')
    } catch {
      continue
    }
    for (const raw of text.split('\n')) {
      const line = raw.trim()
      if (!line) continue
      let obj
      try { obj = JSON.parse(line) } catch { continue }
      if (lineRunId(obj) !== runId) continue
      const ts = obj.timestamp ? Date.parse(obj.timestamp) : 0
      if (since && ts && ts < since) continue
      const u = usageOf(obj)
      if (!u) continue
      events.push({
        runId,
        agentId: agentIdOf(obj),
        model: u.model || obj.model || 'unknown',
        inputTokens: u.usage.input_tokens || 0,
        outputTokens: u.usage.output_tokens || 0,
        cacheReadTokens: u.usage.cache_read_input_tokens || 0,
        cacheWriteTokens: u.usage.cache_creation_input_tokens || 0,
        timestamp: obj.timestamp || null,
      })
    }
  }
  return events
}
