# Research: Steerable, Bounded QA-Loop (Report-First)

Phase 0 decisions. Each resolves a "how" the spec leaves open, grounded in the existing
`qa-loop.js`/`qa.conf`/`quality-loop` implementation and spec 003's primitives. No NEEDS
CLARIFICATION remained after the spec's `## Clarifications` session; the items below are design
choices, not open spec questions.

---

## R1 — Report-first control flow & the modes (FR-A1..A4)

**Decision.** Restructure the workflow into **two modes**, selected by `args.mode` (default from
`QA_MODE` in `qa.conf`, default `report`):

- `mode: report` (default): `Target-select → [round loop: Generate → dedup → Verify(+impact) → rank]
  → write triage report (.md + .json) → STOP`. **No branch, no fix** for anything below the top
  tier. The *only* code-touching action permitted is the **narrow auto-fix lane** (R5) for
  unambiguous top-tier findings.
- `mode: fix` (explicit, human-invoked): takes an **approved id subset** (`args.fix = [ids]`, read
  against the `qa-<date>.json` sidecar from a prior report run). Creates one branch, fixes **only**
  those ids with the fast fix-gate (R6), runs the full suite once at the end, and writes a fix report.
- A broader `mode: autofix` is the **opt-in** full-auto path (FR-A4): same fix machinery but it
  auto-approves the whole fix tier. It is never the default and must honor all ceilings + the bar.

**Rationale.** The current single linear path interleaves verify-and-fix per finding, which is exactly
what produced 28 auto-fixes. Splitting *discovery* (read-only, ranked, stops) from *action* (scoped,
branch, human-gated) makes report-first the structural default rather than a flag, satisfying SC-002
(0% of default runs touch code) by construction. Encoding the approved subset as ids resolved against a
persisted JSON sidecar makes the approve step a clean, auditable hand-off (no re-running discovery to
fix).

**Alternatives considered.**
- *A single mode with a `--fix` flag that still discovers then fixes in one pass* — rejected: keeps
  generation and fixing coupled, so a runaway generator can still drive fixes, and "approve a subset"
  has no durable artifact to approve against.
- *Interactive in-loop approval prompt* — rejected: the runner is non-interactive/batch; a persisted
  report + a second invocation is the portable hand-off and matches the existing "stops before the
  PR, human resumes" pattern.

---

## R2 — Verifier impact schema & the severity bar (FR-B1..B3, Edge: ambiguous severity)

**Decision.** Extend the `VERDICT` schema the `qa-verifier` returns with:
- `impact`: enum `data-loss | security | correctness | robustness | theoretical-edge`.
- `impactConfidence`: enum `high | low` (classification confidence).
- `impactRationale`: short string tying the class to the threat model (recorded in the report).

The bar is an **ordering** over impact classes (highest→lowest): `data-loss > security > correctness >
robustness > theoretical-edge`. `QA_MIN_SEVERITY` names the lowest class that still reaches the fix
tier. Default **`moderate`** maps to the `robustness` cutoff: `data-loss, security, correctness,
robustness` → fix tier; `theoretical-edge` → backlog. Per the spec's "classify conservatively" edge
case, an **ambiguous** finding is assigned the **higher** impact and the rationale is recorded.

**Rationale.** Reusing the existing VERDICT object (rather than a separate classifier pass) keeps the
verifier the single oracle and avoids a second agent round-trip per finding — important for the cost
ceiling. A simple total order over five classes makes the bar a one-line comparison and makes
convergence (R3) trivial to evaluate. `moderate` is the spec-clarified default (FR-CFG3).

**Alternatives considered.**
- *Numeric severity score (0–10)* — rejected: invites false precision and bikeshedding; the five named
  classes map directly to the threat model and the spec's own language.
- *A dedicated `impact-classifier` subagent* — rejected: doubles per-finding agent calls (cost) for no
  accuracy gain; the verifier already reproduces the finding and is best positioned to judge impact.

---

## R3 — Convergence keyed on the bar, not on CONFIRMED (FR-B4)

**Decision.** Replace the current `confirmedThisRound === 0 → dryStreak++` rule with
**`qualifyingThisRound === 0 → dryStreak++`**, where *qualifying* = "a new finding whose `impact` is
at/above `QA_MIN_SEVERITY`." Rounds that produce only below-bar findings advance the dry-streak exactly
as empty rounds do. Keep `QA_DRY_STREAK` (default 2) and `QA_MAX_ROUNDS` (default 4) as the two
independent breakers.

**Rationale.** The post-mortem's "never converges" failure is precisely that generators can always
manufacture one more reproducible edge case; keying the streak on *confirmed* let those keep the loop
alive. Keying on *at/above-bar* means the marginal tail can no longer extend the run, directly
satisfying FR-B4 and US2 acceptance #3.

**Alternatives considered.** *Drop the dry-streak and rely only on max-rounds/budget* — rejected:
loses early termination on genuinely-converged runs (wastes budget); the bar-keyed streak is strictly
better now that below-bar noise no longer poisons it.

---

## R4 — Bounded execution: consume spec 003's budget primitive (FR-C1..C4)

**Decision.** Wrap the round loop (and the fix-run) with spec 003's `budget` Workflow primitive,
configured from `.agent/budget.conf` + a QA-scoped `QA_BUDGET` override in `qa.conf`. Add `QA_MAX_FIXES`
(cap on fix-tier findings accrued/fixed per run) and keep `QA_MAX_ROUNDS`; an **optional**
`QA_WALLCLOCK` is threaded the same deterministic way as `dateStamp` (a start timestamp passed via
`args`, never `new Date()` inline). The loop checks **all** ceilings at the top of each round and after
each verify; on breach it **breaks out and still runs Triage**, tagging the report with the breached
ceiling (`stop: budget | max-fixes | max-rounds | wall-clock | dry-streak | max-rounds-cap`).

**Rationale.** Spec 003 already owns spend accounting + soft-alert/hard-abort; re-using its `budget`
primitive satisfies "Adopt, Don't Reinvent" and FR-C1 without re-specifying pricing. Checking ceilings
at round boundaries (not mid-agent-call) keeps abort points clean so Triage always runs → graceful
partial report (FR-C4, SC-005). `QA_MAX_FIXES` and the rounds cap are QA-local and live in `qa.conf`.

**Alternatives considered.**
- *Re-implement a token counter inside qa-loop.js* — rejected: duplicates 003, violates Principle VI,
  and would drift from the host's real accounting.
- *Kill the run hard on budget* — rejected: violates FR-C4/SC-005 (must emit a partial report); the
  break-then-Triage path is mandatory.

---

## R5 — The narrow top-tier auto-fix lane (FR-A3, Edge: auto-fix vs opt-in)

**Decision.** In `mode: report`, after ranking, the loop auto-fixes **only** findings where
`impact ∈ {data-loss, security}` **AND** `impactConfidence === high` (unambiguous top tier). Anything
data-loss/security with `impactConfidence: low` is **routed to the report, not fixed** (ambiguous →
report). Auto-fixes use the same fast fix-gate (R6), count against `QA_MAX_FIXES` and the budget, land
on the lazily-created branch, and are recorded in the report's own **"auto-fixed (top-tier)"** section.

**Rationale.** This is the spec's clarified narrow autonomous lane: act without approval *only* when
the finding is both top-impact and unambiguous, because the cost of leaving a real data-loss/security
bug unfixed outweighs the report-first default there. The `impactConfidence` gate operationalizes the
spec's "ambiguous classification → report, not fix" rule.

**Alternatives considered.** *No auto-fix lane at all (pure report-first)* — rejected: contradicts the
spec clarification, which explicitly preserves a narrow autonomous lane. *Auto-fix all top-tier
regardless of confidence* — rejected: violates the ambiguity carve-out.

---

## R6 — Fast fix-gate: regression + directly-affected checks only (FR-D1/D2)

**Decision.** During a fix-run, each fix is gated by **(a)** the new RED-first regression case for that
finding and **(b)** the *directly-affected* existing checks — not the full `TEST_CMD`. "Directly-
affected checks" are resolved by a small, explicit **target→checks map** declared in `qa.conf`
(`QA_AFFECTED_<target>` or a single `QA_AFFECTED_MAP`), falling back to "the check script that already
self-tests this target" (e.g. a hook's own `self_test()`, or `tests/check-qa-manifest.sh` for the
manifest). The **full `TEST_CMD`** runs **exactly once**, at the end of the fix-run, as the final gate
before the report.

**Rationale.** The post-mortem's dominant cost was re-running `mkdocs --strict + validate` every fix
iteration. A declared map keeps "affected" deterministic and auditable (vs. an agent guessing), and the
self-test fallback reuses the repo's existing per-target tests. Running the full suite once at the end
preserves the integration guarantee (SC-007) at a fraction of the cost.

**Alternatives considered.**
- *Let the agent infer affected checks per fix* — rejected as the primary mechanism: non-deterministic
  and risks missing a regression (named risk R-2 below); used only as a documented fallback behind the
  explicit map.
- *Static import/dependency analysis* — rejected: the targets are shell scripts + JS with no shared
  build graph; a hand-declared map is simpler and exact for this repo.

---

## R7 — Spec 003 dependency sequencing & graceful degradation

**Decision.** Treat spec 003 (branch `003-agent-budget-observability`, not yet on `main`) as a hard
dependency for FR-C1 (budget ceiling) and FR-E2/E3-live-watch. The workflow **feature-detects** the
`budget` primitive: if present, ceilings include budget and the live `/workflows` view is documented as
the watch path; if absent, the run still enforces `QA_MAX_FIXES` + `QA_MAX_ROUNDS` (+ optional
wall-clock) and degrades the budget ceiling to a no-op with a logged warning, so 004 is testable before
003 lands. The plan does **not** re-specify 003's accounting/observability.

**Rationale.** The spec's Assumptions explicitly say the budget + observability are 003's and "not
separately built here." Feature-detection keeps 004 independently verifiable (US1–US3, US4's non-budget
ceilings, US5 scoping) while honoring the dependency for the budget/live-watch pieces.

**Alternatives considered.** *Hard-fail if 003 absent* — rejected: blocks all of 004 on 003 even though
most user stories don't need the budget primitive. *Re-implement budget locally* — rejected (Principle
VI; see R4).

---

## R8 — Steering: per-run target scope (FR-E1) & abort (FR-E3)

**Decision.** Per-run scope is the existing `args.targets` (already supported) elevated to a
first-class steering control, plus a `QA_TARGETS_DEFAULT` vs. named subsets in `qa.conf` so a developer
can name one subsystem (e.g. `--targets hooks`). Mid-flight **abort** is delivered by 003's live
`/workflows` control (003 owns the abort affordance); on abort the workflow takes the same
break→Triage path as a ceiling hit, emitting a partial report. Pre-003, abort = interrupting the run;
the next `report` run still produces a fresh ranked report (no partial-state corruption because
discovery is idempotent and the report writes atomically at the end).

**Rationale.** Reuses the workflow's existing `args.targets` plumbing (minimal new surface) and 003's
observability for watch+abort, satisfying US5 without re-specifying the dashboard.

---

## Consolidated decisions

| # | Decision | Key requirement(s) |
|---|---|---|
| R1 | Two/three modes: `report` (default, stops) + `fix` (scoped, approved ids) + opt-in `autofix` | FR-A1, A4, US1, US3 |
| R2 | VERDICT gains `impact` + `impactConfidence` + `impactRationale`; total order over 5 classes | FR-B1, B2 |
| R3 | Convergence keys on "no new finding at/above the bar" | FR-B4 |
| R4 | Consume 003 `budget` primitive; add `QA_MAX_FIXES`; break→Triage on any ceiling | FR-C1..C4 |
| R5 | Auto-fix only `data-loss/security` AND `impactConfidence: high`; ambiguous→report | FR-A3 |
| R6 | Fast gate = regression + declared directly-affected checks; full `TEST_CMD` once at end | FR-D1, D2 |
| R7 | 003 is a hard dep for budget/live-watch; feature-detect + degrade gracefully | Assumptions, FR-C1, E2 |
| R8 | Per-run `--targets` scope + 003-driven mid-flight abort → break→Triage | FR-E1, E3 |

## Open risks (carried into the plan's risk section)

- **R-1 Verifier mis-classifies impact** → a real bug lands below the bar (false-backlog) or a pedantic
  one above it. Mitigation: conservative "ambiguous → higher class," `impactRationale` recorded for
  audit, and the `tests/check-qa-loop.sh` replay fixture asserts the post-mortem-style edge cases land
  below the bar.
- **R-2 "Affected check" selection misses a regression** the full suite would have caught. Mitigation:
  explicit declared map (not agent inference) + the **full `TEST_CMD` once at end** as the backstop
  (FR-D2) so nothing ships without the integration gate.
- **R-3 003 not yet merged** → budget ceiling inactive. Mitigation: feature-detect + degrade (R7);
  non-budget ceilings still bound the run.
