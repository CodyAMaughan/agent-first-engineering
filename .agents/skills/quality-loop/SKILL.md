---
name: quality-loop
version: 0.2.0
description: Steerable, bounded, REPORT-FIRST adversarial QA of the repo's own tooling. Generate candidate failure modes, REPRODUCE each against the real code AND classify its real-world impact under the threat model, then write a ranked triage report and STOP for human review — no branch, no code change, except a narrow auto-fix lane for unambiguous data-loss/security findings. A human approves a subset; only that subset is fixed, on one branch, with a fast fix-gate. Every run is bounded (budget + max-fixes + rounds); any ceiling yields a graceful partial report. Run it via the qa-loop workflow or by hand. Trigger with "run the quality loop", "adversarially test our tooling", "/quality-loop".
---

# Quality Loop

Break the tools before your users (or your agents) do — the agent-first way: adversarial agents
*generate* candidate failures, a hostile skeptic *reproduces* each against the real code **and classifies
its real-world impact**, and the loop writes a **ranked triage report and stops for human review**. Only
a human-approved subset gets fixed (test-first), on one branch. This is "write loops, not prompts"
pointed at your own quality bar (Phases 3 + 6) — now **report-first and bounded** so it can't run away.

> **Operating principle:** generation is cheap and mostly noise; a finding counts only when a hostile
> skeptic has **reproduced** it AND it clears an **impact bar** under the threat model. Discovery is
> read-only and *stops* for review; *action* is scoped, branched, and human-gated. This is *confirm RED
> before green* applied to QA — plus "rank by real impact, then let a human steer."

## Why report-first (the post-mortem)
An earlier unbounded run went for ~4 hours, surfaced 28 "bugs" in the repo's own guardrail hooks, and
**auto-fixed every one** on its own branch — yet most were pedantic edge cases (exotic encodings,
theoretical races on hooks that never run concurrently). Four root causes, four fixes:

| Failure | Fix |
|---|---|
| No ceiling → ran for hours | **Bounded execution** — budget + `QA_MAX_FIXES` + rounds cap; any breach → partial report |
| Acceptance bar was just "reproduces?" | **Impact bar** — classify each finding; only at/above `QA_MIN_SEVERITY` is fix-worthy |
| Fire-and-forget, no human checkpoint | **Report-first** — discovery stops; a human approves a subset to fix |
| Never converged (always one more edge case) | **Bar-keyed convergence** — the below-bar marginal tail can't extend the run |

## The pipeline

```
targets → [GENERATE] → dedup → [VERIFY +impact] → [RANK] → [TRIAGE report] → ⏸ human
            │ (fan-out)          │ reproduce         │ tier vs the bar   │ .md + .json
          N lens-agents        skeptic + impact    fix | backlog        STOP (default)
          (candidates)         class               │
                                                    └─► auto-fix lane: ONLY unambiguous
                                                        data-loss/security (high-confidence)

  then, separately:  human approves ids → [mode: fix] → scoped fixes on one branch
                                            fast gate per fix · full TEST_CMD once at end
```

| Stage | Actor produces | Gate (oracle) | Loops until | Config |
|---|---|---|---|---|
| **Generate** | candidates (per lens) + a `proposedImpact` hint | — (volume is fine) | every lens runs | `QA_LENSES`, `QA_TARGETS` |
| **Verify** | a verdict **+ impact class + confidence** per finding | skeptic must **reproduce** it, else REJECT | every fresh finding judged | `QA_THREAT_MODEL` |
| **Rank** | each confirmed finding tiered fix vs. backlog | impact vs. `QA_MIN_SEVERITY` | once per round | `QA_MIN_SEVERITY` |
| **Triage** | a **ranked report** (`.md` + `.json` sidecar) | — | once, on every terminating path | — |
| **Fix** *(only on approval / auto-fix lane)* | a regression test (RED first) + a minimal fix | **fast gate** (regression + affected checks); full `TEST_CMD` **once at end** | green or the fix cap | `lifecycle.conf` `TEST_CMD`, `QA_AFFECTED_MAP` |

## Modes (the steering control)

| `mode` | Branch? | Code change? | Approval | Output |
|---|---|---|---|---|
| **`report`** (default) | only if the top-tier auto-fix lane fires | only unambiguous **data-loss/security** (high-confidence) | none beyond that narrow lane | ranked `.md` + `.json`, then **STOP** |
| `fix` | one branch | only the approved `fix` id subset | a human passed the ids | scoped fixes + end-of-run full `TEST_CMD` |
| `autofix` (opt-in) | one branch | the whole fix tier | none (explicit opt-in) | full-auto fixes, still honoring ceilings + the bar |

**Default is report-first for everything except a narrow autonomous lane** for unambiguous
data-loss/security findings. Broader auto-fixing is opt-in, never implicit. With **no** `qa.conf`
present the workflow still adopts the safe defaults (report-first, ceilings on) — never unbounded.

## The impact bar (so the loop stops chasing pedantry)
The verifier classifies each confirmed finding by **real-world impact** under the threat model:

```
data-loss  >  security  >  correctness  >  robustness  >  theoretical-edge
```

`QA_MIN_SEVERITY` names the lowest class still in the **fix tier**; the rest go to the **backlog /
won't-fix tier** with a stated reason. **Default `moderate`**: data-loss, security, correctness, and
robustness reach the fix tier; purely **theoretical-edge** findings (exotic encodings, a race on a
never-concurrent hook) go to the backlog. Ambiguous class ⇒ assigned the **higher** one (conservative).
**Convergence keys on "no new finding at/above the bar"**, so below-bar noise can't keep the loop alive.

## Bounded execution (no more runaways)
Every run is hard-bounded and any breach yields a **graceful partial report** naming the ceiling:
- **Budget** — reuses spec 003's cost guardrail (`.agent/budget.conf`), **wired into** `qa-loop.js`
  (`BudgetBreaker.checkpoint()` each round + after each verify/fix). Absent/disabled ⇒ degrade to the
  caps below.
- **`QA_MAX_FIXES`** — cap on fix-tier findings acted on per run.
- **`QA_MAX_ROUNDS`** — hard rounds cap; **`QA_DRY_STREAK`** — bar-keyed convergence streak.
- **`QA_WALLCLOCK`** (optional) — wall-clock minutes.

## How to run it

**Autonomously (the loop):** run the workflow `qa-loop`. Default `mode: report` fans out the lenses,
reproduces + classifies each candidate, ranks them, **writes `qa/reports/qa-<date>.md` + `.json` and
stops** — no code touched (bar the narrow lane). Watch it live with `/workflows` (spec 003's
observability) and abort mid-flight if it heads somewhere unproductive — it still emits its report.

**Approve & fix a subset (US3):** read the report, then run `qa-loop` with
`args = { "mode": "fix", "fix": ["<id>", ...] }`. The ids resolve against the latest `qa-<date>.json`
sidecar; only those are fixed, on one branch. Each fix is gated by its new regression case + the
directly-affected checks; the **full `TEST_CMD` runs once at the end** (not per fix). Empty subset ⇒
no change. Unknown ids are reported skipped; a finding that no longer reproduces is reported, not faked.

**Scope a run (US5):** `args = { "targets": ["<path>", ...] }` QAs one subsystem instead of all targets.

**By hand (drive it yourself):**
1. **Generate.** Per target + lens, write candidate failures — each with `file:line`, a one-line claim,
   a literal repro recipe, and a `proposedImpact` hint.
2. **Verify.** `mktemp -d`, write the failing input, run the real script/hook, capture exit+output.
   CONFIRM only if reproduced — then **classify impact** under the threat model (conservative: ambiguous
   → higher class). Otherwise reject with a reason.
3. **Rank & report.** Tier each confirmed finding fix vs. backlog by impact vs. `QA_MIN_SEVERITY`; write
   the ranked report and **stop**.
4. **Fix (only the approved subset).** Add a regression case and confirm it FAILS first (RED), make the
   minimal fix, run the fast gate (regression + affected checks), and the **full** `TEST_CMD` once at end.

## Threat model (so you don't chase non-bugs)
These guardrails — and the code the loop tests — protect against an **honest agent's mistakes** and
**untrusted content** the agent reads (the lethal trifecta), *not* a determined local attacker with
file-write/RCE (that's out of scope). That framing is the impact yardstick: a reproducible-but-
implausible finding (exotic-encoding evasion, a split-second race on a never-concurrent hook) is
**below the bar** (theoretical-edge). Findings that map to data loss, a security boundary an honest run
could cross, or everyday correctness/robustness are **at or above it**.

## Adapting to a new repo
1. Set `QA_TARGETS` in `.agent/qa.conf` to that project's risky surfaces (its hooks, gates, scripts),
   and keep the defaults (`QA_MODE=report`, `QA_MIN_SEVERITY=moderate`, the ceilings) so a run can't run
   away.
2. Ensure `qa-adversary` + `qa-verifier` subagents exist in `.claude/agents/` (the verifier must emit
   the `impact`/`impactConfidence`/`impactRationale` fields) and a `TEST_CMD` in `.agent/lifecycle.conf`.
3. Run the `qa-loop` workflow. Keep `tests/check-qa-manifest.sh` (manifest) and `tests/check-qa-loop.sh`
   (the post-mortem replay gate) so the loop's own invariants stay enforced.

## Portability
Follows the Agent Skills (`SKILL.md`) standard. Canonical copy in `.agents/skills/quality-loop/`;
mirrored byte-identical to `.claude/skills/quality-loop/`. The orchestrator is
`.claude/workflows/qa-loop.js`; its pure decision logic lives in `.claude/workflows/lib/qa-classify.js`,
`qa-convergence.js`, and `qa-report.js` (unit-tested with `node --test`); the subagents are
`.claude/agents/qa-adversary.md` and `.claude/agents/qa-verifier.md`.
