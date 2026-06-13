# Quickstart: Budget Guardrail & Observability

How an operator turns the feature on and verifies it — the manual happy path plus the two tests that
prove the guardrail actually fires. Mirrors the spec's three Independent Tests.

## 1. Turn on the budget guardrail (P1 — the MVP)

The scaffolder emits `.agent/budget.conf` with conservative defaults, so a freshly scaffolded repo is
already bounded (FR-022). To adopt it in this repo, drop the file in and tune it:

```sh
cp .agents/skills/scaffold-agent-project/assets/project-files/budget.conf .agent/budget.conf
# edit ceilings if needed; defaults: soft $3 / hard $5 per task, 40-step iteration cap
```

Run a workflow as usual — the breaker now accumulates model-aware notional cost between agent steps:

```sh
node .claude/workflows/feature-pipeline.js '{"feature":"..."}'
# soft threshold crossed  -> "[budget] soft alert: $3.10 of $5.00 (notional)" — run continues
# hard threshold crossed  -> run ABORTS before the next step, reports spend + breached threshold
```

To confirm it is **opt-in / non-breaking**: `rm .agent/budget.conf` (or set `BUDGET_ENABLED=false`) and
the workflow behaves exactly as before (SC-005).

## 2. Verify a budget actually aborts a run (Independent Test for User Story 1 / SC-001, SC-007)

This is the guardrail gate — "it must fire in a fixture, not just exist."

```sh
sh tests/budget-breaker.fixture.sh
```

The fixture sets a deliberately tiny ceiling (e.g. `PERTASK_HARD_USD=0.01`), feeds a **stub usage log**
whose tokens cost more than that, runs the breaker, and asserts:
- the run reaches `status=aborted-on-budget`,
- `breachedThreshold` is reported,
- a `BudgetRecord` was written to `.agent/budget/runs/` with the spend at abort time.
It also asserts the **iteration cap** aborts a loop of sub-threshold steps (the "cheap loop" edge case).

## 3. Verify notional-cost accuracy (FR-004, SC-004, SC-006)

```sh
node --test tests/cost-engine.test.js        # per-token-type rates incl. cache-read/write
node --test tests/notional-accuracy.test.js  # engine total vs a ccusage-derived baseline
```

`cost-engine.test.js` asserts cache-read and cache-write are costed at **their own** rates, not the
input rate. `notional-accuracy.test.js` parses a fixture `*.jsonl` and checks the engine's total
matches a `ccusage`-derived figure within tolerance, and that the output is labeled **notional**.

## 4. Turn on live observability (P0 — optional, local-first)

```sh
cp .agents/skills/scaffold-agent-project/assets/observability/env.observability.example .env.observability
# enables CLAUDE_CODE_ENABLE_TELEMETRY=1 (+ enhanced-telemetry beta for spans)
docker compose -f .agents/skills/scaffold-agent-project/assets/observability/docker-compose.yml up -d
# OTel collector + Arize Phoenix come up locally
```

Start a long-running workflow, open the Phoenix UI, and confirm (Independent Test for User Story 2):
- current phase/step, per-agent token + notional-cost totals, recent tool calls, run status — **live**,
- usage attributed per agent/subagent/skill (`query_source` / `agent.name` / `skill.name`),
- after the run ends, final per-agent totals remain for after-the-fact inspection.

No usage data leaves the host (FR-018). The guardrail in steps 1–3 works **with this turned off**
(FR-006, FR-014) — the breaker reads local logs, not the collector.

## 5. Inspect the run ledger (P2 foundation — User Story 3 / SC-002)

```sh
cat .agent/budget/runs/*.ndjson | jq '{runId, workflowType, status, totalNotionalCostUsd, breachedThreshold}'
```

Every completed **or** aborted run has a record with total + per-agent notional cost, workflow type,
task id, and (if aborted) the breached threshold. This is the durable data the future P2 "was it worth
the tokens?" analytics layer would read — that analytics/judgment UI is **out of scope here**.
