// notional-accuracy.test.js — the cost engine's total over a parsed usage stream must match a
// hand-derived ccusage-style baseline (within tolerance) and be labeled `notional` (FR-004, SC-006).
// The usage-source adapter reads a stub ccusage-style JSONL log so this runs with telemetry OFF.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { loadPriceTable } from '../.claude/workflows/lib/price-table.js'
import { totalCost } from '../.claude/workflows/lib/cost-engine.js'
import { readUsageSince } from '../.claude/workflows/lib/usage-source.js'

const OPUS = {
  input_cost_per_token: 15 / 1e6,
  output_cost_per_token: 75 / 1e6,
  cache_read_input_token_cost: 1.5 / 1e6,
  cache_creation_input_token_cost: 18.75 / 1e6,
}
const cfg = { priceTable: { source: 'litellm', maxAgeHours: 168, fallback: 'assume-max' } }

// A ccusage-style ~/.claude/projects/**/*.jsonl: one JSON object per line, assistant messages carry
// message.usage with input_tokens / output_tokens / cache_read_input_tokens / cache_creation_input_tokens.
function stubLog(dir, runId) {
  const proj = join(dir, 'projects', 'demo')
  mkdirSync(proj, { recursive: true })
  const lines = [
    { sessionId: runId, timestamp: '2026-06-13T10:00:01Z', type: 'assistant', message: { model: 'claude-opus', usage: { input_tokens: 10000, output_tokens: 2000, cache_read_input_tokens: 50000, cache_creation_input_tokens: 1000 } } },
    { sessionId: runId, timestamp: '2026-06-13T10:00:05Z', type: 'assistant', message: { model: 'claude-opus', usage: { input_tokens: 4000, output_tokens: 1200, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } }, agent: { name: 'code-reviewer' } },
    { sessionId: 'OTHER-RUN', timestamp: '2026-06-13T10:00:09Z', type: 'assistant', message: { model: 'claude-opus', usage: { input_tokens: 999999, output_tokens: 0 } } },
  ]
  writeFileSync(join(proj, 'session.jsonl'), lines.map((l) => JSON.stringify(l)).join('\n') + '\n')
}

test('notional accuracy: engine total over the parsed JSONL matches the ccusage-style baseline and is notional', () => {
  const { dir: tdir, file } = (() => {
    const d = mkdtempSync(join(tmpdir(), 'price-'))
    const f = join(d, 'mp.json')
    writeFileSync(f, JSON.stringify({ 'claude-opus': OPUS }))
    return { dir: d, file: f }
  })()
  const logDir = mkdtempSync(join(tmpdir(), 'claude-'))
  const runId = 'feature-pipeline-2026'
  stubLog(logDir, runId)

  const table = loadPriceTable({ ...cfg, priceTable: { ...cfg.priceTable, cacheFile: file } })
  const events = readUsageSince(runId, '1970-01-01T00:00:00Z', { usageDir: logDir })

  // The unrelated session (OTHER-RUN) must be excluded.
  assert.equal(events.length, 2, 'only this runId\'s events are returned')

  const baseline =
    10000 * OPUS.input_cost_per_token + 2000 * OPUS.output_cost_per_token +
    50000 * OPUS.cache_read_input_token_cost + 1000 * OPUS.cache_creation_input_token_cost +
    4000 * OPUS.input_cost_per_token + 1200 * OPUS.output_cost_per_token

  const tot = totalCost(events, table, cfg)
  assert.ok(Math.abs(tot.usd - baseline) < 1e-9, `engine ${tot.usd} vs baseline ${baseline}`)
  assert.equal(tot.costBasis, 'notional')

  rmSync(tdir, { recursive: true, force: true })
  rmSync(logDir, { recursive: true, force: true })
})

test('notional accuracy: usage-source attributes per agent/subagent', () => {
  const logDir = mkdtempSync(join(tmpdir(), 'claude2-'))
  const runId = 'attr-run'
  stubLog(logDir, runId)
  const events = readUsageSince(runId, '1970-01-01T00:00:00Z', { usageDir: logDir })
  const ids = events.map((e) => e.agentId).sort()
  // one main event + one attributed to the code-reviewer subagent.
  assert.ok(ids.includes('subagent:code-reviewer') || ids.includes('code-reviewer'), `got ${ids}`)
  rmSync(logDir, { recursive: true, force: true })
})
