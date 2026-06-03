# Curriculum Outline — Agent-First Engineering

*From "vibe coding" to "systems engineer for agents." Audience: intermediate developers who
already use AI agents informally. Agent-agnostic (Claude Code / Codex / Cursor), built on open
standards. v1 — 2026-06-01.*

Each phase = a single competency, taught one concept at a time with diagrams, a worked example,
and a hands-on exercise per lesson, plus a check-understanding quiz. **Lockstep principle:** every
phase maps to something the companion scaffolder generates — so learners graduate by recognizing
(then running) automation of a process they understand.

```
  vibe coding ──► P1 Fundamentals ──► P2 Context Eng ★★★ ──► P3 Verification ★★★
                                                                      │
   systems engineer ◄── P6 Harness ◄── P5 Spec-Driven ◄── P4 Session & Memory
```

> ★★★ = load-bearing. If you internalize only two phases, make them **2 and 3** — every
> researched source (Anthropic, OpenAI harness engineering, Cursor, 12-factor-agents) converges
> on context engineering and verification as the highest-leverage practices.

---

## Phase 1 — Fundamentals: the agentic loop

**Objective:** Drive a task through **explore → plan → code → commit** with specific, context-rich
prompts; use plan mode to align on *what* before *how*; know when a task is too small to plan.

**Lessons**
1. The loop: why "explore→plan→code→commit" beats "just ask for code" (the agent solves the wrong problem when it skips exploration).
2. Prompt specificity: name the file, the constraint, the example pattern, the definition of done.
3. Feeding context, not describing it: `@file`, screenshots, piped data, URLs.
4. Plan mode first — and when to skip it (one-line diffs don't need a plan).

**Diagram**
```
  EXPLORE ──► PLAN ──► CODE ──► COMMIT
  (read,      (cheap,   (against  (small,
   ask)       editable  the plan)  reviewable)
              artifact)
```

**Maps to scaffolder:** the `init` **interview UX** itself (the tool models good explore→plan
behavior by interviewing you before generating).

**Check understanding:** when is planning waste? what makes a prompt "specific enough"?

---

## Phase 2 — Context Engineering ★★★

**Objective:** Treat the context window as the scarce resource. Manage it deliberately with
`/clear`, compaction, fresh sessions, and the spec handoff — and recognize context degradation as
the *primary* failure mode of agentic coding.

**Lessons**
1. The context window is a desk, not a filing cabinet (ELI5 + why it's finite).
2. Context rot: why long sessions degrade and accumulate failed approaches.
3. The three moves: `/clear` (reset), `/compact` (summarize with intent), fresh session (start over with a better prompt).
4. The spec handoff: interview → `SPEC.md` → **fresh** session to implement.
5. What the scaffolder gives you: the capture-learnings-before-compaction memory loop.

**Maps to scaffolder:** the **capture-learnings memory loop** hook (`pre-compact`/`session-end`
→ merge learnings into `.agent/memory/*.md`; `session-start` → re-inject).

**Check understanding:** see the [fully-written exemplar](curriculum/02-context-engineering/index.md) →

---

## Phase 3 — Verification & TDD ★★★

**Objective:** Give the agent an **external oracle** (tests, build exit code, linter,
screenshot-diff) so it closes its own loop instead of stopping at "looks done" — and use TDD so
correctness survives long sessions.

**Lessons**
1. "Looks done" is not done: why you become the verification loop without an oracle.
2. The oracle gradient: in-prompt check → goal condition → `Stop` hook → verification subagent.
3. TDD with agents: write tests first, confirm they **fail**, implement to green.
4. Oracles for the un-testable: screenshot-diffs and visual feedback for UI.

**Diagram**
```
  agent writes code ──► runs oracle ──► pass? ──► done
                            ▲             │ no
                            └─────────────┘  (self-corrects, no human in loop)
```

**Maps to scaffolder:** the **test-gate / `Stop`-gate hooks** (refuse to finish until tests/build
pass) + post-edit lint/format hooks.

**Check understanding:** why confirm tests fail first? where does the human stay in the loop?

---

## Phase 4 — Session & Memory Discipline

**Objective:** Course-correct early; author and *prune* minimal steering files
(`AGENTS.md` / skills); promote must-always-happen rules from prose into deterministic hooks.

**Lessons**
1. Interrupt drift early; cheap rewind/checkpoints license risky attempts.
2. `AGENTS.md` done right: short, imperative, command-first, version-controlled (and what NOT to put in it).
3. Skills vs rules vs commands: the decision, and progressive disclosure.
4. "If it must happen every time, it's a hook, not a sentence" — promoting prose to enforcement.

**Diagram**
```
  prose rule  ──(must happen every time?)──►  hook (deterministic)
       └──(style/intent?)──► AGENTS.md (guidance)
```

**Maps to scaffolder:** `AGENTS.md` generation + `.agents/skills/` starter library + the
prose-to-hook promotion.

**Check understanding:** when does a CLAUDE.md line belong in a hook instead? why does a bloated
steering file *reduce* adherence?

---

## Phase 5 — Spec-Driven Development

**Objective:** Turn a vague idea into a precise, self-contained, executable spec; treat the
**spec — not the code — as the source of truth** that regenerates implementation. (This very repo
dogfoods Spec Kit.)

**Lessons**
1. Why specs beat prompts at system scale (the spec is durable; code is regenerable).
2. The Spec Kit loop: constitution → specify → plan → tasks → implement.
3. Separating WHAT (spec, no tech) from HOW (plan, tech choices).
4. Spec as steering wheel: catching misunderstanding in the spec, not in 2,000 lines of code.

**Maps to scaffolder:** the **Spec Kit hand-off** (the tool offers to run `specify init`).

**Check understanding:** what belongs in the spec vs the plan? why is the spec the source of truth?

---

## Phase 6 — Orchestration & Harness Engineering (capstone)

**Objective:** Decompose work into small focused agents (writer/reviewer, adversarial review,
git worktrees); then graduate to **harness engineering** — encode mechanical "golden principles,"
enforce architecture with linters + CI, structure machine-parsable docs as the source of truth,
wire telemetry, and run recurring cleanup. **Design the environment, not the edit.**

**Lessons**
1. Small focused agents (12-factor #10): why scope kills quality and how subagents protect context.
2. Adversarial review: a fresh-context reviewer that sees only the diff + criteria.
3. Parallelism via git worktrees; headless/CI fan-out.
4. Harness engineering: golden principles + CI enforcement + machine-parsable docs + telemetry.
5. Defining a team's direction: standardize the agent-first core, enforce non-negotiables, measure babysitting.

**Diagram**
```
  per-diff review  ──────────────►  environment design
  (human is the      harness eng.   (agent correct
   bottleneck)                       by construction)
```

**Maps to scaffolder:** the **full guardrail layer + CI workflow templates + the per-agent adapter
system** — i.e. the whole tool is the capstone artifact.

**Check understanding:** when do you delegate to a subagent? why scope a reviewer to correctness
only? what does "design the environment" mean concretely?

---

## Capstone artifact (the graduation)

The learner runs the scaffolder on a real new project (or `adopt`s an existing one) and annotates
each generated artifact with the phase that taught it — `AGENTS.md` (P4), memory loop (P2), test
gate (P3), Spec Kit hand-off (P5), the adapter/CI layer (P6). The tool stops being magic and
becomes *automation of a process they understand.*

## Open design questions (to revisit post-Thursday)

- Static-site presentation (`data.js` like the reference repo) vs markdown-only — markdown for v1.
- Per-phase quiz delivery (a `check-understanding`-style skill?) vs static markdown quizzes.
- Whether Phase 6 splits back into two phases (orchestration / harness) as content grows.
