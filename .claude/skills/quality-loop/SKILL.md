---
name: quality-loop
version: 0.3.0
description: Lean, safe, report-first adversarial QA of the repo's own tooling. ONE grounded review pass finds the few sharpest real issues (each cited to file:line + a reproduction, abstaining on clean code); a verifier reproduces-or-drops each and classifies it critical/high/low/nitpick; a ranked report is written and the run STOPS — no branch, no code change. Auto-fix is opt-in via a flag and scoped to named severities. Hard-capped by total agents + a token ceiling so it cannot run away. Run it via the qa-loop workflow or by hand. Trigger with "run the quality loop", "review our tooling", "/quality-loop".
---

# Quality Loop (lean)

Find the real bugs in your own tooling without drowning in noise or burning tokens. v2 is deliberately
small: **one grounded review pass → verify each finding → a ranked report → stop.** Report-only by
default; writing code is always an explicit opt-in.

> **Operating principle:** precision over volume. LLM reviewers' dominant failure is *inventing*
> issues (most run >90% noise), so every finding must be **grounded** (cite `file:line` + a
> reproduction) or it's dropped, and **abstaining on clean code is success**. Reproduction — not
> "are you sure?" self-critique — is the gate that kills false positives.

## Why it's shaped this way (the post-mortem)
The previous version fanned out 6 parallel "lens" agents, verified every invented candidate, looped 4
rounds, and had no real cost ceiling — it ran ~2.6h / 3.5M tokens / 105 agents, twice. The research is
unanimous on the fix: a single grounded pass beats a parallel swarm (parallel near-identical agents
duplicate work and burn ~15× tokens); cap **cumulative** agents+tokens (round caps don't bound a
fan-out); ground-or-drop; abstain; collapse nitpicks; gate auto-fix behind a flag.

## The pipeline

```
config → REVIEW (1 grounded agent: the few sharpest issues, cited + reproducible, or ABSTAIN)
       → VERIFY each (reproduce-or-DROP in a sandbox; classify critical/high/low/nitpick)
       → RANK + write qa-<date>.{md,json} → STOP        [report-only: no branch, no code]
       --autofix critical|high → scoped RED-first fix of ONLY those tiers, on one branch
```

| Stage | Agents | Gate | Config |
|---|---|---|---|
| Config | 1 | — | `.agent/qa.conf` |
| Review | 1 | precision-first; returns ≤ `QA_MAX_FINDINGS`; may abstain | `QA_TARGETS`, `QA_THREAT_MODEL` |
| Verify | ≤ findings | **reproduce-or-drop** + severity class | — |
| Fix *(opt-in)* | ≤ `QA_MAX_FIXES` | RED-first; full `TEST_CMD` once at end | `QA_AUTOFIX`, `lifecycle.conf` |
| Report | 1 | writes `.md` + `.json`, STOP | — |

A default run is **~3–6 agents, report-only**. Clean code → ~3 agents and an "abstained" report.

## Severity (replaces the old 5-class scale)
`critical > high > low > nitpick`. **`QA_MIN_SEVERITY` (default `low`)** = lowest tier shown as an
actionable finding; **nitpick is always collapsed** (count shown, details hidden). The verifier assigns
severity from the *reproduced* impact: critical = data-loss/security/breakage; high = a real wrong
result; low = an edge that genuinely bites; nitpick = marginal/theoretical.

## Bounds — always on (no budget directive required)
Enforced in the script at every agent spawn; any breach → **abort + partial report**:
- **`QA_MAX_AGENTS`** (default 10) — total `agent()` calls.
- **`QA_TOKEN_CEILING`** (default 150000) — tokens this run (`budget.spent()` works even with no `+Nk`).
- **`QA_MAX_FINDINGS`** (default 5) — caps the reviewer, bounding verify.
- Optional `.agent/budget.conf` notional-$ ceiling (spec 003), if a `+Nk` directive is active.

## How to run it
- **Default (report-only):** `Workflow qa-loop {}` — reviews `QA_TARGETS`, writes `qa/reports/qa-<date>.md`
  + `.json`, and stops. Watch with `/workflows`; it's hard-capped, so it can't run away.
- **Scope it:** `{ targets: ["path", ...] }` reviews just those.
- **Auto-fix (opt-in):** `{ autofix: "critical" }` or `"critical,high"` — RED-first fixes ONLY those
  tiers on one branch, then runs `TEST_CMD` once. A bare run NEVER writes code.

**By hand:** read the targets → list only the few sharpest issues you can cite + reproduce (abstain
otherwise) → reproduce each in a sandbox, classify severity, drop the unreproducible → write a short
ranked report.

## Evaluation
`tests/eval-qa-loop/` holds the oracle: `planted.sh` (one real critical bug — must be found) and
`clean.sh` (correct — must be abstained on). That's how "working as intended" is checked, not just
"the code parses." See `tests/eval-qa-loop/README.md`.

## Portability
Follows the Agent Skills (`SKILL.md`) standard. Canonical in `.agents/skills/quality-loop/`; mirrored
byte-identical to `.claude/skills/quality-loop/`. Orchestrator: `.claude/workflows/qa-loop.js`;
subagents: `.claude/agents/qa-adversary.md` (reviewer) + `.claude/agents/qa-verifier.md` (verifier).
