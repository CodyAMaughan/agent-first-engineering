# Implementation Plan: Agent Observability & Per-Task Cost-Budget Guardrail for Workflows

**Branch**: `003-agent-budget-observability` | **Date**: 2026-06-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-agent-budget-observability/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Give the Workflow orchestrator (`.claude/workflows/*.js` — `feature-pipeline`, `qa-loop`, future
`create-mvp`) an enforced, model-aware cost ceiling and live visibility, delivered as **one optional,
agent-agnostic feature** the scaffolder can emit into any agent-first repo.

The technical approach, in three phases matching the spec's priorities:

- **P0 — Observability (near-zero custom code):** the scaffolder emits an opt-in preset that turns on
  the reference agent's native OpenTelemetry export (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, plus the
  enhanced-telemetry beta for spans) and a local-first `docker-compose` collector + dashboard
  (Arize Phoenix for the live agent-graph view; optional Grafana/Prometheus for token/cost panels and
  threshold alerts). No usage data leaves the host.
- **P1 — Budget guardrail (the MVP):** a small, portable **cost engine** computes notional cost as
  `Σ(tokens_by_type × price_for(model, token_type))` using rates pulled from a maintained external
  **price table** (never hardcoded), reading the reference agent's local usage logs
  (`~/.claude/projects/**/*.jsonl`, the way `ccusage` does) so it works with telemetry off. A
  **CostCircuitBreaker** accumulates cost per agent step and **extends the runtime's existing `budget`
  primitive** (`budget.total` / `budget.spent()` / `budget.remaining()`, `agent()` throwing once spent
  ≥ total) to be model- and token-type-aware and **per-task scoped**, with a **soft-alert** threshold
  (continue) below a **hard-abort** ceiling (short-circuit), plus an independent **iteration cap**.
  All of it configured via a new optional **`.agent/budget.conf`**, with a **conservative default
  ceiling shipped by the scaffolder** so a fresh repo cannot run away.
- **P2 — Cost-per-task analytics (forward-looking, not built here):** a **per-task budget record**
  (notional-cost ledger) written for every run — the durable data foundation a future "was it worth the
  tokens?" view would build on. P1 writes the record; the judgment/UI layer is out of scope.

The HOW stays implementation-agnostic where the design wants (the cost engine and config schema are
agent-neutral) but technically specific about the substrate (OTel GenAI conventions, the LiteLLM price
table, the `ccusage` JSONL parse, the existing `budget` primitive).

## Technical Context

**Language/Version**: JavaScript (ES modules) for the Workflow runtime + cost engine, matching the
existing `.claude/workflows/*.js` orchestrator; POSIX **sh** for the scaffolder hooks and the
`budget.conf` reader, matching `.agent/hooks/*.sh`. No new language is introduced.

**Primary Dependencies**:
- The existing **Workflow runtime** (`agent()`, `phase()`, `log()`, `parallel()`, and the `budget`
  primitive it exposes) — extended, not replaced.
- A maintained **external price table**: LiteLLM `model_prices_and_context_window.json` (MIT) as the
  reference source, with `tokencost` (a thin wrapper over the same data) as a documented alternative.
- **OpenTelemetry** (the reference agent's native OTLP export; OTel GenAI semantic conventions) +
  a local **OTel Collector** and a self-hosted dashboard (**Arize Phoenix**, Apache-2.0; optional
  **Grafana/Prometheus**, AGPL/Apache — Grafana flagged as optional, not a core dependency, since its
  license is copyleft).
- The reference agent's **local usage logs** (`~/.claude/projects/**/*.jsonl`), parsed the way the
  permissively-licensed **`ccusage`** tool does (referenced as the parse pattern of record).

**Storage**: Files only. Read-only inputs: the agent's `*.jsonl` usage logs and the cached price
table. Written outputs: a **per-task budget record** appended to a run ledger (newline-delimited JSON
under a repo-local path, e.g. `.agent/budget/runs/`); a cached copy of the price table with a
fetched-at timestamp for staleness checks. No database.

**Testing**: Node's built-in test runner / plain assertion scripts for the cost engine + breaker
(unit), and shell-driven **fixture** tests for the guardrail (a deliberately-low ceiling + a stub
usage log that must force an abort) — consistent with `tests/*.sh` and the repo's "guardrails must
actually fire in a fixture" gate. `mkdocs build --strict` + `tests/validate.sh` remain the doc/agent-
layer gates.

**Target Platform**: Local developer machine / CI runner (macOS + Linux). The observability stack runs
in Docker locally; the guardrail and cost engine run in-process with the workflow and require no
container.

**Project Type**: Agent-first tooling layer (orchestrator runtime extension + scaffolder preset +
deterministic config/hooks) — not a web/mobile app. Single-project structure.

**Performance Goals**: Cost accounting adds negligible overhead relative to a model round-trip — the
breaker check between agent steps must be **O(usage events since last check)** and complete in well
under the per-step model latency (target < ~50 ms/check). The guardrail must abort **before the next
agent step starts** (SC-001: overshoot bounded to one in-flight step). The live view must reflect a
running run's per-agent totals within seconds (SC-003).

**Constraints**:
- **Opt-in / non-breaking**: absent `.agent/budget.conf`, workflow behavior is byte-for-byte unchanged
  (FR-013, SC-005). Observability is a separate opt-in preset (FR-017).
- **Local-first**: no requirement to ship usage data to any third-party hosted service (FR-018).
- **Agent-agnostic core**: the cost engine + config schema must not hardcode one agent's paths/syntax;
  the JSONL/telemetry specifics live in an adapter (FR-021, Constitution II).
- **Fail-safe pricing**: a missing/stale price-table entry must never be silently treated as $0
  (FR-019).
- **License**: every adopted dependency MIT/Apache/BSD-equivalent; copyleft (Grafana) only as an
  optional, clearly-flagged preset (Constitution VI + Licensing constraints).

**Scale/Scope**: Three reference workflows; a handful of agents/subagents per run; usage logs on the
order of MBs/run. The accumulation is linear in usage events. This is single-machine, single-operator
scale — no multi-tenant or distributed concerns.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How this plan complies |
|---|---|---|
| **I. Open Standards First** | PASS | Budget config is a portable `.agent/*.conf` + an agent-neutral cost engine; observability rides **OTel GenAI semantic conventions** (open standard), not a proprietary format. Claude-specific paths (`~/.claude/.../*.jsonl`, the telemetry env vars) live in a thin **adapter**, never the core. |
| **II. Agent-Agnostic by Construction** | PASS | Core cost engine + `budget.conf` schema are agent-neutral; per-agent usage-log location and telemetry env are an adapter seam. Claude Code is the reference target; portability to Codex/opencode is verified at the adapter boundary (Agnosticism gate). |
| **III. Teach and Generate in Lockstep** | PASS (deferred items noted) | The scaffolder emits the preset (`budget.conf` + breaker wiring + OTel compose); the curriculum's orchestration/harness + production phases explain it. Curriculum lesson updates are **out of this feature's build scope** but flagged in research.md so the lockstep gate is satisfied when authored. |
| **IV. Guardrails Over Vibes (NON-NEGOTIABLE)** | PASS | The ceiling is a **deterministic** CostCircuitBreaker + iteration cap that aborts the run, plus a fixture test proving it fires — not prose. The conservative default ceiling means safety isn't opt-in. |
| **V. Minimal Context, Progressive Disclosure** | PASS | `budget.conf` is short and command-first like the other `.agent/*.conf`; deep reference (price-table mechanics, OTel setup) lives in scaffolder `references/`, loaded only when enabling the preset. |
| **VI. Adopt, Don't Reinvent** | PASS | Prices from **LiteLLM**'s maintained table; usage parse follows **`ccusage`**; observability is **OTel + Phoenix** — all mature/permissive. New code is limited to the glue (cost engine, breaker, config reader) where no drop-in exists. |
| **VII. Specs Are the Source of Truth** | PASS | This plan is generated from the clarified spec; no implementation precedes it. |

**Result**: PASS — no violations. Complexity Tracking is empty. (Re-checked after Phase 1: still PASS;
the design adds one config file, one adapter seam, and one ledger path, no new projects or patterns.)

## Project Structure

### Documentation (this feature)

```text
specs/003-agent-budget-observability/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── budget.conf.schema.md     # the budget config contract
│   ├── cost-engine.md            # price-table adapter + cost-engine API contract
│   └── budget-record.schema.md   # per-run ledger record contract
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
.claude/workflows/                 # the Workflow orchestrator (reference-agent rendering)
├── feature-pipeline.js            # EXTEND: wrap agent() steps with the budget breaker
├── qa-loop.js                     # EXTEND: same breaker wiring + iteration cap
└── lib/
    ├── cost-engine.js             # NEW: notional-cost computation (Σ tokens×rate), agent-neutral
    ├── price-table.js             # NEW: price-table adapter (fetch/cache/staleness, fallback policy)
    ├── usage-source.js            # NEW: adapter — read reference-agent JSONL usage logs (ccusage-style)
    ├── budget-breaker.js          # NEW: CostCircuitBreaker (soft/hard thresholds, iteration cap)
    └── budget-record.js           # NEW: write the per-task budget record to the run ledger

.agent/
├── budget.conf                    # NEW (scaffolder-emitted): ceilings, thresholds, price-table source,
│                                  #   iteration cap, fallback policy — with a CONSERVATIVE DEFAULT
└── budget/
    ├── price-table.cache.json     # cached price table + fetched-at (gitignored)
    └── runs/*.ndjson              # per-task budget records (the P2 ledger foundation)

.agents/skills/scaffold-agent-project/   # the portable scaffolder (open-standard source of truth)
├── assets/
│   ├── project-files/budget.conf        # NEW: the conservative-default config the scaffolder emits
│   └── observability/                   # NEW: opt-in P0 preset
│       ├── docker-compose.yml           #   OTel collector + Phoenix (+ optional Grafana/Prometheus)
│       ├── otel-collector.yaml          #   OTLP receiver → exporters config
│       └── env.observability.example    #   CLAUDE_CODE_ENABLE_TELEMETRY etc.
└── references/budget-observability.md   # NEW: how the preset works (loaded on activation only)

tests/
├── budget-breaker.fixture.sh      # NEW: low ceiling + stub usage log MUST force an abort (SC-001/SC-007)
├── cost-engine.test.js            # NEW: per-token-type rates incl. cache-read/write (SC-004)
└── notional-accuracy.test.js      # NEW: cost-engine total vs a ccusage-derived baseline (FR-004)
```

**Structure Decision**: Single-project, agent-first tooling layer. The new code lands in three places
that already exist in the repo: the **runtime** (`.claude/workflows/lib/`, new — the orchestrator code
that the cost engine/breaker plug into), the **config + ledger** (`.agent/`, alongside the existing
`guardrails.conf`/`qa.conf`/hooks), and the **portable scaffolder assets** (`.agents/skills/scaffold-
agent-project/assets/`, mirrored to `.claude/` per the byte-identical-mirror rule). The cost engine,
price-table adapter, and config schema are the agent-neutral core; the JSONL usage reader and the OTel
env/compose are the per-agent adapter edge. No new top-level project or language is introduced.

## Complexity Tracking

> No constitution violations. This section intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
