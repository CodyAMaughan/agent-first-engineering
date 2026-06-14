---
name: create-mvp
version: 0.1.0
description: Drive a greenfield project from an idea or a spec to its first fully-functional MVP. Refine the spec into a scope-cut vertical slice with a definition-of-done and a test oracle, scaffold (or confirm) a green test harness, decompose the MVP into small always-functional slices, then build each slice test-first on one stacking branch until the oracle is green. Run it autonomously via the create-mvp workflow, or step through it by hand. Trigger with "create the MVP", "take this greenfield idea to a working first version", "/create-mvp".
---

# Create MVP

Take a greenfield project **idea → first fully-functional version**, the agent-first way. The trap with
a new project is building breadth before the core loop works. This flips it: define the *smallest slice
that genuinely works*, stand up an oracle that can prove it, then grow the slice test-first until the
Definition of Done is met. It is "write loops, not prompts" applied to a blank repo.

> **Operating principle:** an MVP is the smallest thing that is *actually functional*, defended by an
> *oracle* (a test command that proves it). Scaffold the oracle FIRST, decompose into slices that each
> leave the project runnable, and build each slice test-first. The oracle decides when a slice — and the
> MVP — is done. No oracle ⇒ you can't tell "looks done" from "is done."

## The pipeline

```
idea / SPEC
   → [SPEC]      refine to a vertical slice + scope-cut + Definition of Done + the test oracle   (reviewer gate)
   → [SCAFFOLD]  agent-first layer + a GREEN test harness so the oracle is live from commit 1     (oracle green)
   → [DECOMPOSE] break the MVP into ordered, always-functional slices
   → [BUILD]     one stacking branch; each slice test-first → oracle → review                     (oracle + reviewer)
   → [INTEGRATE] full Definition-of-Done gate end-to-end                                          (DoD gate)
   → ⏸ human → PR
```

| Stage | Produces | Gate (oracle) | Loops until | Config |
|---|---|---|---|---|
| **Spec** | a tight MVP spec: slice · scope-cut · DoD · test command | reviewer: minimal-yet-functional, scoped, checkable, verifiable | pass or `MAX_SPEC_ROUNDS` | — |
| **Scaffold** | agent-first layer + a green test harness | the oracle (`TEST_CMD`) exits 0 | green | scaffold-agent-project |
| **Decompose** | an ordered list of always-functional slices | — | once | `maxSlices` |
| **Build** | each slice's tests + code on one `mvp/<slug>` branch | `TEST_CMD` exits 0 **and** the slice's tests assert; then a `code-reviewer` pass | green or the cap, per slice | `lifecycle.conf` |
| **Integrate** | (no new code) | a fresh agent checks every DoD bullet end-to-end | once | — |

Everything stack-specific lives in **`.agent/lifecycle.conf`** (`TEST_CMD` = the oracle, branch naming,
per-stage caps) — the same as the feature pipeline, so the two share one config.

## Why one stacking branch (not a branch per slice)
Slices depend on each other (slice 3 needs slice 1's code). So all slices build on a single
`mvp/<slug>` branch and **stack** — unlike the feature pipeline, which branches per feature off main.
That's the one structural difference; everything else is the same soft-procedure + hard-gates + loop.

## How to run it

**Autonomously (the loop):** run the workflow `create-mvp` with `args` = `{ idea: "..." }` or
`{ specPath: "docs/SPEC.md", stack: "..." }`. It refines the spec, confirms/scaffolds the harness,
decomposes, builds each slice test-first, runs the DoD gate, and **stops before the PR**. Watch with
`/workflows`.

**By hand (drive it yourself):**
1. **Spec.** Write the vertical slice + what's OUT + a checkable Definition of Done + the exact test
   command that proves it. Red-team it for "is this really the smallest *functional* thing?"
2. **Scaffold.** Get a green test harness first (the oracle live from commit 1). Reuse
   `scaffold-agent-project` for a new repo.
3. **Decompose.** List ordered slices, each leaving the project runnable.
4. **Build.** Branch `mvp/<slug>`. For each slice: write tests first, confirm RED, code to green, run
   the oracle, review. Stack slices on the one branch.
5. **Integrate.** Check every DoD bullet end-to-end, then hand to a human for the PR.

## Stop conditions (don't let a loop spin)
Per-slice implement cap and per-stage review caps come from `.agent/lifecycle.conf`. If a slice can't
go green within its cap, the workflow **stops and surfaces it to a human** with the failing gate — it
never ships a half-built slice. No oracle for the MVP ⇒ define it first (write the test command).

## Adapting to a new repo
1. Set `TEST_CMD` in `.agent/lifecycle.conf` to the project's real oracle (a deterministic/headless
   test is ideal).
2. Ensure a `code-reviewer` subagent exists in `.claude/agents/` (the scaffolder emits one).
3. Run `create-mvp` with your idea or spec.

## Portability
Follows the Agent Skills (`SKILL.md`) standard. Canonical copy in `.agents/skills/create-mvp/`;
mirrored byte-identical to `.claude/skills/create-mvp/`. The orchestrator is
`.claude/workflows/create-mvp.js`. Pairs with `feature-lifecycle` (single features, post-MVP).
