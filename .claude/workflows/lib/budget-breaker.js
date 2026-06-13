// budget-breaker.js — the CostCircuitBreaker (FR-007–FR-012). Between agent() steps it reads new
// usage events, costs them (model- and token-type-aware), accumulates into an in-memory
// BudgetState, fires a soft alert ONCE below the hard ceiling, and ABORTS before the next step on
// the hard cost ceiling, an optional token ceiling, the per-workflow aggregate, or the iteration
// cap. On run end it writes one BudgetRecord (delegated to budget-record.js).
//
// It EXTENDS the runtime's existing `budget` primitive ({ total, spent(), remaining() }) so that
// spent() reflects notional cost and total = PERTASK_HARD_USD, and agent() throws once spent >=
// total (FR-011). Deterministic; works with observability OFF (reads local logs, FR-014).
import { loadPriceTable } from './price-table.js'
import { totalCost, costByAgent } from './cost-engine.js'
import { readUsageSince } from './usage-source.js'
import { writeBudgetRecord } from './budget-record.js'

export class BudgetBreaker {
  // config: BudgetConfig (from budget-config.js)
  // table:  PriceTable   (from loadPriceTable); if omitted, loaded from config
  // budgetPrimitive: the runtime's { total, spent(), remaining() } — extended in place (optional)
  // opts: { usageSince, runsDir, log, usageOpts } — seams for wiring + fixtures
  constructor(config, table, budgetPrimitive, opts = {}) {
    this.config = config || { enabled: false }
    this.enabled = !!this.config.enabled
    this.table = table || (this.enabled ? loadPriceTable(this.config) : null)
    this.opts = opts
    this.log = opts.log || ((m) => process.stderr.write(m + '\n'))
    this.runsDir = opts.runsDir || '.agent/budget/runs'
    this.usageOpts = opts.usageOpts || {}
    this.readUsage = opts.readUsage || readUsageSince

    this.lastChecked = opts.usageSince || '1970-01-01T00:00:00Z'
    this.state = {
      runId: opts.runId || null,
      spentUsd: 0,
      spentTokens: 0,
      iterations: 0,
      perAgent: {},
      softFired: false,
      status: 'running',
      breachedThreshold: null,
    }
    this.startedAt = opts.startedAt || null

    // Extend the runtime budget primitive so agent() throws once spent >= total (FR-011).
    this.budget = budgetPrimitive || null
    if (this.budget && this.enabled) {
      this.budget.total = this.config.perTask.hardUsd
      this.budget.spent = () => this.state.spentUsd
      this.budget.remaining = () => Math.max(0, this.budget.total - this.state.spentUsd)
    }
  }

  // checkpoint(runId) -> { action: 'continue'|'alert'|'abort', state }
  // Called between agent() steps. Counts ONE iteration, accumulates new usage, then evaluates
  // (iteration cap → per-task hard cost → per-task token ceiling → per-workflow → soft → continue).
  checkpoint(runId) {
    if (!this.enabled) return { action: 'continue', state: this.state }
    if (runId && !this.state.runId) this.state.runId = runId
    if (this.state.status !== 'running') return { action: 'abort', state: this.state }

    this.state.iterations += 1

    // Accumulate usage since the last check (windowed, O(new events)).
    const events = this.readUsage(runId, this.lastChecked, this.usageOpts) || []
    if (events.length) {
      const tot = totalCost(events, this.table, this.config)
      this.state.spentUsd += tot.usd
      this.state.spentTokens += tot.tokens
      const byAgent = costByAgent(events, this.table, this.config)
      for (const [id, v] of Object.entries(byAgent)) {
        if (!this.state.perAgent[id]) this.state.perAgent[id] = { usd: 0, tokens: 0, model: null, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 }
        this.state.perAgent[id].usd += v.usd
        this.state.perAgent[id].tokens += v.tokens
      }
      for (const ev of events) {
        const a = this.state.perAgent[ev.agentId] || (this.state.perAgent[ev.agentId] = { usd: 0, tokens: 0, model: null, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 })
        a.model = ev.model
        a.inputTokens += ev.inputTokens || 0
        a.outputTokens += ev.outputTokens || 0
        a.cacheReadTokens += ev.cacheReadTokens || 0
        a.cacheWriteTokens += ev.cacheWriteTokens || 0
      }
      // Advance the window past the newest event we consumed.
      const newest = events.reduce((mx, e) => (e.timestamp && e.timestamp > mx ? e.timestamp : mx), this.lastChecked)
      this.lastChecked = newest
    }

    const c = this.config
    // 1. iteration cap (independent of cost) — FR-012
    if (this.state.iterations >= c.iterationCap) {
      return this._abort('iterationCap')
    }
    // 2. per-task hard cost — FR-009
    if (this.state.spentUsd >= c.perTask.hardUsd) {
      return this._abort('perTask.hard')
    }
    // 3. per-task token ceiling (optional) — FR-007
    if (c.perTask.hardTokens && this.state.spentTokens >= c.perTask.hardTokens) {
      return this._abort('perTask.tokens')
    }
    // 4. per-workflow aggregate ceiling (optional)
    if (c.perWorkflow && c.perWorkflow.hardUsd && this.state.spentUsd >= c.perWorkflow.hardUsd) {
      return this._abort('perWorkflow.hard')
    }
    // 5. soft alert once — FR-008
    if (this.state.spentUsd >= c.perTask.softUsd && !this.state.softFired) {
      this.state.softFired = true
      this.log(`[budget] soft alert: $${this.state.spentUsd.toFixed(2)} of $${c.perTask.hardUsd.toFixed(2)} (notional) — continuing`)
      return { action: 'alert', state: this.state }
    }
    return { action: 'continue', state: this.state }
  }

  _abort(threshold) {
    this.state.status = 'aborted-on-budget'
    this.state.breachedThreshold = threshold
    this.log(`[budget] ABORT: breached ${threshold} at $${this.state.spentUsd.toFixed(2)} (notional), ${this.state.iterations} steps`)
    return { action: 'abort', state: this.state }
  }

  // onRunEnd(status, meta) -> BudgetRecord (also written to the ledger). Called on EVERY
  // termination path (FR-020). `status` defaults to the breaker's own state.
  onRunEnd(status, meta = {}) {
    if (!this.enabled) return null
    const finalStatus = status || (this.state.status === 'aborted-on-budget' ? 'aborted-on-budget' : 'completed')
    const perAgent = Object.entries(this.state.perAgent).map(([agentId, a]) => ({
      agentId,
      model: a.model || 'unknown',
      inputTokens: a.inputTokens,
      outputTokens: a.outputTokens,
      cacheReadTokens: a.cacheReadTokens,
      cacheWriteTokens: a.cacheWriteTokens,
      notionalCostUsd: a.usd,
    }))
    const record = {
      runId: this.state.runId || meta.runId || 'unknown',
      workflowType: meta.workflowType || 'feature-pipeline',
      taskId: meta.taskId || this.state.runId || 'unknown',
      startedAt: this.startedAt || meta.startedAt || new Date(0).toISOString(),
      endedAt: meta.endedAt || new Date().toISOString(),
      costBasis: 'notional',
      totalNotionalCostUsd: this.state.spentUsd,
      totalTokens: this.state.spentTokens,
      status: finalStatus,
      perAgent,
    }
    if (finalStatus === 'aborted-on-budget') {
      record.breachedThreshold = this.state.breachedThreshold || 'perTask.hard'
    }
    writeBudgetRecord(record, this.runsDir)
    return record
  }
}

export default BudgetBreaker
