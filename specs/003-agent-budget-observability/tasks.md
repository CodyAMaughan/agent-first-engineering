# Tasks: Agent Observability & Per-Task Cost-Budget Guardrail for Workflows

**Input**: Design documents from `/specs/003-agent-budget-observability/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (all present)

**Tests**: REQUESTED — strict TDD. Every unit of behavior gets a test FIRST (prove RED), then the
implementation (GREEN). Test tasks precede their implementation tasks within each story.

**Scope (per the orchestrator brief)**: P0 (observability preset, opt-in assets) + P1 (the budget
guardrail MVP) + P2 **data foundation only** (the NDJSON ledger writer; no analytics/UI).

**Organization**: grouped by user story. US1 = the budget kill-switch (MVP, P1). US2 = live
observability (P2, scaffolder assets only — no custom collector code). US3 = the per-run ledger
record (P2, data foundation).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (Setup/Foundational/Polish have no story label)

## Path Conventions

Agent-first tooling layer (single project). The cost core lands in `.claude/workflows/lib/`, config
in `.agent/`, scaffolder assets in `.agents/skills/scaffold-agent-project/assets/` (mirrored to
`.claude/`), tests in `tests/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: directories + ignore rules so the cost core, ledger, and cache have a home.

- [ ] T001 Create the cost-core directory `.claude/workflows/lib/` and the ledger/cache dir `.agent/budget/runs/` (with a `.gitkeep`) per plan.md "Project Structure".
- [ ] T002 Add gitignore rules for the transient cost artifacts (`.agent/budget/price-table.cache.json`, `.agent/budget/runs/*.ndjson`) to the repo `.gitignore` per data-model.md ("cache files are gitignored").

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the pieces every user story depends on — the config reader/validator and the price-table
adapter. No story can compute or enforce cost without these.

**⚠️ CRITICAL**: blocks US1 and US3.

### Tests (write FIRST, prove RED)

- [ ] T003 [P] Write `tests/cost-engine.test.js` config-reader cases (`node --test`): a valid `.agent/budget.conf` parses to the BudgetConfig shape; `soft >= hard` fails closed; `ITERATION_CAP < 1` fails closed; an out-of-enum `PRICE_TABLE_FALLBACK` fails closed; absent file ⇒ `{enabled:false}` no-op. Per contracts/budget.conf.schema.md "Validation rules (fail closed)". Confirm RED.
- [ ] T004 [P] Write `tests/cost-engine.test.js` price-table cases (`node --test`): `rateFor` returns the per-token-type rate for a known model; an unknown model under `assume-max` returns a conservative HIGH rate (never 0); under `block` it throws; `tableState` reports `missing` when no cache exists. Per contracts/cost-engine.md `price-table.js`. Confirm RED.

### Implementation

- [ ] T005 [US-shared] Implement `.claude/workflows/lib/budget-config.js` — POSIX-`KEY=value` reader + validator that fails closed (the JS twin of the `.conf` grammar in contracts/budget.conf.schema.md). Make T003 GREEN.
- [ ] T006 [US-shared] Implement `.claude/workflows/lib/price-table.js` — `loadPriceTable(config)`, `rateFor(table, model, tokenType)`, `tableState(table)`, honoring `PRICE_TABLE_FALLBACK` (`block`/`assume-max`/`warn-continue`), NEVER returning 0 for an unknown rate (FR-019). Reads LiteLLM-style `model_prices_and_context_window.json` keys (`input_cost_per_token`, `output_cost_per_token`, `cache_read_input_token_cost`, `cache_creation_input_token_cost`). Make T004 GREEN.

**Checkpoint**: config + pricing are testable; cost computation and enforcement can be built on them.

---

## Phase 3: User Story 1 — A runaway workflow is aborted at its budget ceiling (Priority: P1) 🎯 MVP

**Goal**: model- and token-type-aware notional cost accumulates between agent steps; a soft alert
fires once below the hard ceiling; the hard ceiling OR the iteration cap aborts the run before the
next step, naming the breached threshold.

**Independent Test**: `sh tests/budget-breaker.fixture.sh` — a tiny ceiling + a stub usage stream
forces a hard abort (soft alert first); the iteration cap trips a loop of cheap steps. Plus
`node --test tests/cost-engine.test.js` for per-token-type pricing accuracy.

### Tests for User Story 1 (write FIRST, prove RED) ⚠️

- [ ] T007 [P] [US1] `tests/cost-engine.test.js` — `costOf(event,table,config)`: cache-read is priced at `cacheReadPerToken` (≈0.1× input) and cache-write at `cacheWritePerToken` (≈1.25–2× input), NOT the input rate (SC-004); a hand-computed token-count→USD matches exactly. Confirm RED.
- [ ] T008 [P] [US1] `tests/notional-accuracy.test.js` — `totalCost` over a fixture event set matches a hand-derived ccusage-style baseline within tolerance, and the result is labeled **notional** (FR-004, SC-006). Confirm RED.
- [ ] T009 [P] [US1] `tests/cost-engine.test.js` — fail-safe: with the price table `missing` and `PRICE_TABLE_FALLBACK=assume-max`, `costOf` returns a conservative non-zero cost (never $0); with `block` it throws (FR-019). Confirm RED.
- [ ] T010 [US1] Write `tests/budget-breaker.fixture.sh` (shell, self-testing like `tests/check-qa-manifest.sh`): a tiny `PERTASK_HARD_USD` + a stub usage log whose cost exceeds it MUST drive the breaker to `aborted-on-budget` with `breachedThreshold` reported AND fire the soft alert first; a separate case with `ITERATION_CAP=2` MUST abort a loop of sub-threshold steps. Confirm RED (breaker not yet enforcing).

### Implementation for User Story 1

- [ ] T011 [US1] Implement `.claude/workflows/lib/cost-engine.js` — pure `costOf`, `costByAgent`, `totalCost` (Σ tokens_by_type × rateFor), per contracts/cost-engine.md. Make T007/T008/T009 GREEN.
- [ ] T012 [P] [US1] Implement `.claude/workflows/lib/usage-source.js` — the adapter seam: `readUsageSince(runId, sinceTimestamp)` parsing `~/.claude/projects/**/*.jsonl` (ccusage-style) into neutral `UsageEvent[]`, with a `USAGE_SOURCE_DIR`/path override so the fixture can inject a stub log. Agent-specifics confined here (Constitution II).
- [ ] T013 [US1] Implement `.claude/workflows/lib/budget-breaker.js` — `new BudgetBreaker(config, table, budgetPrimitive)`, `checkpoint(runId) -> {action,state}` (iteration-cap → perTask.hard → perWorkflow.hard → soft-once → continue), wrapping/extending the runtime `budget` primitive so `spent()` is notional cost and `agent()` throws on abort (FR-011). Disabled config ⇒ always `continue`. Make T010 GREEN.
- [ ] T014 [US1] Add `.agent/budget.conf` with the clarified conservative defaults (soft $3 / hard $5, `ITERATION_CAP=40`, `PRICE_TABLE_SOURCE=litellm`, `PRICE_TABLE_MAX_AGE_HOURS=168`, `PRICE_TABLE_FALLBACK=assume-max`) per contracts/budget.conf.schema.md.

**Checkpoint**: US1 fully functional — the kill-switch fires in a fixture and pricing is accurate.

---

## Phase 4: User Story 3 — Every workflow run records its notional cost (Priority: P2, data foundation)

**Goal**: on every run end (completed OR aborted-on-budget) one NDJSON record is appended to
`.agent/budget/runs/<date>.ndjson` with total + per-agent notional cost, workflow type, task id,
status, and (if aborted) the breached threshold. **No analytics/UI** — data foundation only.

**Independent Test**: covered inside `tests/budget-breaker.fixture.sh` (the abort case asserts a
record was written with the spend at abort time, SC-002) plus a `node --test` shape assertion.

### Tests for User Story 3 (write FIRST, prove RED) ⚠️

- [ ] T015 [P] [US3] `tests/cost-engine.test.js` (or a sibling block) — `writeBudgetRecord(...)` produces a JSON object matching contracts/budget-record.schema.md (required fields, `costBasis:"notional"`, `status ∈ {completed, aborted-on-budget}`, `perAgent[]` with tokens-by-type) and appends exactly one NDJSON line. Confirm RED.

### Implementation for User Story 3

- [ ] T016 [US3] Implement `.claude/workflows/lib/budget-record.js` — `writeBudgetRecord(record, dir)` appending one validated NDJSON line to `.agent/budget/runs/<date>.ndjson`; `breaker.onRunEnd(status)` delegates here. Make T015 GREEN and the fixture's "record written on abort" assertion GREEN.

**Checkpoint**: every run leaves a durable, greppable cost record.

---

## Phase 5: User Story 2 — Live observability preset (Priority: P2, scaffolder assets only)

**Goal**: an OPT-IN, local-first observability preset the scaffolder can emit — no usage data leaves
the host, no custom collector code. Turning it OFF leaves everything unchanged (the guardrail works
without it, FR-006/FR-014).

**Independent Test**: assets exist, are valid, and are opt-in (no auto-wiring); `node --check`/YAML
parse where applicable. (Bringing up Docker is out of CI scope — the assets are the deliverable.)

### Implementation for User Story 2 (scaffolder assets)

- [ ] T017 [P] [US2] Add `.agents/skills/scaffold-agent-project/assets/observability/docker-compose.yml` — OTel Collector + Arize Phoenix (default), optional Grafana/Prometheus flagged as copyleft. Local-first; no hosted SaaS.
- [ ] T018 [P] [US2] Add `.agents/skills/scaffold-agent-project/assets/observability/otel-collector.yaml` — OTLP receiver → local exporters.
- [ ] T019 [P] [US2] Add `.agents/skills/scaffold-agent-project/assets/observability/env.observability.example` — `CLAUDE_CODE_ENABLE_TELEMETRY=1` + the enhanced-telemetry beta env to enable spans. Opt-in.
- [ ] T020 [US2] Add `.agents/skills/scaffold-agent-project/references/budget-observability.md` — how the preset + guardrail work (loaded only on activation, Constitution V).

**Checkpoint**: observability is an opt-in emitted feature; nothing is auto-enabled.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T021 Add `.agents/skills/scaffold-agent-project/assets/project-files/budget.conf` — the conservative-default config the scaffolder emits into a fresh repo (FR-022), matching `.agent/budget.conf`.
- [ ] T022 Add the project-files `gitignore` lines for `.agent/budget/` cache + runs so scaffolded repos ignore them too.
- [ ] T023 Wire the cost tests into the suite: create `tests/check-budget.sh` (self-testing, like `tests/check-footnotes.sh`/`check-qa-manifest.sh`) that runs `node --test` on the cost tests + `node --check` on every new `.js` + the breaker fixture; invoke it (and `node --test`) from `tests/validate.sh`.
- [ ] T024 [P] Add the cost-core JS to `.agent/qa.conf` `QA_TARGETS` (so the QA loop sees it) and keep `tests/check-qa-manifest.sh` green.
- [ ] T025 Mirror the scaffolder skill `.agents/skills/scaffold-agent-project` → `.claude/skills/scaffold-agent-project` byte-identically (`tests/check-skill-mirror.sh` gate).
- [ ] T026 Run the full gate: `node --test`, `node --check` on every new `.js`, `sh tests/check-budget.sh`, `.venv/bin/mkdocs build --strict -d /tmp/_003`, `sh tests/check-skill-mirror.sh`, `sh tests/check-qa-manifest.sh`, `sh tests/validate.sh` — all green.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (P1)** → no deps.
- **Foundational (P2)** → needs Setup; BLOCKS US1 and US3 (config + price table).
- **US1 (P3)** → needs Foundational. The MVP. Independently testable.
- **US3 (P4)** → needs Foundational + the breaker's `onRunEnd` hook from US1; the record writer itself is independent.
- **US2 (P5)** → independent of the cost core (assets only); can run any time after Setup.
- **Polish (P6)** → after the stories it wires up.

### Within Each User Story

- Tests are written and proven RED **before** the implementation task that makes them GREEN.
- `budget-config.js` + `price-table.js` (Foundational) before `cost-engine.js` (US1).
- `cost-engine.js` + `usage-source.js` before `budget-breaker.js`.
- `budget-record.js` (US3) before the fixture's "record written" assertion is fully GREEN.

### Parallel Opportunities

- T003 / T004 (test authoring for different modules) in parallel.
- T007 / T008 / T009 (independent test cases) in parallel.
- T012 parallel with T011 (different files).
- T017 / T018 / T019 (independent asset files) in parallel.

---

## Implementation Strategy

### MVP First (User Story 1)

1. Setup (T001–T002) → Foundational (T003–T006) → US1 (T007–T014).
2. **STOP and VALIDATE**: `sh tests/budget-breaker.fixture.sh` + `node --test` green. The kill-switch fires.

### Incremental Delivery

1. Setup + Foundational → ready.
2. US1 → the guardrail (MVP).
3. US3 → durable ledger.
4. US2 → opt-in observability preset.
5. Polish → wire into the suite, mirror, full gate.

---

## Notes

- Strict TDD: prove RED, then GREEN. Red+green may be paired commits per the repo's existing style.
- `[P]` = different files, no dependency on an incomplete task.
- Do NOT weaken or delete a test to pass. Do NOT silently price an unknown model at $0 (FR-019).
- P2 here is **data foundation only** — `budget-record.js` is built; no analytics/judgment UI.
- Commit on `003-agent-budget-observability`; do NOT merge or push (the orchestrator verifies/merges).
