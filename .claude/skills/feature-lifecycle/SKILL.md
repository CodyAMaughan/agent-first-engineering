---
name: feature-lifecycle
version: 0.1.0
description: Drive a feature from request to a review-ready PR through verified stages — spec → plan → implement → test-gate → review — where each stage loops until its oracle (a reviewer subagent or the test command) passes. Run it autonomously via the feature-pipeline workflow, or step through it by hand. Trigger with "run the feature lifecycle", "take this feature through the pipeline", "/feature-lifecycle <feature>".
---

# Feature Lifecycle

Take a feature **request → implemented & verified**, the agent-first way: the agent is *prompted*
through a procedure, but never *forced* — each stage advances only when its **gate (oracle)** passes,
and the orchestrating **loop** re-runs a stage until it does. This is "write loops, not prompts"
applied to the software lifecycle (Phase 9.2) using the building blocks (Phases 6–8).

> **Operating principle:** soft procedure (this skill) + hard gates (tests, reviewers, CI) + a loop
> that iterates until the gates pass. The skill says *what* to do; the gates decide *when it's done*.

## The pipeline

```
request → [SPEC] → [PLAN] → [IMPLEMENT] → [REVIEW] → ⏸ human → PR → (CodeRabbit + CI)
            │        │          │            │
          review   review    TEST_CMD    code-reviewer
          gate     gate      gate        subagent gate
```

| Stage | Actor produces | Gate (oracle) | Loops until | Config |
|---|---|---|---|---|
| **Spec** | a short spec (goal · scope · contracts · acceptance criteria) | a reviewer subagent: is it clear, scoped, testable? | pass or `MAX_SPEC_ROUNDS` | — |
| **Plan** | a plan (files, approach, test strategy) | reviewer: does the plan satisfy the spec? | pass or `MAX_PLAN_ROUNDS` | — |
| **Implement** | code on a `feat/` branch, behind tests | **`TEST_CMD`** (+ lint/typecheck) exits 0 | green or `MAX_IMPLEMENT_ROUNDS` | `TEST_CMD`, `LINT_CMD` |
| **Review** | (no new code) | a `code-reviewer` subagent: no must-fix findings, no gamed gates | clean or `MAX_REVIEW_ROUNDS` | `REVIEW_SUBAGENT` |
| **PR** *(human)* | a branch + summary + review verdict | **a person** opens/approves the PR | — | `STOP_BEFORE_PR` |

Everything stack-specific lives in **`.agent/lifecycle.conf`** — point `TEST_CMD` etc. at *your*
project's real commands and the orchestrator is unchanged. The default config targets this repo
(`mkdocs --strict` + the parity/validate checks).

## How to run it

**Autonomously (the loop):** run the workflow `feature-pipeline` with the feature as `args`. It runs
spec → plan → implement → review, looping each stage on its gate, and **stops before the PR** so you
review the branch and open it yourself. Watch it with `/workflows`.

**By hand (drive it yourself):** follow the stages above in order. At each one, do the work, then run
the gate — *do not advance until the gate is green*:
1. **Spec.** Write goal / scope / 1–2 contracts / acceptance criteria. Have a fresh agent (or yourself) red-team it for ambiguity.
2. **Plan.** List the files you'll touch and the test strategy. Check it against the spec.
3. **Implement.** Branch `feat/<slug>`. Write the test first where you can, then the code. Run `TEST_CMD` — loop until green.
4. **Review.** Invoke the `code-reviewer` subagent on the diff (fresh context, least-privilege). Fix must-fix findings; re-review.
5. **PR.** Open it. CodeRabbit + CI are the outermost gates; a human approves.

## Stop conditions (don't let a loop spin)
Each stage has a max-rounds cap in `.agent/lifecycle.conf`. If a stage hits its cap without passing,
the pipeline **stops and surfaces it to a human** with the failure and the last gate output — it never
spins burning tokens or ships a half-done stage. No oracle for a stage → don't loop it; make the oracle
first (write the test, define the acceptance criteria).

## Adapting to a new repo
1. Copy `.agent/lifecycle.conf` and set `TEST_CMD` / `LINT_CMD` / `BASE_BRANCH` to that project's commands.
2. Ensure a `code-reviewer` subagent exists in `.claude/agents/` (the scaffolder emits one).
3. Run the `feature-pipeline` workflow with your feature request.

## Portability
Follows the Agent Skills (`SKILL.md`) standard. Canonical copy in `.agents/skills/feature-lifecycle/`;
mirrored byte-identical to `.claude/skills/feature-lifecycle/`. The orchestrator is
`.claude/workflows/feature-pipeline.js`.
