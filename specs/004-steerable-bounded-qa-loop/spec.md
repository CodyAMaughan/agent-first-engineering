# Feature Specification: Steerable, Bounded QA-Loop (Report-First)

**Feature Branch**: `004-steerable-bounded-qa-loop`

**Created**: 2026-06-13

**Status**: Draft

**Input**: User description: "Steerable, bounded QA-loop (report-first)"

## Overview

The adversarial QA-loop workflow (`.claude/workflows/qa-loop.js`, configured by `.agent/qa.conf` and
driven by the `quality-loop` skill) generates candidate defects against a target, verifies which are
reproducible, and fixes them in a loop. In a real run it went badly wrong: it ran for roughly **four
hours unbounded**, surfaced **28 "bugs" in the repo's own guardrail hooks**, and **auto-fixed every
one of them on its own branch** — yet most were pedantic, low-impact edge cases (exotic encodings,
theoretical concurrency races on hooks that never run concurrently) on ancillary code, not defects
that matter in practice.

The post-mortem isolates four root problems, each mapping to a required capability:

1. **No ceiling.** Nothing bounded tokens, notional cost, wall-clock time, or fix count — so the run
   simply did not stop.
2. **Too pedantic an acceptance bar.** The only gate was "is it reproducible?", so every reproducible
   finding was treated as fix-worthy regardless of real-world impact, and the loop drifted into the
   marginal tail.
3. **Unsteerable (fire-and-forget).** There was no scope control, no checkpoint for human review, no
   live visibility, and no way to say "stop after the real ones."
4. **Never converges.** The "stop after K dry rounds with no new confirmed findings" rule never fired,
   because creative generators can always manufacture one more reproducible edge case.

This feature reshapes the QA-loop into a **steerable, bounded, report-first** tool. Its default
behavior changes from "find-and-auto-fix-everything" to **"find, rank, and stop for human review."**
A human approves a subset; only that subset is fixed, in a single scoped fix-run. It also adds an
impact-severity bar (so convergence is keyed on real findings, not the marginal tail) and hard
execution ceilings (so a run cannot become a multi-hour runaway).

This spec describes **what** the QA-loop must do and **why**, not how to build it.

### Relationship to spec 003 (dependency, not re-specified here)

Spec **003 — Agent Observability & Per-Task Cost-Budget Guardrail** owns two primitives this feature
**depends on and reuses** rather than re-defining:

- The **budget / cost-ceiling guardrail** (003's P1 MVP) — the token and notional-cost accounting and
  the soft-alert / hard-abort mechanism. This feature **consumes** that guardrail to enforce its
  token/cost ceiling; it does not re-specify how spend is measured or priced.
- **Live observability** (003's P0) — the live "check in on a running workflow" view. This feature
  **relies on** that view to make rounds, tokens, and findings watchable mid-run.

Where this spec says "budget ceiling" or "live visibility," it means **the 003 primitive applied to
the QA-loop**. The QA-loop-specific ceilings (max-fixes, max-rounds, severity bar, scope) are new and
defined here.

### Threat model (sets the impact bar)

These guardrails — and the code the QA-loop tests — protect against **an honest agent's mistakes and
untrusted *content*** (e.g. a malicious string flowing through a hook), **not a determined human
attacker** with arbitrary local control. That framing is the yardstick for impact: a reproducible but
implausible finding (an exotic-encoding evasion, a split-second race on a hook that never runs
concurrently) is **below the bar** because it does not correspond to a realistic threat. Findings that
map to data loss, a security boundary an honest run could cross, or everyday correctness are **at or
above the bar**.

## Clarifications

### Session 2026-06-13
- Q: Should a fully-autonomous "fix everything" mode exist, or is report-first → approve → fix-subset the only path? → A: A **narrow autonomous lane only** — the loop MAY auto-fix unambiguous **top-tier** findings (data-loss / security) without approval; every other finding is report-first → human-approved scoped fix. Auto-fix still honors all ceilings and the severity bar.
- Q: What default severity/impact bar (`QA_MIN_SEVERITY`) should the loop ship with? → A: The **"moderate"** bar — data-loss, security, correctness, **and** robustness findings reach the fix tier; only purely theoretical edge cases go to the won't-fix backlog.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The QA-loop produces a ranked report and stops without touching code (Priority: P1)

A developer runs the QA-loop against a target. It generates and verifies candidate findings, then
produces a **ranked triage report** — findings ordered by real-world impact, each tagged with a
severity/impact class, a reproduction, and a fix/won't-fix recommendation — and **stops**. No branch
is created and no code is changed. The developer reads the report and decides what, if anything, to
fix.

**Why this priority**: This is the MVP and the core behavior change. Report-first-by-default is the
single change that fixes both over-fixing and unsteerability: nothing is altered until a human says
so. It directly prevents the "auto-fixed all 28" failure.

**Independent Test**: Run the QA-loop in its default mode against a target with known issues; confirm
it emits a ranked report listing findings with severities and recommendations, and that the working
tree and git branches are unchanged afterward (no auto-fix occurred).

**Acceptance Scenarios**:

1. **Given** the QA-loop in its default mode, **When** a run completes, **Then** it produces a ranked
   triage report and makes **no** code changes and creates **no** fix branch.
2. **Given** a completed report, **When** the developer reviews it, **Then** each finding shows its
   impact/severity class, a reproduction, the tier it landed in (fix vs. backlog/won't-fix), and a
   recommendation.
3. **Given** a run that found nothing at or above the bar, **When** it completes, **Then** the report
   states that no fix-tier findings were found (and may list below-bar findings as backlog).

---

### User Story 2 - Only high-impact findings are proposed for fixing; pedantic edge cases are won't-fix (Priority: P1)

During verification, each confirmed finding is classified by **real-world impact** (e.g. data-loss,
security, correctness, robustness, or theoretical-edge), not merely by whether it reproduces. Only
findings at or above a configurable severity bar advance into the report's **fix tier**; everything
below the bar is listed in a **backlog / won't-fix tier** with a stated reason. The loop's convergence
is keyed on **"no new findings above the bar"**, so the endless marginal tail can no longer keep it
running.

**Why this priority**: This is what stops the QA-loop from drifting into pedantry and from never
converging. Without the impact bar, report-first still produces an unranked pile dominated by
edge-case noise, and the loop still never settles.

**Independent Test**: Run against a target that yields both a genuine correctness defect and a
theoretical-edge finding; confirm the correctness defect is in the fix tier and the edge case is in
the backlog/won't-fix tier with a reason, and that further rounds producing only below-bar findings do
not extend the run.

**Acceptance Scenarios**:

1. **Given** a confirmed finding, **When** it is verified, **Then** it is assigned an impact/severity
   class in addition to being confirmed reproducible.
2. **Given** a configured minimum-severity bar, **When** a finding's impact is below the bar, **Then**
   it is placed in the backlog/won't-fix tier with a stated reason rather than the fix tier.
3. **Given** consecutive rounds that produce only below-the-bar findings, **When** convergence is
   evaluated, **Then** the loop treats those rounds as "no new qualifying findings" and converges
   (does not keep running on the marginal tail).
4. **Given** a reproducible-but-implausible finding (e.g. an exotic-encoding evasion or a race on a
   never-concurrent hook), **When** it is classified against the threat model, **Then** it lands below
   the bar.

---

### User Story 3 - A developer approves a subset, and only those are fixed on one branch (Priority: P1)

After reviewing the ranked report, the developer approves a specific subset of findings. A **scoped
fix-run** then fixes **only** the approved findings, on a single branch, and leaves everything else
untouched. Approving zero findings results in no changes.

**Why this priority**: This is the "human in the loop, then act" half of report-first. Without it the
report is read-only advice with no safe path to action; with it, fixing is explicit, scoped, and
auditable to one branch.

**Independent Test**: From a produced report, approve N of M findings; run the scoped fix-run; confirm
exactly those N are addressed on a single branch and the other M−N are untouched.

**Acceptance Scenarios**:

1. **Given** a report and an approved subset of N findings, **When** the scoped fix-run executes,
   **Then** only those N findings are fixed and all changes land on a single branch.
2. **Given** an approved subset, **When** the fix-run completes, **Then** findings outside the subset
   are left unchanged (no code touched for them).
3. **Given** zero approved findings, **When** a fix-run is requested, **Then** no code changes are
   made.

---

### User Story 4 - A run aborts gracefully when it hits a ceiling and reports what it found so far (Priority: P2)

A developer runs the QA-loop with execution ceilings configured: a token/notional-cost budget, a
maximum number of confirmed fixes per run, a maximum number of rounds, and optionally a wall-clock
limit. When any ceiling is reached, the run **stops cleanly** and still emits its ranked report of
findings discovered up to that point, noting which ceiling was hit.

**Why this priority**: This is the hard backstop against the four-hour runaway. It is P2 relative to
report-first because report-first already removes the auto-fix blast radius, but the ceiling is what
guarantees the run itself terminates in bounded time/cost regardless of generator creativity.

**Independent Test**: Configure a deliberately low ceiling (e.g. a small max-rounds or a low budget),
run against a target that would otherwise keep producing findings, and confirm the run stops at the
ceiling and emits a partial ranked report naming the ceiling that was hit.

**Acceptance Scenarios**:

1. **Given** a configured token/cost budget, **When** accumulated spend reaches the ceiling, **Then**
   the run stops and reports findings-so-far plus the breached ceiling.
2. **Given** a configured max-fixes-per-run cap, **When** that many findings have been confirmed for
   fixing, **Then** the run stops accruing further fix-tier findings and reports.
3. **Given** a configured max-rounds cap (and/or wall-clock limit), **When** it is reached, **Then**
   the run stops and emits its report.
4. **Given** any ceiling abort, **When** the run stops, **Then** the abort is graceful — a ranked
   report is still produced rather than the run simply being killed with no output.

---

### User Story 5 - A developer scopes a run to one subsystem and watches it live (Priority: P3)

A developer targets a single subsystem (one set of targets) rather than all QA targets at once, and
while it runs opens the live view to watch rounds, tokens, and findings accrue — and can abort if it
is heading somewhere unproductive.

**Why this priority**: Scoping and live visibility make the loop steerable in the moment, but the
report-first default plus ceilings already make a run safe; per-subsystem scoping and watch-and-abort
are refinements that improve focus and control.

**Independent Test**: Configure a run scoped to one subsystem; confirm only that subsystem's targets
are exercised; open the live view (per spec 003's observability) and confirm rounds/tokens/findings
update mid-run and the run can be aborted from there.

**Acceptance Scenarios**:

1. **Given** a per-run target scope naming one subsystem, **When** the run executes, **Then** only
   that subsystem's targets are exercised (not all targets).
2. **Given** a run in flight, **When** the developer opens the live view, **Then** current round,
   token/cost spend, and findings-so-far are visible and updating (via spec 003's observability).
3. **Given** a run in flight, **When** the developer chooses to abort, **Then** the run stops
   gracefully and emits its report of findings so far.

---

### Edge Cases

- **Nothing above the bar**: a run that finds only below-bar issues produces a report whose fix tier
  is empty and whose backlog tier may be populated; default mode still changes no code.
- **Ceiling hit mid-verification**: a finding being verified when a ceiling trips is either resolved
  to a tier or reported as "unverified at abort" — it is not silently dropped.
- **Approved finding no longer reproduces** at fix time (e.g. underlying code changed): the fix-run
  reports it as stale/no-longer-reproducible rather than fabricating a fix.
- **Same defect surfaced by multiple generators**: duplicates collapse to one ranked finding so the
  fix cap and report are not inflated by re-discoveries.
- **A finding's severity is ambiguous** between two classes: it is classified at the higher impact and
  the rationale is recorded, so the bar is applied conservatively.
- **Auto-fix lane vs. opt-in full-auto-fix**: the default run auto-fixes only unambiguous top-tier
  (data-loss / security) findings; a broader opt-in auto-fix mode, if invoked, must still honor the
  ceilings and the severity bar — "auto" changes who approves, not whether bounds apply.

## Requirements *(mandatory)*

### Capability A — Report-first default mode

- **FR-A1**: For every finding **below the top tier**, the QA-loop MUST behave **report-first**:
  generate candidate findings, verify them, produce a ranked triage report, and **stop** — creating no
  branch and changing no code for those findings.
- **FR-A2**: The ranked report MUST order findings by real-world impact and MUST show, per finding, its
  severity/impact class, a reproduction, its tier (fix vs. backlog/won't-fix), and a recommendation.
- **FR-A3**: The QA-loop MAY auto-fix, **without** human approval, ONLY **unambiguous top-tier**
  findings (data-loss / security). Any finding whose top-tier classification is ambiguous MUST be
  routed to the report, not auto-fixed. All **non-top-tier** findings MUST require an explicit human
  approval step before any fix (report-first → approve → scoped fix).
- **FR-A4**: Auto-fixing the **full** set of findings non-interactively MUST NOT be the default or
  implicit; any auto-fix beyond the narrow top-tier lane MUST be an explicit opt-in. Top-tier
  auto-fixes MUST still honor all ceilings (budget, fix-cap, rounds) and MUST be recorded in the report.

*Default: report-first for everything except a narrow autonomous lane for unambiguous data-loss/
security findings; broader auto-fixing is opt-in, never implicit.*

### Capability B — Severity / impact bar

- **FR-B1**: Verification MUST classify each confirmed finding by **real-world impact** (e.g.
  data-loss | security | correctness | robustness | theoretical-edge), in addition to confirming it
  reproduces.
- **FR-B2**: Impact classification MUST apply the stated **threat model** (honest-agent mistakes +
  untrusted content, not a determined attacker), so reproducible-but-implausible findings are
  classified below the bar.
- **FR-B3**: A configurable minimum-severity bar (`QA_MIN_SEVERITY`) MUST gate the report's **fix
  tier**: only findings at or above the bar enter the fix tier; the rest go to the backlog/won't-fix
  tier with a stated reason.
- **FR-B4**: Loop convergence MUST be keyed on **"no new findings at or above the bar"**, so rounds
  that produce only below-bar findings do not extend the run.

*Findings are ranked by impact under an explicit threat model; only above-bar findings are fix-worthy,
and convergence ignores the below-bar tail.*

### Capability C — Bounded execution

- **FR-C1**: A run MUST enforce a **token / notional-cost budget** ceiling, reusing spec 003's budget
  guardrail (this spec does not re-define spend accounting or pricing).
- **FR-C2**: A run MUST enforce a configurable **maximum number of confirmed fixes per run**
  (`QA_MAX_FIXES`).
- **FR-C3**: A run MUST enforce a configurable **maximum number of rounds**, and MAY enforce an
  optional **wall-clock** limit.
- **FR-C4**: When any ceiling is reached, the run MUST abort **gracefully** — stop further work and
  still emit its ranked report of findings discovered so far, naming the ceiling that was breached.

*Every run has hard ceilings on cost, fixes, rounds, and optionally time; hitting one stops the run
cleanly with a partial report.*

### Capability D — Faster fix gate

- **FR-D1**: During a scoped fix-run, per-fix validation MUST run only the **new regression check for
  that finding** plus the **directly-affected** existing checks — not the full integration suite on
  every iteration.
- **FR-D2**: The **full integration suite** (e.g. full build + full validate) MUST run **once at the
  end** of a fix-run, not per fix.

*Each fix is gated by a targeted check; the expensive full suite runs only once, at the end.*

### Capability E — Steering & visibility

- **FR-E1**: A run MUST support **per-run target scoping** so a developer can QA a single subsystem
  rather than all targets at once.
- **FR-E2**: A run MUST expose **live visibility** into rounds, token/cost spend, and findings-so-far
  while in flight, via spec 003's observability (not re-specified here).
- **FR-E3**: A developer MUST be able to **abort a run in flight**, after which the run stops
  gracefully and emits its report of findings so far.

*A run can be scoped to one subsystem, watched live, and aborted by a human mid-flight.*

### Configuration

- **FR-CFG1**: QA-loop behavior MUST be configurable via `.agent/qa.conf`, including at minimum: the
  default **mode** (report-first), the minimum-severity bar (`QA_MIN_SEVERITY`), the max-fixes cap
  (`QA_MAX_FIXES`), the rounds cap, the budget ceiling, and the target scope.
- **FR-CFG2**: With no QA-loop config present, the workflow MUST adopt the safe defaults defined here
  (report-first, ceilings on) rather than reverting to unbounded auto-fix.
- **FR-CFG3**: The default `QA_MIN_SEVERITY` MUST be the **"moderate"** bar: data-loss, security,
  correctness, **and** robustness findings reach the fix tier, while purely theoretical edge cases are
  routed to the won't-fix backlog.

### Key Entities

- **Finding**: one candidate defect — its reproduction, confirmed/unconfirmed status, **impact /
  severity class**, assigned **tier** (fix vs. backlog/won't-fix), and recommendation.
- **Triage report**: the ranked, human-readable output of a default run — findings ordered by impact,
  grouped into fix and backlog/won't-fix tiers, plus run metadata (rounds, spend, any ceiling hit).
- **Severity bar (`QA_MIN_SEVERITY`)**: the configurable threshold separating fix-tier from
  backlog-tier findings and keying convergence.
- **Run ceilings**: the bounded-execution limits for a run — budget (per spec 003), max-fixes
  (`QA_MAX_FIXES`), max-rounds, optional wall-clock.
- **Target scope**: the subset of QA targets (one subsystem or all) a given run exercises.
- **Approved subset**: the human-selected findings a scoped fix-run is permitted to fix.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A typical QA-loop run completes in **minutes, not hours** — there is no run that
  proceeds unbounded (every run terminates at convergence or a ceiling).
- **SC-002**: By default, a run **changes no code and creates no branch**; 0% of default runs auto-fix
  anything without an explicit human approval step.
- **SC-003**: Every default run produces a **ranked triage report** in which each finding carries an
  impact/severity class and a fix-or-won't-fix tier with a reason.
- **SC-004**: Reproducible-but-low-impact findings (the kind that made up most of the 28 in the
  post-mortem) appear in the **backlog/won't-fix tier**, not the fix tier — replaying the post-mortem
  scenario yields a small fix tier and a larger won't-fix tier rather than 28 auto-fixes.
- **SC-005**: When a ceiling (budget, max-fixes, max-rounds, or wall-clock) is configured and reached,
  **100%** of such runs stop gracefully and still emit a report naming the breached ceiling.
- **SC-006**: A scoped fix-run touches **only** the human-approved subset — exactly N of M approved
  findings are addressed and the other M−N are unchanged.
- **SC-007**: A fix-run runs the **full integration suite at most once** (at the end), not once per
  fix — the dominant repeated-full-build cost from the post-mortem is eliminated.
- **SC-008**: A run can be **scoped to a single subsystem** and **aborted mid-flight** by a human,
  after which it still emits a report of findings so far.

## Assumptions

- **Spec 003 is the source of the budget guardrail and live observability.** This feature consumes
  those primitives; if 003 is not yet implemented, the budget-ceiling (FR-C1) and live-visibility
  (FR-E2) requirements depend on it and are not separately built here.
- The existing QA-loop pieces — `.claude/workflows/qa-loop.js`, `.agent/qa.conf`, and the
  `quality-loop` skill — are the components being reshaped; this is an evolution of that workflow, not
  a green-field tool.
- "Real-world impact" is judged against the stated threat model (honest-agent mistakes + untrusted
  content, not a determined attacker); that framing is fixed for this feature.
- The set of severity/impact classes (data-loss, security, correctness, robustness, theoretical-edge)
  is a reasonable default; the exact class names may be refined during planning without changing the
  fix-vs-backlog gating behavior.
- "Directly-affected checks" (FR-D1) are determinable per finding/target; the workflow can identify
  which existing checks relate to a given fix without running the whole suite.
- A run targets a local repository working tree and a single human reviewer/approver; multi-user
  approval workflows are out of scope for this feature.

## Out of Scope

- Re-specifying token/cost accounting, pricing, or the soft-alert/hard-abort mechanism (owned by spec
  003).
- Re-specifying the live observability dashboard/view (owned by spec 003).
- Changing the generators' creativity or the verifier's reproduction mechanism beyond adding impact
  classification.
- Multi-reviewer or remote approval workflows.
