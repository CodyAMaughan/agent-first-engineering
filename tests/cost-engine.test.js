// cost-engine.test.js — unit tests for the agent-neutral cost core (run: node --test).
// Covers: budget-config (fail-closed validation), price-table (per-token-type rates +
// fail-safe fallback, never $0), cost-engine (Σ tokens×rate, cache-read/write own rates),
// and budget-record (NDJSON shape). Strict TDD: written before the implementations.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { readBudgetConfig } from '../.claude/workflows/lib/budget-config.js'
import { loadPriceTable, rateFor, tableState } from '../.claude/workflows/lib/price-table.js'
import { costOf, costByAgent, totalCost } from '../.claude/workflows/lib/cost-engine.js'
import { writeBudgetRecord } from '../.claude/workflows/lib/budget-record.js'

// ---- a LiteLLM-style price table fixture (per-token USD) -------------------------------------
// claude-opus: input $15/Mtok, output $75/Mtok, cache-read 0.1×input, cache-write 1.25×input.
const OPUS = {
  input_cost_per_token: 15 / 1e6,
  output_cost_per_token: 75 / 1e6,
  cache_read_input_token_cost: 1.5 / 1e6, // 0.1× input
  cache_creation_input_token_cost: 18.75 / 1e6, // 1.25× input
}
function tmpTable(rates) {
  const d = mkdtempSync(join(tmpdir(), 'price-'))
  const f = join(d, 'model_prices_and_context_window.json')
  writeFileSync(f, JSON.stringify(rates))
  return { dir: d, file: f }
}
function tmpConf(body) {
  const d = mkdtempSync(join(tmpdir(), 'conf-'))
  const f = join(d, 'budget.conf')
  writeFileSync(f, body)
  return { dir: d, file: f }
}

// =============================================================================================
// budget-config.js — fail-closed KEY=value reader (T003)
// =============================================================================================
test('budget-config: a valid file parses to the BudgetConfig shape', () => {
  const { dir, file } = tmpConf(
    'BUDGET_ENABLED=true\nPERTASK_SOFT_USD=3.00\nPERTASK_HARD_USD=5.00\n' +
    'PERWORKFLOW_HARD_USD=15.00\nITERATION_CAP=40\nPRICE_TABLE_SOURCE=litellm\n' +
    'PRICE_TABLE_MAX_AGE_HOURS=168\nPRICE_TABLE_FALLBACK=assume-max\n')
  const c = readBudgetConfig(file)
  assert.equal(c.enabled, true)
  assert.equal(c.perTask.softUsd, 3.0)
  assert.equal(c.perTask.hardUsd, 5.0)
  assert.equal(c.perWorkflow.hardUsd, 15.0)
  assert.equal(c.iterationCap, 40)
  assert.equal(c.priceTable.fallback, 'assume-max')
  rmSync(dir, { recursive: true, force: true })
})

test('budget-config: absent file ⇒ disabled no-op (opt-in)', () => {
  const c = readBudgetConfig(join(tmpdir(), 'definitely-missing-budget.conf'))
  assert.equal(c.enabled, false)
})

test('budget-config: soft >= hard fails closed', () => {
  const { dir, file } = tmpConf(
    'BUDGET_ENABLED=true\nPERTASK_SOFT_USD=5.00\nPERTASK_HARD_USD=5.00\nITERATION_CAP=40\n' +
    'PRICE_TABLE_SOURCE=litellm\nPRICE_TABLE_MAX_AGE_HOURS=168\nPRICE_TABLE_FALLBACK=assume-max\n')
  assert.throws(() => readBudgetConfig(file), /soft/i)
  rmSync(dir, { recursive: true, force: true })
})

test('budget-config: ITERATION_CAP < 1 fails closed', () => {
  const { dir, file } = tmpConf(
    'BUDGET_ENABLED=true\nPERTASK_SOFT_USD=3.00\nPERTASK_HARD_USD=5.00\nITERATION_CAP=0\n' +
    'PRICE_TABLE_SOURCE=litellm\nPRICE_TABLE_MAX_AGE_HOURS=168\nPRICE_TABLE_FALLBACK=assume-max\n')
  assert.throws(() => readBudgetConfig(file), /iteration/i)
  rmSync(dir, { recursive: true, force: true })
})

test('budget-config: out-of-enum fallback fails closed', () => {
  const { dir, file } = tmpConf(
    'BUDGET_ENABLED=true\nPERTASK_SOFT_USD=3.00\nPERTASK_HARD_USD=5.00\nITERATION_CAP=40\n' +
    'PRICE_TABLE_SOURCE=litellm\nPRICE_TABLE_MAX_AGE_HOURS=168\nPRICE_TABLE_FALLBACK=free-money\n')
  assert.throws(() => readBudgetConfig(file), /fallback/i)
  rmSync(dir, { recursive: true, force: true })
})

// =============================================================================================
// price-table.js — per-token-type rates + fail-safe fallback (T004)
// =============================================================================================
function cfg(over = {}) {
  return {
    priceTable: { source: 'litellm', maxAgeHours: 168, fallback: 'assume-max', ...over },
  }
}

test('price-table: rateFor returns the per-token-type rate for a known model', () => {
  const { dir, file } = tmpTable({ 'claude-opus': OPUS })
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: file } })
  assert.equal(rateFor(t, 'claude-opus', 'input', cfg()), OPUS.input_cost_per_token)
  assert.equal(rateFor(t, 'claude-opus', 'output', cfg()), OPUS.output_cost_per_token)
  assert.equal(rateFor(t, 'claude-opus', 'cacheRead', cfg()), OPUS.cache_read_input_token_cost)
  assert.equal(rateFor(t, 'claude-opus', 'cacheWrite', cfg()), OPUS.cache_creation_input_token_cost)
  rmSync(dir, { recursive: true, force: true })
})

test('price-table: unknown model under assume-max returns a conservative HIGH rate, never 0', () => {
  const { dir, file } = tmpTable({ 'claude-opus': OPUS })
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: file } })
  const r = rateFor(t, 'some-future-model', 'input', cfg({ fallback: 'assume-max' }))
  assert.ok(r > 0, 'assume-max must never return 0')
  assert.ok(r >= OPUS.input_cost_per_token, 'assume-max should be conservative (>= a known high rate)')
  rmSync(dir, { recursive: true, force: true })
})

test('price-table: unknown model under block throws (refuse to start)', () => {
  const { dir, file } = tmpTable({ 'claude-opus': OPUS })
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: file } })
  assert.throws(() => rateFor(t, 'some-future-model', 'input', cfg({ fallback: 'block' })), /price|rate|unknown/i)
  rmSync(dir, { recursive: true, force: true })
})

test('price-table: tableState is missing when no cache exists', () => {
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: join(tmpdir(), 'no-such-cache.json') } })
  assert.equal(tableState(t), 'missing')
})

// =============================================================================================
// cost-engine.js — Σ tokens×rate; cache-read/write at their OWN rates (T007/T008/T009)
// =============================================================================================
test('cost-engine: cache-read and cache-write are priced at their OWN rates, not input', () => {
  const { dir, file } = tmpTable({ 'claude-opus': OPUS })
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: file } })
  // 1M cache-read tokens cost 1M × cacheRead, which must NOT equal 1M × input.
  const ev = { runId: 'r', agentId: 'main', model: 'claude-opus', inputTokens: 0, outputTokens: 0, cacheReadTokens: 1e6, cacheWriteTokens: 0 }
  const c = costOf(ev, t, cfg())
  assert.equal(c, 1e6 * OPUS.cache_read_input_token_cost)
  assert.notEqual(c, 1e6 * OPUS.input_cost_per_token, 'cache-read must not be priced at the input rate')
  rmSync(dir, { recursive: true, force: true })
})

test('cost-engine: a hand-computed token-count→USD matches exactly', () => {
  const { dir, file } = tmpTable({ 'claude-opus': OPUS })
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: file } })
  const ev = { runId: 'r', agentId: 'main', model: 'claude-opus', inputTokens: 1000, outputTokens: 500, cacheReadTokens: 2000, cacheWriteTokens: 100 }
  const expected =
    1000 * OPUS.input_cost_per_token +
    500 * OPUS.output_cost_per_token +
    2000 * OPUS.cache_read_input_token_cost +
    100 * OPUS.cache_creation_input_token_cost
  assert.equal(costOf(ev, t, cfg()), expected)
  rmSync(dir, { recursive: true, force: true })
})

test('cost-engine: totalCost over events matches a hand-derived ccusage-style baseline and is labeled notional', () => {
  const { dir, file } = tmpTable({ 'claude-opus': OPUS, 'claude-sonnet': { input_cost_per_token: 3 / 1e6, output_cost_per_token: 15 / 1e6, cache_read_input_token_cost: 0.3 / 1e6, cache_creation_input_token_cost: 3.75 / 1e6 } })
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: file } })
  const events = [
    { runId: 'r', agentId: 'main', model: 'claude-opus', inputTokens: 10000, outputTokens: 2000, cacheReadTokens: 50000, cacheWriteTokens: 1000 },
    { runId: 'r', agentId: 'subagent:reviewer', model: 'claude-sonnet', inputTokens: 4000, outputTokens: 1200, cacheReadTokens: 0, cacheWriteTokens: 0 },
  ]
  const opusCost = 10000 * (15 / 1e6) + 2000 * (75 / 1e6) + 50000 * (1.5 / 1e6) + 1000 * (18.75 / 1e6)
  const sonnetCost = 4000 * (3 / 1e6) + 1200 * (15 / 1e6)
  const tot = totalCost(events, t, cfg())
  assert.ok(Math.abs(tot.usd - (opusCost + sonnetCost)) < 1e-9)
  assert.equal(tot.tokens, 10000 + 2000 + 50000 + 1000 + 4000 + 1200)
  assert.equal(tot.costBasis, 'notional')
  rmSync(dir, { recursive: true, force: true })
})

test('cost-engine: costByAgent attributes per agentId', () => {
  const { dir, file } = tmpTable({ 'claude-opus': OPUS })
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: file } })
  const events = [
    { runId: 'r', agentId: 'main', model: 'claude-opus', inputTokens: 1000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 },
    { runId: 'r', agentId: 'main', model: 'claude-opus', inputTokens: 1000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 },
    { runId: 'r', agentId: 'sub', model: 'claude-opus', inputTokens: 500, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 },
  ]
  const m = costByAgent(events, t, cfg())
  assert.equal(m.main.usd, 2000 * OPUS.input_cost_per_token)
  assert.equal(m.sub.usd, 500 * OPUS.input_cost_per_token)
  assert.equal(m.main.tokens, 2000)
  rmSync(dir, { recursive: true, force: true })
})

test('cost-engine: fail-safe — missing table + assume-max yields a conservative non-zero cost (never $0)', () => {
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: join(tmpdir(), 'no-cache-here.json') } })
  assert.equal(tableState(t), 'missing')
  const ev = { runId: 'r', agentId: 'main', model: 'whatever', inputTokens: 1000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 }
  const c = costOf(ev, t, cfg({ fallback: 'assume-max' }))
  assert.ok(c > 0, 'a missing price table must never cost $0 (FR-019)')
})

test('cost-engine: fail-safe — missing table + block throws', () => {
  const t = loadPriceTable({ ...cfg(), priceTable: { ...cfg().priceTable, cacheFile: join(tmpdir(), 'no-cache-here-2.json') } })
  const ev = { runId: 'r', agentId: 'main', model: 'whatever', inputTokens: 1000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 }
  assert.throws(() => costOf(ev, t, cfg({ fallback: 'block' })), /price|rate|unknown|block/i)
})

// =============================================================================================
// budget-record.js — per-run NDJSON ledger (T015)
// =============================================================================================
test('budget-record: writes exactly one valid NDJSON line matching the contract', () => {
  const dir = mkdtempSync(join(tmpdir(), 'runs-'))
  const record = {
    runId: 'qa-loop-test', workflowType: 'qa-loop', taskId: 'demo',
    startedAt: '2026-06-13T14:50:22Z', endedAt: '2026-06-13T14:58:09Z',
    costBasis: 'notional', totalNotionalCostUsd: 4.12, totalTokens: 1830422,
    status: 'aborted-on-budget', breachedThreshold: 'perTask.hard',
    perAgent: [{ agentId: 'main', model: 'claude-opus', inputTokens: 1, outputTokens: 1, cacheReadTokens: 0, cacheWriteTokens: 0, notionalCostUsd: 4.12 }],
  }
  const out = writeBudgetRecord(record, dir)
  const lines = readFileSync(out, 'utf8').trimEnd().split('\n')
  assert.equal(lines.length, 1)
  const parsed = JSON.parse(lines[0])
  for (const k of ['runId', 'workflowType', 'taskId', 'startedAt', 'endedAt', 'costBasis', 'totalNotionalCostUsd', 'totalTokens', 'status', 'perAgent']) {
    assert.ok(k in parsed, `record missing required field: ${k}`)
  }
  assert.equal(parsed.costBasis, 'notional')
  assert.ok(['completed', 'aborted-on-budget'].includes(parsed.status))
  assert.equal(parsed.breachedThreshold, 'perTask.hard')
  rmSync(dir, { recursive: true, force: true })
})

test('budget-record: rejects a record missing required fields (fail closed)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'runs2-'))
  assert.throws(() => writeBudgetRecord({ runId: 'x' }, dir), /required|missing|invalid/i)
  rmSync(dir, { recursive: true, force: true })
})
