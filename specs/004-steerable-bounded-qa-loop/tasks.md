---
description: "Task list for Steerable, Bounded QA-Loop (Report-First)"
---

# Tasks: Steerable, Bounded QA-Loop (Report-First)

**Input**: Design documents from `/specs/004-steerable-bounded-qa-loop/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (qa-conf, verdict-schema, report-schema, workflow-args)

**Tests**: REQUESTED — this feature is built **test-first (TDD)**. The pure decision logic is extracted into
testable seams (`lib/qa-classify.js`, `lib/qa-convergence.js`) unit-tested with `node --test`, plus a
deterministic `tests/check-qa-loop.sh` shell harness that replays the 4-hour post-mortem. Each behavior:
RED test first → confirm fail → implement to GREEN.

**Organization**: Grouped by user story (US1–US5) in priority order, after a shared-foundation phase
that introduces the decision-logic seams every story depends on.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different file, no incomplete dependency)
- **[Story]**: US1–US5 (Polish/Setup/Foundational have no story label)

## Path Conventions

Single-repo agent-tooling layer (no `src/`). The "code" is the workflow JS
(`.claude/workflows/qa-loop.js` + new `.claude/workflows/lib/qa-*.js` seams), POSIX config
(`.agent/qa.conf`), skill markdown (`.agents/skills/quality-loop/SKILL.md` + `.claude/` mirror),
subagent prompts (`.claude/agents/qa-*.md`), and deterministic `sh`/`node --test` checks under `tests/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the branch carries 003's budget core and establish the seam layout.

- [ ] T001 Confirm 003's budget core is present and syntactically valid on this branch: `node --check`
  every file in `.claude/workflows/lib/*.js` and confirm `.agent/budget.conf` exists (the live wiring
  target for FR-C1).
- [ ] T002 Decide and record the seam layout in this tasks file's comments: pure decision logic lives in
  `.claude/workflows/lib/qa-classify.js` (impact order, tiering, top-tier auto-fix gate, default
  resolution) and `.claude/workflows/lib/qa-convergence.js` (bar-keyed dry-streak, ceiling/stop
  evaluation, fast-gate check selection). `qa-loop.js` imports these and keeps only `agent()`-bound glue.

---

## Phase 2: Foundational — the testable decision-logic seams (Blocking Prerequisites)

**Purpose**: The pure functions every user story's behavior is asserted against. MUST exist before the
workflow can be rewired or any story tested. Built strict-TDD: test file first (RED), then the module.

- [ ] T003 [P] Write the RED unit test file `tests/qa-classify.test.js` (`node --test`) asserting, against
  a not-yet-existing `.claude/workflows/lib/qa-classify.js`: (a) `IMPACT_ORDER` ranks
  data-loss>security>correctness>robustness>theoretical-edge; (b) `resolveConfig(qaConf, args)` yields the
  safe defaults (mode=report, minSeverity=moderate, maxFixes=5, maxRounds=4, dryStreak=2) when conf/args
  are empty (FR-CFG2); (c) args override conf override defaults per `contracts/qa-conf.md`. Confirm RED
  (module missing).
- [ ] T004 [P] Write the RED unit test file `tests/qa-convergence.test.js` (`node --test`) asserting,
  against a not-yet-existing `.claude/workflows/lib/qa-convergence.js`: (a) `qualifies(finding, minSeverity)`
  is true only at/above the bar; (b) a round of only below-bar findings advances the dry-streak
  (`bumpDryStreak`); (c) `evaluateStop(state, ceilings)` returns the right `stop` reason for
  max-rounds / dry-streak / max-fixes. Confirm RED.
- [ ] T005 Implement `.claude/workflows/lib/qa-classify.js` to GREEN T003: `IMPACT_ORDER`, `impactRank`,
  `tierFor(impact, minSeverity)` (fix vs backlog per data-model §3), `isTopTierAutoFixable(verdict)`
  (data-loss|security AND impactConfidence==='high'), `resolveConfig(conf, args)` (the
  default-resolution contract incl. `mode|fix|autofix`, `targets`, `fixIds`). Run `node --test
  tests/qa-classify.test.js` → GREEN.
- [ ] T006 Implement `.claude/workflows/lib/qa-convergence.js` to GREEN T004: `qualifies`,
  `bumpDryStreak(state, qualifyingThisRound)`, `evaluateStop(state, ceilings)` over
  {round,maxRounds,dryStreak,dryStreakStop,fixCount,maxFixes}, and `affectedChecks(target, affectedMap)`
  (declared map → self-test fallback, data-model §6). Run `node --test tests/qa-convergence.test.js` → GREEN.

**Checkpoint**: both seam modules exist, `node --check` clean, both `node --test` files GREEN. The
budget core (003) is unchanged and still importable.

---

## Phase 3: User Story 1 — Ranked report, no code touched (Priority: P1) 🎯 MVP

**Goal**: Default `mode: report` run does generate→verify→rank→write report→STOP, no branch, no edits.

**Independent test**: a default run produces a ranked `.md`+`.json` report and changes no code / creates
no branch (asserted by `tests/check-qa-loop.sh`).

- [ ] T007 [US1] Write the RED replay harness `tests/check-qa-loop.sh` skeleton + self-test: a built-in
  self-test (like `check-qa-manifest.sh`) proving its pass/fail logic catches a known break, then a
  fixture that feeds **stubbed findings/verdicts** (the 4-hour post-mortem set: one real correctness/
  data-loss finding + many theoretical-edge ones) through the seam modules and a `--report` rendering
  helper. First assertion: a default run yields a ranked report and changes no code (no branch, no edits).
  Confirm RED (rendering/wiring absent). Make it executable.
- [ ] T008 [US1] Extend `qa-loop.js`: add `mode` (default report) to the args/`resolveConfig` plumbing;
  restructure the round loop to `Generate → dedup → Verify(+impact) → rank` and, in `mode: report`,
  STOP after writing the report with **no branch and no fix** (except the US-defined top-tier lane,
  built in US-autofix). Use `resolveConfig`/`tierFor` from the seams. `node --check` qa-loop.js.
- [ ] T009 [US1] Implement the triage-report renderer per `contracts/report-schema.md` — a pure helper
  `renderReport(meta, findings)` in `.claude/workflows/lib/qa-report.js` producing the Markdown sections
  (Summary, Fix tier, Auto-fixed, Backlog, Rejected, Unverified-at-abort) + the JSON sidecar object;
  findings ordered by impact rank then confidence. Have `tests/check-qa-loop.sh` import it. Run
  `sh tests/check-qa-loop.sh` → first US1 assertion GREEN.
- [ ] T010 [US1] Wire `qa-loop.js`'s Triage phase to call `renderReport` and write
  `qa/reports/qa-<dateStamp>.md` + `.json` atomically (date threaded via `args.dateStamp`, never
  `new Date()` inline). Update the workflow return value to the `workflow-args.md` shape. `node --check`.

**Checkpoint**: US1 independently runnable — default run → ranked report, no code touched.

---

## Phase 4: User Story 2 — Impact bar; pedantic edge cases are backlog (Priority: P1)

**Goal**: Verifier classifies impact; only at/above-`QA_MIN_SEVERITY` reaches the fix tier; convergence
keys on the bar.

**Independent test**: replay → correctness defect in fix tier, theoretical-edge in backlog with a reason;
below-bar-only rounds don't extend the run.

- [ ] T011 [P] [US2] Extend the VERDICT schema in `qa-loop.js` with `impact` + `impactConfidence` +
  `impactRationale` per `contracts/verdict-schema.md`; enforce the validation rule (a CONFIRMED missing a
  non-null `impact` is discarded). `node --check`.
- [ ] T012 [US2] Add the RED assertions to `tests/check-qa-loop.sh`: (a) the **moderate** bar admits
  correctness+robustness, excludes theoretical-edge; (b) a theoretical-edge finding lands in **backlog**,
  not fix, with a stated reason; (c) ambiguous impact is classed at the higher tier. Confirm those new
  asserts RED.
- [ ] T013 [US2] Wire `tierFor` + the conservative ambiguity rule into `qa-loop.js`'s rank step so each
  confirmed finding's tier is computed from its verdict `impact` vs resolved `minSeverity`. Run
  `sh tests/check-qa-loop.sh` → US2 tiering asserts GREEN.
- [ ] T014 [US2] Replace the convergence rule in `qa-loop.js` with the bar-keyed dry-streak
  (`qualifyingThisRound===0 → bumpDryStreak`) via `qa-convergence.js`. Add the RED assert in
  `tests/check-qa-loop.sh` that a below-bar-only round advances the streak (marginal tail can't extend
  the run), then GREEN it.
- [ ] T015 [P] [US2] Update `.claude/agents/qa-verifier.md`: add the "Classify impact" step (pick one
  impact class under the threat model, state confidence, record rationale, conservative ambiguous→higher),
  per `contracts/verdict-schema.md`. Update `.claude/agents/qa-adversary.md` to tag a `proposedImpact`
  hint (advisory). Tool grants unchanged.

**Checkpoint**: US2 independently testable — bar gates the fix tier; convergence ignores the tail.

---

## Phase 5: User Story 3 — Approve a subset; scoped fix-run on one branch (Priority: P1)

**Goal**: `mode: fix` with an approved id subset fixes only those, on one branch; empty subset → no change.

**Independent test**: from a report, approve N of M ids → exactly N fixed on one branch, M−N untouched.

- [ ] T016 [US3] Add RED `tests/check-qa-loop.sh` asserts: (a) `mode: fix` with empty/absent `fix` ⇒ no
  code change (the resolved plan is a no-op); (b) `fix` ids are resolved against the latest
  `qa-<date>.json` sidecar — unknown ids reported skipped, stale (no-longer-reproducing) ids reported not
  fabricated. Confirm RED.
- [ ] T017 [US3] Implement `resolveFixSubset(reportJson, fixIds)` in `.claude/workflows/lib/qa-classify.js`
  (or `qa-fix.js`): looks up ids in the sidecar, partitions into {approved, unknown, stale-marker}. Wire
  `qa-loop.js` `mode: fix` to load `qa/reports/qa-<dateStamp>.json`, resolve the subset, and branch only
  if there is ≥1 approved id. Run `sh tests/check-qa-loop.sh` → US3 subset asserts GREEN.
- [ ] T018 [US3] Implement the scoped fix-run control flow in `qa-loop.js`: one lazily-created branch, fix
  only approved ids RED-first, all on that branch; record `fixBranch` per finding. `node --check`.

**Checkpoint**: US3 independently testable — scoped fix touches only the approved subset.

---

## Phase 6: User Story 4 — Graceful ceiling abort + partial report (Priority: P2)

**Goal**: WIRE 003's budget into qa-loop.js; any ceiling (budget / QA_MAX_FIXES / rounds / wall-clock) →
break→Triage→partial ranked report naming the breach. **This is the live 003 integration 003 deferred.**

**Independent test**: a tiny ceiling aborts with a partial report naming the breach (asserted by the shell
harness with a 003-style fixture ceiling).

- [ ] T019 [US4] Add the RED assert in `tests/check-qa-loop.sh`: with a deliberately tiny ceiling
  (max-rounds=1 and/or a budget fixture like 003's), the run **aborts with a partial report** whose
  `meta.stop` names the breached ceiling and whose findings-so-far are still emitted (nothing silently
  dropped; mid-verify finding → `unverified-at-abort`). Confirm RED.
- [ ] T020 [US4] Wire 003's budget into `qa-loop.js`: import `readBudgetConfig` (budget-config.js) +
  `BudgetBreaker` (budget-breaker.js) from `.claude/workflows/lib/`, construct the breaker from
  `.agent/budget.conf` (+ `QA_BUDGET` override), call `breaker.checkpoint()` at the top of each round and
  after each verify/fix, and `breaker.onRunEnd()` on every termination path. Feature-detect/degrade per
  research R7 (absent/disabled budget ⇒ no-op + the non-budget ceilings still bound the run). `node --check`.
- [ ] T021 [US4] Implement the break→Triage ceiling handling via `qa-convergence.js evaluateStop` +
  the breaker's abort: on any breach, break the loop, set `meta.stop`, record any mid-verify finding as
  `unverified-at-abort`, and still run Triage so a ranked partial report is written (FR-C4, SC-005). Run
  `sh tests/check-qa-loop.sh` → US4 abort assert GREEN.

**Checkpoint**: US4 independently testable — budget is WIRED INTO qa-loop.js (not just feature-detected),
and a fixture proves the abort emits a partial report.

---

## Phase 7: User Story 5 — Per-run scope + faster fix gate (Priority: P3)

**Goal**: `--targets`/`QA_TARGETS` per-run scope; fast fix gate = regression + directly-affected checks,
full `TEST_CMD` once at end.

**Independent test**: a scoped run exercises only the named targets; a fix runs only its affected
check(s) per iteration and the full suite once at the end.

- [ ] T022 [P] [US5] Add the RED assert in `tests/check-qa-loop.sh` that `affectedChecks(target, map)`
  resolves to the declared check(s) (or self-test fallback) and NOT the full `TEST_CMD`, and that
  `resolveConfig` honors `args.targets` scope over `QA_TARGETS`. Confirm RED, then GREEN via the seams.
- [ ] T023 [US5] Wire the fast fix-gate into `qa-loop.js`'s fix loop: per-fix iteration runs the new
  regression check + `affectedChecks(target, affectedMap)` only; run the full `TEST_CMD` exactly once at
  end-of-fix-run (FR-D1/D2). Wire `args.targets`/`QA_TARGETS` scope into Target-select. `node --check`.

**Checkpoint**: all five stories integrated.

---

## Phase 8: Config, skill, manifest, and gate wiring (Cross-Cutting)

**Purpose**: Update the authored config/skill/docs and wire the new checks into the repo's gates.

- [ ] T024 Update `.agent/qa.conf` per `contracts/qa-conf.md`: add `QA_MODE=report`,
  `QA_MIN_SEVERITY=moderate`, `QA_MAX_FIXES=5`, `QA_BUDGET` (→ budget.conf link), optional `QA_WALLCLOCK`,
  `QA_AFFECTED_MAP`; keep `QA_MAX_ROUNDS`/`QA_DRY_STREAK`/`QA_LENSES`/`QA_THREAT_MODEL`. Add the new
  `lib/qa-*.js` + the harness to `QA_TARGETS` so the manifest stays valid; confirm
  `sh tests/check-qa-manifest.sh` GREEN.
- [ ] T025 Update `.agents/skills/quality-loop/SKILL.md` to report-first: modes, the impact bar +
  moderate default, ceilings/budget, bar-keyed convergence, fast fix-gate, scope. Then copy it
  byte-identical to `.claude/skills/quality-loop/SKILL.md`; confirm `sh tests/check-skill-mirror.sh` GREEN.
- [ ] T026 Wire `tests/check-qa-loop.sh` + the new `node --test` files into `tests/validate.sh` (a new
  numbered check block that runs `sh tests/check-qa-loop.sh` and the qa decision-logic `node --test`),
  mirroring the existing budget block. Confirm `sh tests/validate.sh` GREEN.

---

## Phase 9: Polish & full-gate verification (Cross-Cutting)

- [ ] T027 Run the full gate green: `node --test tests/qa-classify.test.js tests/qa-convergence.test.js
  tests/cost-engine.test.js tests/notional-accuracy.test.js`; `node --check` qa-loop.js + every new lib;
  `sh tests/check-qa-loop.sh`; `.venv/bin/mkdocs build --strict -d /tmp/_004`; `sh tests/check-skill-mirror.sh`;
  `sh tests/check-qa-manifest.sh`; `sh tests/check-budget.sh`; `sh tests/validate.sh`. Fix any failures.
- [ ] T028 Final review pass: confirm SC-002 (default touches no code), SC-004 (post-mortem → small fix
  tier / big backlog), SC-005 (ceiling → partial report) are each asserted by a GREEN test, and that the
  budget is wired (not merely detected). Record honest thin spots.

---

## Dependencies & Execution Order

- **Phase 1 (Setup)** → **Phase 2 (seams)** block everything: the seams are imported by every later phase.
- **US1 (Phase 3)** is the MVP and must land first (report-first control flow + renderer).
- **US2 (Phase 4)** depends on US1 (needs the rank/report path) — adds the impact bar + convergence.
- **US3 (Phase 5)** depends on US1 (consumes the JSON sidecar) — independent of US2.
- **US4 (Phase 6)** depends on US1 (needs Triage break-point) — the budget wiring; independent of US2/US3.
- **US5 (Phase 7)** depends on US1 (scope) + the fast-gate seam from Phase 2.
- **Phase 8** depends on all stories (config/skill must describe final behavior; gates wire final files).
- **Phase 9** is the final verification.

## Parallel Opportunities

- T003 / T004 (the two RED seam test files) are `[P]` — different files, no dependency.
- T011 (VERDICT schema) / T015 (subagent prompts) within US2 are `[P]`.
- T022 (US5 RED assert) is `[P]` once the seams exist.
- Cross-story: after Phase 2, US3 and US4 touch largely disjoint qa-loop.js regions but both edit
  qa-loop.js, so coordinate edits (not fully parallel at the file level).

## MVP Scope

**US1 only** (Phases 1–3): a default run produces a ranked report and changes no code. This alone
delivers SC-002 + SC-003 and prevents the "auto-fixed all 28" failure. US2 (bar) and US4 (ceilings)
are the next increments that deliver SC-004 and SC-005.
