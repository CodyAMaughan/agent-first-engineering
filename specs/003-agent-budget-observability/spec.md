# Feature Specification: Agent Observability & Per-Task Cost-Budget Guardrail for Workflows

**Feature Branch**: `003-agent-budget-observability`

**Created**: 2026-06-13

**Status**: Draft

**Input**: User description: "Agent observability & per-task cost-budget guardrail for workflows"

## Overview

The agent-first Workflow orchestrator (the `.claude/workflows/*` scripts — `feature-pipeline`,
`qa-loop`, `create-mvp`) drives multi-agent runs that can consume large amounts of model tokens.
Today a run has no enforced ceiling and almost no live visibility: a recent `qa-loop` ran roughly
**four hours unbounded** because nothing capped its token or notional-cost spend, and operators
could only inspect it through the basic `/workflows` view and by reading git commits after the fact.

This feature standardizes three related, independently valuable capabilities for those workflows,
delivered as **one optional feature** that the scaffolder (`scaffold-agent-project`) can emit into any
agent-first repo:

1. **Token/cost tracking** — per workflow and per agent, including a **notional cost** for
   subscription accounts where there is no per-token bill.
2. **Budget guardrail / kill-switch** (the primary deliverable / MVP) — per-task and per-workflow
   ceilings on tokens and/or notional cost, with soft alerts and hard aborts so a run cannot become a
   surprise runaway.
3. **Observability** — live "check in on a running agent" visibility into in-flight workflows: phase,
   current step, per-agent tokens and cost, tool calls, and status.

Phasing (explicit): **P0 = observability** (near-zero build, enable existing telemetry + a local
dashboard), **P1 = budget guardrail** (the MVP, extends the runtime's existing `budget` primitive),
**P2 = cost-per-task analytics** (forward-looking, framed as an emerging bet, not part of the MVP).

The spec describes **what** these capabilities must do and **why**, not how to build them.

## Clarifications

### Session 2026-06-13
- Q: Should the scaffolder ship a default cost/token budget ceiling, or require each project to set one? → A: **Ship a conservative default** ceiling out of the box (safe by default) — low enough to stop a runaway, user-tunable, with a soft-alert before the hard abort. A fresh repo must not be able to run away.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A runaway workflow is aborted at its budget ceiling (Priority: P1)

An operator starts a workflow with a configured per-task budget ceiling. As the workflow's agents
consume tokens, their spend is accumulated against the ceiling using model- and token-type-aware
pricing. When accumulated spend crosses the **hard** threshold, the workflow short-circuits: the
current and any pending agent steps stop, and the run reports the tokens and notional cost spent and
the threshold that was crossed.

**Why this priority**: This is the MVP and the motivating pain. It directly prevents the four-hour
runaway class of failure. Without it, every other capability is observation without control.

**Independent Test**: Configure a deliberately low per-task ceiling, run a workflow that would
otherwise exceed it, and confirm the run aborts at the ceiling and emits a report stating tokens +
notional cost spent and the breached threshold — testable with no observability dashboard present.

**Acceptance Scenarios**:

1. **Given** a workflow with a hard per-task budget ceiling, **When** accumulated spend reaches or
   exceeds the ceiling, **Then** the workflow aborts before starting the next agent step and reports
   the tokens and notional cost spent plus the breached threshold.
2. **Given** a workflow with a **soft** threshold below the hard ceiling, **When** spend crosses the
   soft threshold, **Then** an alert is surfaced to the operator and the run **continues**.
3. **Given** a workflow with no budget configuration present, **When** it runs, **Then** behavior is
   unchanged from today (the guardrail is opt-in and does not break existing workflows).
4. **Given** a workflow on a Claude subscription (no per-token bill), **When** spend is evaluated,
   **Then** the ceiling is enforced against a **notional cost** computed at API rates.

---

### User Story 2 - A developer checks in on a running workflow live (Priority: P2)

While a workflow is in flight, a developer opens a live view and sees, without stopping the run, its
current phase and step, per-agent token and cost totals, recent tool calls, and overall status — so
they can decide whether to let it continue or stop it.

**Why this priority**: This is the P0 "enable what already exists" win in build effort but is ranked
P2 for *enforcement value* (it observes, it does not control). It makes runaways visible early and
makes the budget guardrail's decisions auditable.

**Independent Test**: Start a long-running workflow, open the live view, and confirm per-agent
tokens/cost, current step, and status update while the run is still executing — testable independently
of whether any budget ceiling is configured.

**Acceptance Scenarios**:

1. **Given** a running workflow, **When** the developer opens the live view, **Then** they see the
   current phase/step, per-agent token and notional-cost totals, recent tool calls, and run status.
2. **Given** a workflow with multiple agents/subagents, **When** the developer inspects the view,
   **Then** token and cost usage is attributed to the specific agent, subagent, or skill responsible.
3. **Given** a workflow that has finished, **When** the developer opens the view, **Then** the final
   per-agent totals and the run's total notional cost remain available for after-the-fact inspection.

---

### User Story 3 - Every workflow run records its notional cost (Priority: P2)

When any workflow run completes (or aborts), the system records that run's total notional cost and
per-agent breakdown, tagged with which workflow produced it (feature-pipeline / create-mvp / qa-loop)
and the task it served, so totals can be reviewed later.

**Why this priority**: It is the durable record that makes both the guardrail's reports and the future
analytics layer possible. It is foundational data capture, not yet the judgment layer.

**Independent Test**: Run any workflow to completion and confirm a per-run record exists capturing
total notional cost, per-agent breakdown, the workflow type, and the associated task.

**Acceptance Scenarios**:

1. **Given** any completed workflow run, **When** it finishes, **Then** a record exists with its total
   notional cost, per-agent breakdown, workflow type, and associated task identifier.
2. **Given** a workflow run that was aborted by the budget guardrail, **When** it ends, **Then** a
   record is still written marking it aborted-on-budget with the spend at abort time.

---

### Edge Cases

- **Missing or stale price table**: the maintained price table is unavailable or lacks an entry for a
  model in use. The system must behave predictably (see FR-019) rather than silently treating cost as
  zero, which would defeat the guardrail.
- **Mid-step crossing**: a single agent step's usage pushes spend well past the ceiling in one jump.
  The guardrail must still abort (it cannot pause mid-token-stream) and report the actual overshoot.
- **Looping with tiny per-step cost**: a loop runs many cheap steps that individually never trip the
  ceiling but collectively waste time. An iteration/step cap must catch this independently of the cost
  ceiling.
- **Subscription vs. API account**: notional cost (subscription) vs. real billed cost (API) must be
  labeled so operators are not misled about what the number represents.
- **Telemetry disabled or collector down**: the budget guardrail must still function from local usage
  logs even when the live observability pipeline is unavailable.
- **Concurrent agents**: multiple agents spending in parallel against one shared per-task budget — the
  ceiling applies to the aggregate, not to any single agent in isolation.
- **Cache-heavy runs**: cache-read and cache-write tokens are priced very differently from input/output
  tokens and must be costed at their own rates, not at the input rate.

## Requirements *(mandatory)*

### Functional Requirements

#### Capability A — Token / Cost Tracking

- **FR-001**: The system MUST track token usage per workflow run and per individual agent/subagent
  within that run, broken down by token type (input, output, cache-read, cache-write).
- **FR-002**: The system MUST compute cost as the sum over token types of `tokens_by_type ×
  price_for(model, token_type)`, applying the correct rate for each model and each token type
  (cache-read priced well below input, cache-write priced above input).
- **FR-003**: Price rates MUST be sourced from a **maintained external price table** and MUST NOT be
  hardcoded in workflow logic, so rates stay current as models and pricing change.
- **FR-004**: For accounts with no per-token bill (e.g. a Claude subscription), the system MUST compute
  a **notional cost** — "what this run would cost at API rates" — for budgeting and reporting, and MUST
  label it as notional rather than billed.
- **FR-005**: The system MUST attribute usage to the responsible agent, subagent, or skill so that
  per-agent totals can be produced.
- **FR-006**: Usage tracking MUST be derivable from the agent's local usage logs so it works even when
  no live telemetry pipeline is running.

#### Capability B — Budget Guardrail / Kill-Switch (primary deliverable)

- **FR-007**: The system MUST support configurable budget ceilings scoped **per task** and **per
  workflow**, expressed as a token ceiling and/or a notional-cost ceiling.
- **FR-008**: The system MUST distinguish a **soft** threshold (raise an alert, continue the run) from a
  **hard** threshold (abort the run).
- **FR-009**: When a hard threshold is crossed, the system MUST short-circuit the run — stop launching
  further agent steps and terminate the current run — rather than letting it continue.
- **FR-010**: On abort, the system MUST report the tokens and notional cost spent and identify which
  threshold (task-level / workflow-level, token / cost) was breached.
- **FR-011**: The guardrail MUST extend the existing Workflow runtime budget primitive (`budget.total`,
  `budget.spent()`, `budget.remaining()`, with `agent()` failing once spent ≥ total) so that the spend
  measure is **model- and token-type-aware cost**, not merely output-token count, and so ceilings can be
  scoped per task rather than only per run.
- **FR-012**: The system MUST support an **iteration / step cap** alongside the cost ceiling, so loops
  that accumulate cost slowly are still caught before excessive wall-clock time elapses.
- **FR-013**: The guardrail MUST be configured via an **optional** `.agent/budget.conf` specifying
  per-stage / per-task ceilings, the price-table source, and the soft-alert vs. hard-abort thresholds;
  when this file is absent, existing workflow behavior MUST be unchanged.
- **FR-014**: Budget enforcement MUST function from local usage data even when the observability
  pipeline (Capability C) is disabled or unavailable.

#### Capability C — Observability ("check in on a running agent")

- **FR-015**: The system MUST provide a live view of in-flight workflows showing, per run: current
  phase, current step, per-agent token and notional-cost totals, recent tool calls, and run status.
- **FR-016**: Live usage data MUST be attributable per agent/subagent/skill, consistent with FR-005.
- **FR-017**: The observability configuration (enabling the agent's telemetry export, a local collector,
  and a self-hosted dashboard with token/cost views and threshold alerts) MUST be emittable by the
  scaffolder as an **optional** preset that an adopting repo can turn on or leave off.
- **FR-018**: The observability layer MUST be self-hostable / local-first (no requirement to send usage
  data to a third-party hosted service) so adopting repos retain control of their telemetry.

#### Cross-Cutting

- **FR-019**: When the price table is missing, stale, or lacks an entry for an in-use model, the system
  MUST fail safe — surface the gap to the operator and apply a configured fallback policy — and MUST NOT
  silently treat the unknown cost as zero.
- **FR-020**: Every workflow run MUST record its total notional cost and per-agent breakdown, tagged with
  the workflow type (feature-pipeline / create-mvp / qa-loop) and the associated task, including for runs
  that were aborted on budget.
- **FR-021**: All three capabilities MUST be **agent-agnostic** in their shared core and offered as an
  **optional** scaffolder feature, consistent with the project's open-standard-first, opt-in conventions
  (Claude Code is the reference target; the design must not hardcode a single agent's paths or syntax in
  the portable core).
- **FR-022**: The scaffolder MUST ship a **conservative default** per-task/per-workflow budget ceiling
  out of the box, so a freshly scaffolded repo is bounded even with no user configuration (safe by
  default). The default MUST be low enough to stop a runaway yet user-tunable (raise/lower in config),
  and a soft-alert MUST fire before the hard ceiling aborts. (No-default / require-opt-in is rejected:
  a fresh repo must not be able to run away.)

### Future Scope (NOT in this feature's MVP)

- **P2 — Per-task cost-vs-outcome analytics**: a notional-cost **ledger** that tags each workflow run so
  operators can later answer "was this task worth the tokens?" — the "judgment layer." Standardized
  FinOps-for-AI cost reporting is institution-backed (e.g. the FinOps Foundation / FOCUS, and DORA 2025
  findings), but **per-task engineering cost-vs-value dashboards are emerging / DIY**, so this is framed
  honestly as a forward bet. FR-020's per-run records are the data foundation this future layer would
  build on; the analytics and value-judgment UI themselves are explicitly out of scope here.

### Key Entities *(include if feature involves data)*

- **Budget configuration (`.agent/budget.conf`)**: optional, opt-in. Defines per-task and per-workflow
  /per-stage ceilings (token and/or notional-cost), the soft-alert and hard-abort thresholds, an
  iteration/step cap, and which maintained price-table source to use.
- **Price table (external, maintained)**: the source of per-model, per-token-type rates (input, output,
  cache-read, cache-write). Referenced, never hardcoded; the system tracks whether it is fresh.
- **Per-task budget record**: the durable record written for each run — total and per-agent token usage,
  notional cost, the workflow type, the associated task, the run's final status (completed / aborted-on-
  budget), and which threshold (if any) was breached.
- **Usage event**: a unit of token consumption attributed to a specific agent/subagent/skill within a
  run, broken down by token type — the raw material for tracking, the live view, and the per-task record.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A workflow that would otherwise overrun its configured ceiling is stopped at the ceiling
  — no run exceeds its hard budget by more than one in-flight agent step's worth of spend.
- **SC-002**: 100% of completed or aborted workflow runs have a per-run record capturing total notional
  cost, per-agent breakdown, workflow type, and associated task.
- **SC-003**: An operator can see a running workflow's current step and per-agent token/cost totals
  within seconds of opening the live view, while the run is still in progress.
- **SC-004**: Reported costs reflect per-model, per-token-type rates pulled from the maintained price
  table (cache-read and cache-write are not costed at the input rate), and rates update without code
  changes when the price table changes.
- **SC-005**: Repos with no budget configuration and observability left off see no change in existing
  workflow behavior — the feature is fully opt-in.
- **SC-006**: On a subscription account, reported spend is clearly labeled **notional** and is computed
  at API rates, so operators are not misled about whether the number is billed.
- **SC-007**: The motivating failure is eliminated: with a configured per-task budget, the previously
  unbounded ~4-hour runaway class of run is aborted at its ceiling instead of running unbounded.

## Assumptions

- The Workflow runtime already exposes the budget primitive described (`budget.total`, `budget.spent()`,
  `budget.remaining()`, and `agent()` failing once spent ≥ total); this feature **extends** that
  primitive rather than introducing budgeting from scratch.
- A maintained, permissively-licensed external price table (covering per-model, per-token-type rates) is
  available to be referenced; selecting the specific table is a planning-phase decision.
- The reference agent (Claude Code) can export per-run, per-agent usage both as local usage logs and as
  telemetry that a local collector and self-hosted dashboard can consume; the portable core stays
  agent-agnostic and per-agent specifics live in adapters.
- Operators on subscription plans want a notional cost for budgeting and analytics even though they are
  not billed per token; the notional figure is for control and insight, not for invoicing.
- Observability is local-first/self-hosted by default; sending usage data to any third-party hosted
  service is out of scope and not required.
- This is an optional scaffolder feature; adopting repos choose to enable it. Existing repos that do not
  enable it are unaffected.

## Dependencies

- The existing Workflow runtime budget primitive (extended by Capability B).
- A maintained external model price table for per-model, per-token-type rates (Capability A).
- The reference agent's usage logging and telemetry export (Capabilities A and C).
- The scaffolder (`scaffold-agent-project`), which emits this feature as an optional preset (FR-017,
  FR-021).
