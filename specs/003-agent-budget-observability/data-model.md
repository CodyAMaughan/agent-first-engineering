# Phase 1 Data Model

Entities derived from the spec's **Key Entities** and Functional Requirements. These are the in-memory
and on-disk shapes the cost engine, breaker, and ledger operate on. Field-level contracts (JSON
schemas / config grammar) live in `contracts/`.

---

## Entity: PriceRate (per-model, per-token-type rate)

The unit of pricing, one entry per `(model, token_type)`. Sourced from the maintained price table
(FR-003), never hardcoded.

| Field | Type | Notes |
|---|---|---|
| `model` | string | canonical model id (e.g. `claude-opus-4-...`) |
| `inputPerToken` | number (USD) | input-token rate |
| `outputPerToken` | number (USD) | output-token rate |
| `cacheReadPerToken` | number (USD) | ≈ 0.1× input; **must** be its own rate (FR-002, cache edge case) |
| `cacheWritePerToken` | number (USD) | ≈ 1.25–2× input; its own rate |
| `source` | string | which table provided it (e.g. `litellm`) |

**Validation**: a missing model or missing token-type rate triggers the **fallback policy** (FR-019),
never $0. Rates are read from the **PriceTable** snapshot, below.

## Entity: PriceTable (the cached, maintained table)

| Field | Type | Notes |
|---|---|---|
| `fetchedAt` | timestamp (ISO-8601) | when the cache was last refreshed |
| `maxAgeHours` | number | staleness threshold (from config); past this the table is "stale" |
| `source` | string/URL | the configured maintained source (LiteLLM by default) |
| `rates` | map<model, PriceRate> | the per-model rate set |

**State**: `fresh` (fetchedAt within maxAge) | `stale` (older) | `missing` (no cache, fetch failed).
`stale`/`missing` invoke the fallback policy (FR-019).

## Entity: UsageEvent (one unit of token consumption)

The raw material for tracking, the live view, and the per-task record (spec Key Entities). Derived from
the agent's local usage logs (FR-006) and attributed per agent/subagent/skill (FR-005).

| Field | Type | Notes |
|---|---|---|
| `runId` | string | the workflow run this belongs to |
| `agentId` | string | responsible agent/subagent/skill (`query_source`, `agent.name`, `skill.name`) |
| `model` | string | model that produced the usage |
| `inputTokens` | int | |
| `outputTokens` | int | |
| `cacheReadTokens` | int | priced at `cacheReadPerToken` |
| `cacheWriteTokens` | int | priced at `cacheWritePerToken` |
| `timestamp` | timestamp | for "events since last check" windowing |

**Derivation**: `notionalCost(event) = Σ_type (tokens_type × PriceRate[model].type)` (FR-002).

## Entity: BudgetConfig (`.agent/budget.conf`)

Optional, opt-in (FR-013). Absent → existing behavior unchanged (SC-005). Scaffolder ships a
conservative default (FR-022). Full grammar in `contracts/budget.conf.schema.md`.

| Field | Type | Notes |
|---|---|---|
| `enabled` | bool | master switch; default present-and-on when scaffolder emits it |
| `perTask.hardCostUsd` | number | hard-abort notional-cost ceiling per task (conservative default) |
| `perTask.softCostUsd` | number | soft-alert threshold (< hard) — alert, continue (FR-008) |
| `perTask.hardTokens` | int? | optional token ceiling per task (FR-007) |
| `perWorkflow.hardCostUsd` | number? | per-workflow ceiling (aggregate across tasks) |
| `iterationCap` | int | max agent steps before abort, independent of cost (FR-012) |
| `priceTable.source` | string | maintained-table source (FR-003) |
| `priceTable.maxAgeHours` | number | staleness threshold |
| `priceTable.fallbackPolicy` | enum | `block` \| `assume-max` \| `warn-continue` (FR-019) |

**Validation**: `soft < hard` for every threshold; `iterationCap ≥ 1`; `fallbackPolicy` in the enum.
Invalid config fails closed (refuse to start) so a typo can't disable the guardrail.

## Entity: BudgetState (in-memory accumulator, the CostCircuitBreaker's ledger)

Lives for the duration of one run; not persisted (the **BudgetRecord** is the persisted summary).

| Field | Type | Notes |
|---|---|---|
| `runId` | string | |
| `spentUsd` | number | accumulated notional cost across all agents (the per-task aggregate) |
| `spentTokens` | int | accumulated tokens |
| `iterations` | int | agent steps taken so far |
| `perAgent` | map<agentId, {usd, tokens}> | the per-agent breakdown |
| `softFired` | bool | soft alert already raised (don't re-alert every step) |
| `status` | enum | `running` \| `completed` \| `aborted-on-budget` |
| `breachedThreshold` | string? | which threshold tripped (`perTask.hard` / `iterationCap` / …) |

**Transitions**:
`running` → (soft crossed) raise alert, set `softFired`, stay `running` (FR-008)
`running` → (hard cost OR token OR iteration cap crossed) `aborted-on-budget`, set `breachedThreshold`,
short-circuit before next step (FR-009/010/012)
`running` → (run finishes under ceiling) `completed`.
This maps onto the extended `budget` primitive: `budget.spent()` returns `spentUsd`, `agent()` throws
once `spentUsd ≥ perTask.hardCostUsd` (FR-011).

## Entity: BudgetRecord (the per-task durable record — P2 ledger foundation)

Written once per run end (completed **or** aborted), appended to `.agent/budget/runs/*.ndjson`
(FR-020, SC-002). Contract in `contracts/budget-record.schema.md`.

| Field | Type | Notes |
|---|---|---|
| `runId` | string | |
| `workflowType` | enum | `feature-pipeline` \| `qa-loop` \| `create-mvp` |
| `taskId` | string | the task this run served |
| `startedAt` / `endedAt` | timestamp | |
| `totalNotionalCostUsd` | number | labeled **notional** (FR-004, SC-006) |
| `totalTokens` | int | |
| `perAgent` | array<{agentId, model, tokens-by-type, notionalCostUsd}> | per-agent breakdown (FR-005) |
| `status` | enum | `completed` \| `aborted-on-budget` |
| `breachedThreshold` | string? | populated when aborted (FR-010) |
| `costBasis` | enum | `notional` \| `billed` — so the number is never misread (SC-006) |

---

## Relationships

```text
PriceTable ──contains──> PriceRate (one per model)
UsageEvent ──priced by──> PriceRate ──> notionalCost
CostCircuitBreaker reads UsageEvents, accumulates into BudgetState,
   compares against BudgetConfig thresholds,
   and on run-end emits one BudgetRecord per run.
```
