# Quickstart: Steerable, Bounded QA-Loop (Report-First)

How the reshaped QA-loop is run and verified. This is the end-to-end "drive it" view that the
`quality-loop` SKILL and `tests/check-qa-loop.sh` are written against.

## 1. Default run — find, rank, STOP (US1)

```sh
# Run the workflow in its default report-first mode (no args needed).
# In Claude Code: invoke the `qa-loop` workflow, or `quality-loop` skill.
```

What happens: `Target-select → (rounds) Generate → dedup → Verify(+impact) → rank → write report → STOP`.

Verify:
- `qa/reports/qa-<date>.md` exists, ranked by impact, each finding tagged with impact class +
  reproduction + tier (fix vs. backlog) + recommendation.
- `git status` is clean and **no new branch** was created (unless a top-tier auto-fix fired — then a
  `qa/loop-fixes-<date>` branch exists and the report's **Auto-fixed (top-tier)** section lists it).

## 2. Only high-impact findings reach the fix tier (US2)

The verifier classifies each confirmed finding's `impact` under the threat model. With the default
`QA_MIN_SEVERITY=moderate`:
- a genuine **correctness** defect → **fix tier**;
- a **theoretical-edge** finding (exotic encoding, race on a never-concurrent hook) → **backlog**, with
  a stated reason.

Convergence keys on "no new finding at/above the bar," so rounds that produce only below-bar findings
do not extend the run.

## 3. Approve a subset, then a scoped fix-run (US3)

```sh
# After reading qa-<date>.md, approve specific ids and run mode=fix:
#   qa-loop  args = { "mode": "fix", "fix": ["test-gate.sh:42:gate-false-verdict", "validate.sh:88:boundary"] }
```

Verify:
- Exactly those ids are fixed, **all on one branch**; every other finding is untouched (SC-006).
- Each fix was gated by its new regression check + directly-affected checks; the **full `TEST_CMD` ran
  once at the end** (SC-007).
- Empty `fix` ⇒ no code change.

## 4. Ceiling hit → graceful partial report (US4)

```sh
# Configure a deliberately low ceiling, e.g. in .agent/qa.conf:  QA_MAX_ROUNDS=1
# or a tiny QA_BUDGET, then run the default mode against a target that keeps producing findings.
```

Verify: the run **stops at the ceiling** and still emits a ranked report whose summary names the
breached ceiling (`stop: max-rounds` / `budget` / `max-fixes` / `wall-clock`). No run goes unbounded
(SC-001, SC-005).

## 5. Scope to one subsystem & watch live (US5)

```sh
# Scope to a subset and watch:
#   qa-loop  args = { "targets": ["\.agent/hooks/git-safety.sh", "\.agent/hooks/secret-scan.sh"] }
#   then open the live view:  /workflows   (spec 003's observability)
```

Verify: only the scoped targets are exercised; rounds/tokens/findings update live; the run can be
aborted mid-flight, after which it still emits a report of findings so far.

## 6. Local verification gate

```sh
sh tests/check-qa-loop.sh    # NEW: asserts defaults (report-first, moderate bar, ceilings on),
                             #      report schema, and the post-mortem replay assertions
sh tests/validate.sh         # wires in check-qa-loop.sh; the agent-first layer is well-formed
.venv/bin/mkdocs build --strict   # docs/skill-mirror gates stay green
```

## Acceptance ↔ artifact map

| Spec item | Verified by |
|---|---|
| SC-002 (default touches no code) | `git status` clean after a default run; `check-qa-loop.sh` asserts no branch sans top-tier |
| SC-003 (every run → ranked report w/ class + tier) | report schema check |
| SC-004 (post-mortem replay → small fix tier, big won't-fix) | `check-qa-loop.sh` replay fixture |
| SC-005 (ceiling → graceful partial report) | low-ceiling run names the breach |
| SC-006 (scoped fix touches only approved subset) | `mode: fix` with N of M ids |
| SC-007 (full suite at most once) | fix-run runs `TEST_CMD` once at end |
| SC-008 (scope + abort) | scoped run + `/workflows` abort |
