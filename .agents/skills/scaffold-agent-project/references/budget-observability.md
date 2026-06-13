# Budget guardrail & observability preset (loaded on activation)

This reference is for the optional, agent-agnostic **cost guardrail + observability** feature the
scaffolder can emit. It is loaded only when you turn the preset on (Constitution V — progressive
disclosure). Two independent layers; either can run without the other.

## Layer 1 — Budget guardrail (P1, the MVP, always-safe-by-default)

A small, agent-neutral **cost core** lives under `.claude/workflows/lib/`:

| File | Role |
|---|---|
| `price-table.js` | Loads LiteLLM-style per-model, per-token-type rates from a cached `model_prices_and_context_window.json`. **Fail-safe**: a missing/stale rate is never $0 — it applies the configured fallback (`block` / `assume-max` / `warn-continue`). |
| `cost-engine.js` | Pure `Σ(tokens_by_type × rate)`. Cache-read (~0.1× input) and cache-write (~1.25–2× input) are costed at **their own** rates. |
| `usage-source.js` | The **only** agent-specific module: parses `~/.claude/projects/**/*.jsonl` (ccusage-style) into neutral `UsageEvent`s. A Codex/opencode adapter implements the same `readUsageSince` signature. Works with telemetry OFF. |
| `budget-breaker.js` | The `CostCircuitBreaker`: accumulates notional cost between agent steps, fires a **soft alert once**, then **hard-aborts** before the next step on the cost ceiling / token ceiling / per-workflow aggregate / **iteration cap**. Extends the runtime `budget` primitive. |
| `budget-record.js` | Appends one NDJSON `BudgetRecord` per run end (completed **or** aborted) to `.agent/budget/runs/<date>.ndjson` — the durable cost ledger. |

Config: **`.agent/budget.conf`** (a shell-sourceable `KEY=value` file). Absent ⇒ no enforcement
(opt-in). The scaffolder ships **conservative defaults** (soft $3 / hard $5 per task, 40-step
iteration cap, `assume-max` fallback) so a fresh repo cannot run away. Validation **fails closed**:
a typo (e.g. `soft >= hard`, `ITERATION_CAP < 1`, an out-of-enum fallback) makes the workflow refuse
to start rather than silently disabling the guardrail.

**Prove it fires**: `sh tests/budget-breaker.fixture.sh` — a tiny ceiling + a stub usage stream
must force a hard abort (soft alert first) and the iteration cap must trip a cheap loop.

## Layer 2 — Observability (P0, opt-in, local-first)

Turn on the reference agent's **native OpenTelemetry** export and a local dashboard. No usage data
leaves the host (FR-018), and the guardrail above keeps working with this OFF (FR-006/FR-014).

```sh
cp assets/observability/env.observability.example .env.observability
set -a && . ./.env.observability        # CLAUDE_CODE_ENABLE_TELEMETRY=1 + spans beta
docker compose -f assets/observability/docker-compose.yml up -d   # OTel Collector + Phoenix
# open http://localhost:6006  (Phoenix: live agent graph, per-agent token/cost, tool calls)
```

- **Phoenix** (Apache-2.0) is the default agent-trace view.
- **Grafana + Prometheus** are an *optional* token/cost-panel preset behind the `metrics` profile.
  Grafana is **AGPL (copyleft)** — flagged, never a core dependency:
  `docker compose --profile metrics -f assets/observability/docker-compose.yml up -d`.

Built on OTel GenAI semantic conventions. Claude Code emits `claude_code.token.usage` (by `type` +
`model`), `claude_code.cost.usage` (USD), and per-subagent-attributed spans (`query_source`,
`agent.name`, `skill.name`).

## What's intentionally NOT here (P2)

The per-run `BudgetRecord` ledger is the durable **data foundation** for a future "was it worth the
tokens?" analytics view. That judgment/UI layer is out of scope — only the data capture is built.
