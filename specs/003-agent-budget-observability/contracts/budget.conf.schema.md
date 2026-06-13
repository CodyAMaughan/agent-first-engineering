# Contract: `.agent/budget.conf` (budget configuration)

The optional, opt-in guardrail config (FR-013, FR-022). Format follows the repo's existing
`.agent/*.conf` convention: a shell-sourceable `KEY=value` file (so a POSIX `sh` reader and a JS reader
can both parse it), with namespaced keys. **Absent file → existing workflow behavior unchanged**
(SC-005). The scaffolder ships this with the **conservative defaults shown below** (FR-022).

## Keys

| Key | Type | Required | Default (scaffolder-emitted) | Meaning |
|---|---|---|---|---|
| `BUDGET_ENABLED` | bool | yes | `true` | master switch; `false` ⇒ no enforcement |
| `PERTASK_HARD_USD` | number | yes | `5.00` | hard-abort notional-cost ceiling per task |
| `PERTASK_SOFT_USD` | number | yes | `3.00` | soft-alert threshold (**must be < hard**) |
| `PERTASK_HARD_TOKENS` | int | no | *(unset)* | optional per-task token ceiling |
| `PERWORKFLOW_HARD_USD` | number | no | `15.00` | aggregate per-workflow ceiling |
| `ITERATION_CAP` | int | yes | `40` | max agent steps before abort (independent of cost) |
| `PRICE_TABLE_SOURCE` | string | yes | `litellm` | maintained price-table source id/URL |
| `PRICE_TABLE_MAX_AGE_HOURS` | number | yes | `168` | staleness threshold (7 days) |
| `PRICE_TABLE_FALLBACK` | enum | yes | `assume-max` | `block` \| `assume-max` \| `warn-continue` on a missing/stale rate (FR-019) |

> Defaults are **conservative and tunable** — low enough to halt a runaway (the motivating ~4h run
> would trip `PERTASK_HARD_USD` or `ITERATION_CAP` long before 4 hours), editable per repo (FR-022,
> SC-007). The exact numbers above are the shipping defaults; teams raise them as needed.

## Example

```sh
# .agent/budget.conf — per-task cost-budget guardrail for workflows.
# Read by .claude/workflows/lib/budget-breaker.js. Absent file ⇒ no enforcement (opt-in).
BUDGET_ENABLED=true

# Per-task ceilings (notional USD at API rates; soft alerts, hard aborts).
PERTASK_SOFT_USD=3.00      # alert, continue
PERTASK_HARD_USD=5.00      # abort the run
# PERTASK_HARD_TOKENS=2000000

# Aggregate ceiling across all tasks in one workflow run.
PERWORKFLOW_HARD_USD=15.00

# Catch slow loops of cheap steps before excessive wall-clock time.
ITERATION_CAP=40

# Pricing — maintained external table, never hardcoded.
PRICE_TABLE_SOURCE=litellm
PRICE_TABLE_MAX_AGE_HOURS=168
PRICE_TABLE_FALLBACK=assume-max   # block | assume-max | warn-continue
```

## Validation rules (fail closed)

- `PERTASK_SOFT_USD < PERTASK_HARD_USD`; if `PERWORKFLOW_HARD_USD` set, it is `≥ PERTASK_HARD_USD`.
- `ITERATION_CAP ≥ 1`.
- `PRICE_TABLE_FALLBACK ∈ {block, assume-max, warn-continue}`.
- Any malformed/contradictory value ⇒ the workflow **refuses to start** with a clear message (a typo
  must never silently disable the guardrail — Constitution IV).

## Behavioral contract

1. On run start, the breaker reads this file. If missing or `BUDGET_ENABLED=false`, it is a no-op and
   the workflow runs exactly as today (FR-013, SC-005).
2. Between every `agent()` step, accumulated notional cost is compared to soft then hard thresholds, and
   `iterations` to `ITERATION_CAP` (FR-008/009/012).
3. Crossing soft ⇒ one alert, run continues. Crossing hard or the cap ⇒ abort before the next step, with
   a report naming the breached threshold (FR-009/010).
