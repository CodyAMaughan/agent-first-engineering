# Data Model: Steerable, Bounded QA-Loop (Report-First)

The QA-loop has no database — its "entities" are in-memory JS objects in `qa-loop.js`, JSON-schema
structured outputs from subagents, POSIX config keys in `qa.conf`, and the persisted report files.
This document defines their fields, validation rules, relationships, and state transitions.

---

## 1. Finding

One candidate defect produced by a generator lens, carried through dedup → verify → rank.

| Field | Type | Source | Notes |
|---|---|---|---|
| `id` | string | derived `keyOf(f)` = `<basename>:<line>:<class>` | dedup key across all rounds |
| `target` | string | generator | a `QA_TARGETS` path |
| `line` | number | generator | file:line of the suspect code |
| `class` | enum(`boundary`,`threat-evasion`,`race`,`encoding`,`gate-false-verdict`,`dos`) | generator | the lens |
| `claim` | string | generator | one-sentence assertion |
| `repro` | string | generator | literal input + exact command + expected-vs-actual |
| `proposedSeverity` | enum(`high`,`med`,`low`) | generator | generator's guess (advisory only) |
| `proposedImpact` | enum impact-class (see §2) \| null | generator (NEW) | advisory hint; the verifier decides authoritatively |

**Validation.** `target` must be in the resolved scope; `repro` non-empty (a finding with no recipe is
dropped per the adversary's discipline). `id` unique (dedup).

**State.** `candidate → (dedup) fresh → (verify) confirmed | rejected → (rank) fix-tier | backlog-tier`.

---

## 2. Verdict (qa-verifier output) — EXTENDED

The structured output of the verifier per finding. **Bold = new in this feature.**

| Field | Type | Notes |
|---|---|---|
| `verdict` | enum(`CONFIRMED`,`WORKS-AS-INTENDED`,`WRONG-THREAT-MODEL`,`LOW-SEV-DEFER`) | unchanged semantics |
| `reproduced` | boolean | `CONFIRMED` requires `true` |
| `evidence` | string | literal command run + captured exit/output, or the reject reason |
| **`impact`** | **enum(`data-loss`,`security`,`correctness`,`robustness`,`theoretical-edge`)** | **real-world impact under the threat model; required when `verdict=CONFIRMED`** |
| **`impactConfidence`** | **enum(`high`,`low`)** | **classification confidence; `low` on a top-tier class blocks the auto-fix lane (→ report)** |
| **`impactRationale`** | **string** | **ties the class to the threat model; recorded in the report** |

**Validation rules.**
- `CONFIRMED` ⇒ `reproduced === true` AND non-empty `evidence` AND a non-null `impact` (the workflow
  discards a `CONFIRMED` lacking these — existing rule, extended to require `impact`).
- **Ambiguous impact ⇒ assign the higher class** and state both candidates in `impactRationale`.
- Threat-model-implausible findings (exotic-encoding evasion, race on a never-concurrent hook) ⇒
  `impact = theoretical-edge` (FR-B2, US2-#4).

---

## 3. Impact ordering & the severity bar

Total order, highest → lowest impact:

```
data-loss  >  security  >  correctness  >  robustness  >  theoretical-edge
```

`QA_MIN_SEVERITY` names the **lowest class still in the fix tier**. Named bars:

| `QA_MIN_SEVERITY` | Fix tier includes | Backlog tier |
|---|---|---|
| `critical` | data-loss, security | correctness, robustness, theoretical-edge |
| `high` | data-loss, security, correctness | robustness, theoretical-edge |
| **`moderate` (DEFAULT)** | **data-loss, security, correctness, robustness** | **theoretical-edge** |
| `low` | all five | — |

**Tiering rule.** `tier = impactRank(finding.impact) >= impactRank(QA_MIN_SEVERITY) ? 'fix' : 'backlog'`.

**Top tier (auto-fix lane).** `data-loss` and `security` only; auto-fixable only when
`impactConfidence === high` (§5).

---

## 4. Run configuration (resolved from qa.conf + args)

| Field | Source key | Default | Notes |
|---|---|---|---|
| `mode` | `QA_MODE` / `args.mode` | `report` | `report` \| `fix` \| `autofix` |
| `targets` | `QA_TARGETS` / `args.targets` | full manifest | per-run scope (FR-E1) |
| `lenses` | `QA_LENSES` | 6 lenses | unchanged |
| `minSeverity` | `QA_MIN_SEVERITY` / `args.minSeverity` | `moderate` | the bar (§3) |
| `maxRounds` | `QA_MAX_ROUNDS` | 4 | rounds cap |
| `dryStreakStop` | `QA_DRY_STREAK` | 2 | convergence streak (now bar-keyed) |
| `maxFixes` | `QA_MAX_FIXES` | 5 | cap on fix-tier findings acted on per run |
| `budget` | `QA_BUDGET` / `.agent/budget.conf` | from 003 | token/cost ceiling (003 primitive) |
| `wallclock` | `QA_WALLCLOCK` | unset (optional) | minutes; deterministic start via `args` |
| `affectedMap` | `QA_AFFECTED_MAP` / `QA_AFFECTED_<target>` | self-test fallback | target→checks for the fast gate (§6) |
| `testCmd` | `TEST_CMD` (lifecycle.conf) | — | full oracle, run once at end |
| `threatModel` | `QA_THREAT_MODEL` | existing | passed to generators + verifier |
| `fixIds` | `args.fix` | — | approved id subset (mode=fix) |

**Validation.** With **no** qa.conf present, the resolved config MUST be the safe defaults above
(report-first, ceilings on) — FR-CFG2. `mode=fix` requires a non-empty `fixIds` resolvable against a
prior `qa-<date>.json` (else: no-op, report "nothing approved").

---

## 5. Run ceilings & convergence (loop state)

| State var | Meaning | Stop condition |
|---|---|---|
| `round` | rounds run | `round >= maxRounds` → stop=`max-rounds` |
| `dryStreak` | consecutive rounds with 0 **at/above-bar** findings | `>= dryStreakStop` → stop=`dry-streak` |
| `fixCount` | fix-tier findings acted on | `>= maxFixes` → stop=`max-fixes` (stop accruing fixes) |
| budget (003) | accumulated token/cost | hard-abort → stop=`budget` |
| wallclock | elapsed minutes | `>= wallclock` → stop=`wall-clock` |

**Auto-fix lane (mode=report).** A finding is auto-fixed iff
`impact ∈ {data-loss,security} AND impactConfidence === high AND fixCount < maxFixes AND budget OK`.
Else → report only.

**Graceful abort.** On **any** stop condition the loop **breaks then runs Triage** → a ranked report is
always emitted, tagged with the breached ceiling (FR-C4, SC-005). A finding mid-verify when a ceiling
trips is recorded as `unverified-at-abort`, never silently dropped (Edge case).

---

## 6. Affected-check selection (fast fix-gate)

| Field | Type | Notes |
|---|---|---|
| `regressionCheck` | string (path/case) | the new RED-first case added for this finding |
| `affectedChecks` | string[] | from `affectedMap`, else the target's own `self_test()` / its check script |

**Gate rule (per fix iteration, FR-D1).** Run `regressionCheck` + `affectedChecks` only. **Not** the
full `TEST_CMD`. **End-of-run (FR-D2).** Run the full `TEST_CMD` exactly once as the final gate.

---

## 7. Triage report (output) — two representations

### 7a. Ranked finding (in `qa-<date>.json`)

| Field | Type | Notes |
|---|---|---|
| `id`, `target`, `line`, `class`, `claim`, `repro` | from Finding | |
| `impact`, `impactConfidence`, `impactRationale` | from Verdict | |
| `evidence` | string | reproduction proof |
| `tier` | enum(`fix`,`backlog`,`auto-fixed`,`unverified-at-abort`) | placement |
| `recommendation` | string | fix / won't-fix-because |
| `fixBranch` | string \| null | set only for auto-fixed / scoped-fixed |

### 7b. Report metadata (run header)

| Field | Type |
|---|---|
| `date`, `mode`, `targets`, `minSeverity` | run params |
| `rounds`, `dryStreak` | loop outcome |
| `stop` | enum(`dry-streak`,`max-rounds`,`max-fixes`,`budget`,`wall-clock`,`aborted`) |
| `spend` | token/cost (from 003) when available |
| `counts` | `{fix, backlog, autoFixed, rejected, unverifiedAtAbort}` |

**Markdown sections** (FR-A2): a one-paragraph summary; **Fix tier** (ranked, with impact + repro +
recommendation); **Auto-fixed (top-tier)** if any; **Backlog / won't-fix** (each with a reason);
**Rejected** (verdict + one-line reason, so never re-investigated); **Unverified-at-abort** if a
ceiling tripped mid-verify.

---

## 8. Approved subset (mode=fix)

| Field | Type | Notes |
|---|---|---|
| `fixIds` | string[] | human-selected ids from a prior report's `qa-<date>.json` |
| resolved findings | Ranked finding[] | looked up by id; ids not in the json → reported skipped |

**Rules.** Only `fixIds` are touched (SC-006); all land on **one** branch. Empty `fixIds` → no code
change (US3-#3). A `fixId` that **no longer reproduces** at fix time → reported `stale/no-longer-
reproducible`, no fabricated fix (Edge case).

---

## Entity relationships

```
qa.conf + args ──► Run configuration ──► round loop
   generators ──► Finding(+proposedImpact) ──► dedup ──► qa-verifier ──► Verdict(+impact)
                                                                              │
                          QA_MIN_SEVERITY ──► tiering ──► Ranked finding ─────┤
                                                                              ▼
                                          mode=report ──► triage report (.md + .json) ──► STOP
                                                       └► auto-fix lane (top-tier, high-conf only)
                                          mode=fix(fixIds) ──► scoped fix-run ──► fast gate ──► full TEST_CMD (once)
```
