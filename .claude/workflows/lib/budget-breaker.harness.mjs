// budget-breaker.harness.mjs — a thin CLI the budget-breaker fixture drives. It wires a real
// BudgetBreaker to a stub usage stream (one event dispensed per checkpoint) and prints a JSON
// summary of the terminal decision + the written BudgetRecord. NOT shipped to scaffolded repos;
// it exists so the shell fixture can exercise the real breaker deterministically.
//
// Usage: node budget-breaker.harness.mjs --conf <f> --cache <f> --runs <dir> --runId <id> --steps N
import { readBudgetConfig } from './budget-config.js'
import { loadPriceTable } from './price-table.js'
import { readUsageSince } from './usage-source.js'
import { BudgetBreaker } from './budget-breaker.js'

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`)
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def
}

const confPath = arg('conf')
const cachePath = arg('cache')
const runsDir = arg('runs')
const runId = arg('runId', 'fixture-run')
const steps = parseInt(arg('steps', '1'), 10)

const config = readBudgetConfig(confPath)
// Point the price table at the fixture's cache.
config.priceTable = { ...config.priceTable, cacheFile: cachePath }
const table = loadPriceTable(config)

// Read the full stub usage stream once, then dispense ONE event per checkpoint so each step's
// spend accumulates exactly like a live run between agent() calls.
const all = readUsageSince(runId, '1970-01-01T00:00:00Z', {})
let cursor = 0
const dispenseOne = () => {
  if (cursor >= all.length) return []
  return [all[cursor++]]
}

const softLines = []
const breaker = new BudgetBreaker(config, table, { total: 0, spent: () => 0, remaining: () => 0 }, {
  runId,
  runsDir,
  startedAt: '2026-06-13T10:00:00Z',
  readUsage: dispenseOne,
  log: (m) => { softLines.push(m); process.stderr.write(m + '\n') },
})

let terminal = 'continue'
let sawSoft = false
for (let i = 0; i < steps; i++) {
  const r = breaker.checkpoint(runId)
  if (r.action === 'alert') sawSoft = true
  if (r.action === 'abort') { terminal = 'abort'; break }
  terminal = r.action
}

const record = breaker.onRunEnd(null, { workflowType: 'qa-loop', taskId: 'fixture-task', endedAt: '2026-06-13T10:05:00Z' })

if (softLines.some((l) => /soft alert/i.test(l))) sawSoft = true

const out = {
  terminal,
  action: terminal,
  status: breaker.state.status,
  breachedThreshold: breaker.state.breachedThreshold,
  iterations: breaker.state.iterations,
  spentUsd: breaker.state.spentUsd,
  softFired: breaker.state.softFired || sawSoft,
  recordStatus: record ? record.status : null,
}
process.stdout.write(JSON.stringify(out) + '\n')

// Exit non-zero when the run aborted on budget, so the shell can also key off the exit code.
process.exit(breaker.state.status === 'aborted-on-budget' ? 7 : 0)
