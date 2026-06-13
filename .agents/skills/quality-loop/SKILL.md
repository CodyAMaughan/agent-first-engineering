---
name: quality-loop
version: 0.1.0
description: Adversarially QA the repo's own tooling (hooks, test scripts, the orchestrator). Generate candidate failure modes, REPRODUCE each against the real code, fix the confirmed ones test-first, and loop until consecutive rounds confirm nothing new. A finding counts only when a skeptic has reproduced it — confirm-RED-before-green applied to QA. Run it autonomously via the qa-loop workflow, or step through it by hand. Trigger with "run the quality loop", "adversarially test our tooling", "/quality-loop".
---

# Quality Loop

Break the tools before your users (or your agents) do — the agent-first way: adversarial agents
*generate* candidate failures, a hostile skeptic *reproduces* each against the real code, and only
**reproduced** defects get fixed (test-first). The loop re-runs until it converges. This is "write
loops, not prompts" pointed at your own quality bar (Phases 3 + 6).

> **Operating principle:** generation is cheap and mostly noise; a finding counts only when a hostile
> skeptic has **reproduced** it against the real code. This is *confirm RED before green* applied to
> QA — the **Verify** stage is the oracle, and the loop converges on **reproduced** defects, not
> candidates. A QA pass that only generates yields a long list of plausible-but-wrong claims.

## The pipeline

```
targets → [GENERATE] → dedup → [VERIFY] → [FIX] → [TRIAGE] → ⏸ human → PR
            │ (fan-out)          │ reproduce  │ RED→GREEN
          N lens-agents        skeptic      regression test first,
          (candidates)         or REJECT    full-oracle gate
                                  └──────── loop rounds until dry ────────┘
```

| Stage | Actor produces | Gate (oracle) | Loops until | Config |
|---|---|---|---|---|
| **Generate** | candidate findings (per lens), each with a literal repro recipe | — (no gate; volume is fine) | every lens runs | `QA_LENSES`, `QA_TARGETS` |
| **Verify** | a verdict per finding | the skeptic must **reproduce** it in a temp dir, else REJECT | every fresh finding judged | — |
| **Fix** | a regression test (RED first) + a minimal fix | the **full `TEST_CMD`** (from `lifecycle.conf`) exits 0 **and** the new case asserts | green or the fix cap | `lifecycle.conf` `TEST_CMD` |
| **Triage** | a report (confirmed-fixed / deferred / rejected-with-reason) | — | once | — |

The systems-under-test, the lenses, and the circuit breakers live in **`.agent/qa.conf`**. The
regression oracle is **not** duplicated there — the loop reads `TEST_CMD` from `.agent/lifecycle.conf`
so QA and the feature pipeline share one source of truth.

## Why a Verify stage at all
A prior one-shot adversarial sweep of this repo's tooling produced ~50 candidate findings — but most
were **miscalibrated** (wrong threat model) or **outright false** (a "bug" that the code already
guards against). Without a reproduce-or-reject gate, you fix noise and miss signal. The Verify stage
is the whole point: **a claim you cannot reproduce is not a bug.**

## How to run it

**Autonomously (the loop):** run the workflow `qa-loop` (optionally with `args` to scope targets /
min-severity). It fans out the lenses, reproduces each candidate, fixes confirmed issues RED-first,
loops until the dry-streak, and **stops before the PR**. Watch it with `/workflows`.

**By hand (drive it yourself):**
1. **Generate.** For each target + lens, read the code and write candidate failures — each with the
   exact `file:line`, a one-line claim, and a literal repro recipe (the input + the command + expected
   vs. actual).
2. **Verify.** For each candidate, `mktemp -d`, write the minimal failing input, run the real
   script/hook, capture exit+output. CONFIRM only if you reproduced it; otherwise reject with a reason.
3. **Fix.** For each CONFIRMED: add a regression case (extend the script's own `self_test()` where it
   has one) and **confirm it FAILS first** (RED) — a regression test that passes before the fix is
   invalid. Then make the minimal fix, run the **full** `TEST_CMD`, loop until green.
4. **Triage.** Record confirmed-fixed, confirmed-deferred, and rejected (with the reason, so it's
   never re-investigated).

## Threat model (so you don't chase non-bugs)
An actor who can already write tracked files in this repo already has code execution — the guardrail
hooks are protection against an **honest agent's mistakes** and against **untrusted content the agent
reads** (the lethal trifecta), *not* a sandbox against a malicious local user. Findings that
presuppose arbitrary file-write / RCE are **out of scope**. Target: false-negatives (guard evasions),
false gate verdicts, untrusted-content escapes, and robustness (paths-with-spaces, encoding, races).

## Stop conditions (don't let a loop spin)
Two independent breakers in `.agent/qa.conf`: `QA_DRY_STREAK` (stop after K consecutive rounds that
confirm **zero** new issues — counts *confirmed*, so a round of pure noise still advances the streak)
and `QA_MAX_ROUNDS` (a hard cap). Rejected findings are remembered so they're never re-litigated.

## Adapting to a new repo
1. Set `QA_TARGETS` in `.agent/qa.conf` to that project's risky surfaces (its hooks, gates, scripts).
2. Ensure `qa-adversary` + `qa-verifier` subagents exist in `.claude/agents/` (and a `TEST_CMD` in
   `.agent/lifecycle.conf` to gate fixes).
3. Run the `qa-loop` workflow. Keep `tests/check-qa-manifest.sh` so the loop can QA its own manifest.

## Portability
Follows the Agent Skills (`SKILL.md`) standard. Canonical copy in `.agents/skills/quality-loop/`;
mirrored byte-identical to `.claude/skills/quality-loop/`. The orchestrator is
`.claude/workflows/qa-loop.js`; the subagents are `.claude/agents/qa-adversary.md` and
`.claude/agents/qa-verifier.md`.
