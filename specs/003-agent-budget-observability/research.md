# Phase 0 Research: Agent Observability & Per-Task Cost-Budget Guardrail

This phase resolves the Technical Context unknowns and records the load-bearing technology decisions.
Each item: **Decision → Rationale → Alternatives considered**. There are **no remaining
NEEDS CLARIFICATION** — the spec's one open question (default ceiling) was resolved in its
Clarifications session (ship a conservative default).

---

## R1. Price-table source (per-model, per-token-type rates)

**Decision**: Reference **LiteLLM's `model_prices_and_context_window.json`** (MIT) as the maintained
price table; cache it locally with a fetched-at timestamp; expose `tokencost` (same underlying data) as
a documented drop-in alternative. Rates are read at run start, never hardcoded (FR-003).

**Rationale**: It is broadly adopted, permissively licensed, and explicitly tracks **per-token-type**
rates — `input`, `output`, `cache_read_input_token_cost`, `cache_creation_input_token_cost` — which is
exactly what FR-002 and the cache-heavy-runs edge case require (cache-read ≈ 0.1× input; cache-write ≈
1.25–2× input). It is updated as vendors change pricing, satisfying SC-004's "rates update without code
changes."

**Alternatives considered**: Hardcoding rates (rejected — violates FR-003, goes stale silently);
scraping vendor pricing pages (rejected — brittle, no stable schema); `tokencost` as primary (kept as
alternative — it is a thin wrapper over the same LiteLLM data, so the underlying table is the real
dependency).

## R2. Notional cost on a subscription (no per-token bill)

**Decision**: Compute **notional cost** by parsing the reference agent's local usage logs at
`~/.claude/projects/**/*.jsonl`, following the parse pattern established by **`ccusage`**, then applying
R1 rates. Label every such figure **notional** (vs **billed**) wherever it is reported (FR-004, SC-006).

**Rationale**: A subscription emits no dollar figure, but the JSONL logs record per-message token
counts by type and the model used — enough to reconstruct "what this would cost at API rates."
`ccusage` is the de-facto reference for this exact computation, so following its parse keeps us
"adopt, don't reinvent" (Constitution VI) and gives us a baseline to validate against (FR-004 test).

**Alternatives considered**: API-only billed cost (rejected — leaves subscription users, the motivating
case, with no number); estimating from output text length (rejected — ignores cache + input tokens,
wildly inaccurate).

## R3. Usage source that works with telemetry OFF

**Decision**: The budget guardrail reads usage from the **local JSONL logs** (R2), **not** from the
OTel pipeline. Telemetry/observability (Capability C) is a separate, optional consumer of the same
underlying usage; the guardrail never depends on it (FR-006, FR-014, edge case "telemetry disabled").

**Rationale**: The spec is explicit that enforcement must survive a downed collector. Local logs are
always present when the agent runs; the OTel exporter is opt-in and may be off. Decoupling enforcement
from observability is the safe design.

**Alternatives considered**: Driving the breaker off live OTel metrics (rejected — couples the kill-
switch to an optional pipeline; a collector outage would disable the guardrail, the opposite of fail-
safe).

## R4. The accumulation + abort mechanism (CostCircuitBreaker)

**Decision**: A lightweight **CostCircuitBreaker** that, **between agent steps**, reads new usage
events since the last check, costs them via the cost engine, accumulates against the per-task and
per-workflow ceilings, fires the **soft alert** when the soft threshold is crossed (run continues), and
**aborts before the next `agent()` call** when the hard ceiling — or the independent **iteration cap**
— is crossed (FR-008/009/012). Pair it with the runtime `budget` primitive so `agent()` throws on
breach.

**Rationale**: Checking between steps (not mid-token-stream) is the only place a workflow can cleanly
short-circuit, and it bounds overshoot to one in-flight step (SC-001). An iteration cap independent of
cost catches the "many cheap steps" loop edge case. This is a well-known, minimal pattern — far simpler
than a proxy.

**Alternatives considered**: A **LiteLLM proxy with per-task virtual-key `max_budget`** (kept as a
documented heavier alternative for teams already running a gateway — it enforces at the network edge,
but adds an always-on service and isn't needed for the in-process MVP); mid-stream cancellation
(rejected — not exposed by the runtime, can't pause a token stream).

## R5. Extending the existing `budget` primitive (not reinventing)

**Decision**: **Extend** the runtime's existing `budget` primitive (`budget.total`, `budget.spent()`,
`budget.remaining()`, `agent()` failing once spent ≥ total) so that the **spend measure** is model- and
token-type-aware **cost** (from the cost engine) rather than a raw output-token count, and so ceilings
can be **scoped per task** rather than only per run (FR-011).

**Rationale**: The spec's Assumptions state the primitive already exists; the constitution forbids
reinventing what we can extend. The breaker (R4) supplies the cost into `budget.spent()`; the per-task
scope is a new layer over the existing per-run total.

**Alternatives considered**: A standalone budget module ignoring the primitive (rejected — duplicates
the existing API, diverges from what the curriculum teaches, violates VI).

## R6. Observability stack (P0, local-first)

**Decision**: Enable the reference agent's **native OpenTelemetry** export
(`CLAUDE_CODE_ENABLE_TELEMETRY=1`, plus the enhanced-telemetry beta for **spans/traces**) → a local
**OTel Collector** → a self-hosted dashboard: **Arize Phoenix** (Apache-2.0; live agent-graph /
trace-waterfall view) as the default, with **Grafana + Prometheus** offered as an *optional* preset for
token/cost panels and threshold alerts. Shipped by the scaffolder as a `docker-compose.yml`. Built on
**OTel GenAI semantic conventions**. No usage data leaves the host (FR-017, FR-018).

**Rationale**: Claude Code emits metrics (`claude_code.token.usage` by `type` + `model`;
`claude_code.cost.usage` USD) and **per-subagent-attributed** spans (`query_source` = main/subagent,
`agent.name`, `skill.name`) — satisfying FR-005/FR-015/FR-016 with **near-zero custom code**. Phoenix
is purpose-built for agent traces and is permissive. Local-first compose keeps telemetry on the host.

**Alternatives considered**: **Jaeger** (kept as an alternative trace-waterfall backend — fine, but
Phoenix's agent-graph view maps better to the "check in on a running agent" scenario); a hosted SaaS
(rejected — FR-018 requires local-first). **Grafana is AGPL**, so it is offered only as a flagged,
optional preset, never a core dependency (Constitution Licensing constraint).

## R7. Conservative default ceiling (the clarified decision)

**Decision**: The scaffolder ships `.agent/budget.conf` with a **conservative default** per-task /
per-workflow ceiling — low enough to stop a runaway, user-tunable, with a **soft alert firing before
the hard abort** — so a freshly scaffolded repo is bounded with zero configuration (FR-022, SC-007).
The concrete default value is a small notional-dollar figure (e.g. on the order of a few dollars per
task) plus an iteration cap; the exact number is set in the config contract and is trivially editable.

**Rationale**: The spec's Clarifications session explicitly rejected "no default / require opt-in": a
fresh repo must not be able to run away. A conservative-but-tunable default is safe-by-default
(Constitution IV) without surprising teams that legitimately need a larger budget.

**Alternatives considered**: No default / require each project to set one (rejected by clarification —
leaves a fresh repo unbounded); a high default (rejected — wouldn't stop the motivating 4-hour
runaway).

## R8. Fail-safe pricing (missing/stale table)

**Decision**: If the price table is unavailable, stale, or lacks an entry for an in-use model, the cost
engine applies a configured **fallback policy** from `budget.conf` (one of: `block` — refuse to start /
abort; `assume-max` — cost the unknown model at a conservative high rate; `warn-continue` — surface the
gap and proceed) and **never** treats unknown cost as $0 (FR-019). Staleness is judged against the
cached fetched-at timestamp and a configurable max-age.

**Rationale**: Silently costing at $0 would defeat the guardrail (the spec calls this out directly).
Making the policy configurable lets cautious repos `block` while others `warn-continue`.

**Alternatives considered**: Always hard-fail on any gap (rejected — too brittle for new models that
just aren't in the table yet); silently default to $0 or to input rate (rejected — FR-019).

## R9. Where the per-task record lives (P2 foundation)

**Decision**: On every run end (completed **or** aborted-on-budget), write a **per-task budget record**
as one NDJSON line under `.agent/budget/runs/` capturing total + per-agent notional cost, token
breakdown, workflow type, task id, final status, and breached threshold (FR-020, SC-002). This is the
durable ledger the future P2 analytics layer reads; **no analytics UI is built here**.

**Rationale**: NDJSON append is the simplest durable, greppable, diff-friendly store consistent with the
repo's file-first, no-database posture; it is the minimum data capture that makes P2 possible without
building P2.

**Alternatives considered**: SQLite/DB (rejected — over-engineered for single-machine, against the
file-first posture); only logging to stdout (rejected — not durable, fails SC-002).

---

## Deferred (flagged for the lockstep/agnosticism gates, NOT built in this feature)

- **Curriculum lessons** explaining the budget guardrail + observability preset (Constitution III) —
  authored later via the `author-curriculum` skill; noted so the gate is satisfiable.
- **Second-agent adapter** (Codex/opencode usage-log + telemetry mapping) to prove the agnosticism gate
  — the core is built agent-neutral now; the second adapter is verified before "done" but is not P1.
- **`create-mvp` workflow** — referenced by the spec but not yet present in `.claude/workflows/`; the
  breaker wiring is written so it applies uniformly when that workflow lands.
