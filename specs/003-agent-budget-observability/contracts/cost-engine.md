# Contract: Cost Engine + Price-Table Adapter + Budget Breaker

The agent-neutral core (FR-021). These are JS module interfaces (ES modules, matching
`.claude/workflows/*.js`). All money is **notional USD at API rates** and labeled as such (FR-004).

## `price-table.js` — the price-table adapter (FR-003, FR-019)

```text
loadPriceTable(config) -> PriceTable
  // Reads .agent/budget/price-table.cache.json; refreshes from PRICE_TABLE_SOURCE if missing/stale.
  // Stamps fetchedAt; computes freshness against PRICE_TABLE_MAX_AGE_HOURS.

rateFor(table, model, tokenType) -> number            // USD per token
  // tokenType ∈ {input, output, cacheRead, cacheWrite}
  // On a missing model/rate, applies config.PRICE_TABLE_FALLBACK:
  //   block        -> throw (caller refuses to start / aborts)
  //   assume-max   -> return a conservative high rate, flag the run
  //   warn-continue-> surface a warning, use best-available estimate
  // MUST NEVER return 0 for an unknown rate (FR-019).

tableState(table) -> 'fresh' | 'stale' | 'missing'
```

**Contract**: never silently $0; staleness is observable; the source is configurable, not compiled in.

## `usage-source.js` — the per-agent usage adapter (FR-005, FR-006)

The **only** agent-specific module in the core path (the adapter seam, Constitution II). Maps the
reference agent's local logs to neutral `UsageEvent`s.

```text
readUsageSince(runId, sinceTimestamp) -> UsageEvent[]
  // Reference impl: parse ~/.claude/projects/**/*.jsonl (ccusage-style) for messages after
  // sinceTimestamp belonging to runId; emit per-event tokens-by-type + agentId (query_source/
  // agent.name/skill.name) + model. A Codex/opencode adapter implements the same signature.
```

**Contract**: works with telemetry OFF (reads files, not the collector — FR-006/FR-014); attribution
per agent/subagent/skill; agent specifics confined here.

## `cost-engine.js` — notional cost (FR-002)

```text
costOf(event, table, config) -> number
  // = event.inputTokens      * rateFor(table, event.model, 'input')
  //  + event.outputTokens     * rateFor(table, event.model, 'output')
  //  + event.cacheReadTokens  * rateFor(table, event.model, 'cacheRead')
  //  + event.cacheWriteTokens * rateFor(table, event.model, 'cacheWrite')
  // Cache-read and cache-write are costed at THEIR OWN rates, not the input rate (SC-004).

costByAgent(events, table, config) -> map<agentId, {usd, tokens}>
totalCost(events, table, config)   -> { usd, tokens }
```

**Contract**: pure function of (events, rates); per-token-type rates honored; agent-neutral (no Claude
paths here — those live in `usage-source.js`).

## `budget-breaker.js` — the CostCircuitBreaker (FR-007–FR-012)

```text
new BudgetBreaker(config, table, budgetPrimitive) -> breaker
  // budgetPrimitive = the runtime's existing { total, spent(), remaining(), ... }, EXTENDED so
  // spent() reflects model-aware notional cost and total = PERTASK_HARD_USD (FR-011).

breaker.checkpoint(runId) -> { action: 'continue' | 'alert' | 'abort', state: BudgetState }
  // Called between agent() steps:
  //   1. events = usage-source.readUsageSince(runId, lastChecked)
  //   2. accumulate cost/tokens/iterations into BudgetState; update budgetPrimitive.spent()
  //   3. iterations >= ITERATION_CAP                      -> abort (breach='iterationCap')   (FR-012)
  //   4. spentUsd >= PERTASK_HARD_USD (or token ceiling)  -> abort (breach='perTask.hard')   (FR-009)
  //   5. perWorkflow aggregate >= PERWORKFLOW_HARD_USD    -> abort (breach='perWorkflow.hard')
  //   6. spentUsd >= PERTASK_SOFT_USD and not softFired   -> alert once, continue            (FR-008)
  //   7. else                                             -> continue

breaker.onRunEnd(status) -> BudgetRecord   // writes the per-task record (delegates to budget-record.js)
```

**Contract**: deterministic; aborts **before** the next `agent()` call so overshoot ≤ one in-flight
step (SC-001); soft alerts once; functions with the observability pipeline absent (FR-014). The runtime
wires `checkpoint()` into the `agent()` wrapper so `agent()` throws on an `abort` action (FR-011), and
calls `onRunEnd()` on every termination path (FR-020).

## Workflow wiring (the EXTEND points)

`feature-pipeline.js` / `qa-loop.js` (and `create-mvp` when it lands) construct one `BudgetBreaker`
at run start and call `breaker.checkpoint(runId)` between steps. When `BUDGET_ENABLED=false` or the
config is absent, `checkpoint()` always returns `continue` and `onRunEnd()` is a no-op — preserving
today's behavior exactly (SC-005).
