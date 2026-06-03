# Feature Specification: Agent-First Engineering Curriculum (Deliverable A)

**Feature Branch**: `001-curriculum`

**Created**: 2026-05-30

**Status**: Draft

**Input**: User description: "A phased, visual curriculum — modeled structurally on the
well-organized 'AI Engineering from Scratch' repo — that takes a developer from
'loosey-goosey vibe coding with AI agents' to 'thinking like a systems engineer who
designs codebases for AI agents to succeed.' Teaches the open standards (AGENTS.md,
SKILL.md), spec-driven development, guardrails/hooks, and agent-agnostic setup. Each
phase culminates in the learner producing a real artifact that the companion Scaffolder
(Deliverable B) can also generate."

## Curriculum Structure (v1 — agreed 2026-06-01)

**Primary audience:** intermediate developers who already use AI agents informally ("vibe
coding") and want to operate like a systems engineer. Phase 1 assumes basic agent usage and
moves quickly toward the systems-level material. (Not aimed at total beginners; a "team
direction-setter" framing is layered in via the executive summary and the harness-engineering
capstone.)

**Six phases** (compressed from the 9-competency research ladder; ★★★ = load-bearing):

| # | Phase | One-line objective | Scaffolder artifact (lockstep) |
|---|---|---|---|
| 1 | **Fundamentals** | Drive a task through explore→plan→code→commit with specific, context-rich prompts; use plan mode; know when to skip it. | the `init` interview UX itself |
| 2 | **Context Engineering** ★★★ | Treat the context window as the scarce resource: `/clear`, compaction, fresh sessions, the spec handoff. | the capture-learnings memory loop hook |
| 3 | **Verification & TDD** ★★★ | Give the agent an external oracle (tests/build/lint/visual) so it closes its own loop. | the test-gate / `Stop`-gate hooks |
| 4 | **Session & Memory Discipline** | Course-correct early; author and *prune* minimal `AGENTS.md`/skills; promote must-haves into hooks. | `AGENTS.md` + `.agents/skills/` generation |
| 5 | **Spec-Driven Development** | Turn a vague idea into an executable spec; spec is the source of truth (Spec Kit). | the Spec Kit hand-off |
| 6 | **Orchestration & Harness Engineering** | Small focused agents, adversarial review, worktrees; encode "golden principles," enforce with CI; design the environment, not the edit. | full guardrail layer + CI templates + adapters |

The two ★★★ phases (Context Engineering, Verification) carry the most weight across all
researched sources and are the non-negotiable core. Phase 6 (Harness Engineering) is the
capstone — the true "systems engineer for agents" frontier.

**Per-phase contract:** each phase has a one-line objective, 3–5 single-concept lessons (each
with a diagram, a worked example, and one hands-on exercise), an explicit mapping to the
scaffolder output it teaches, and a non-trivial check-understanding quiz.

## User Scenarios & Testing *(mandatory)*

<!--
  Each user story is an independently shippable slice. A learner who completes only
  Phase set 1 already has a usable, better-organized repo — that is the MVP.
-->

### User Story 1 - The "loosey-goosey → agent-ready repo" core path (Priority: P1) 🎯 MVP

A developer who has been coding with AI agents informally works through the foundational
phases and, by the end, has hand-built (and understood) a complete agent-first setup for a
real project of their own: an `AGENTS.md`, a small `SKILL.md` library, lifecycle-hook
guardrails, and a spec-driven workflow. They understand *why* each piece exists, not just
that it exists.

**Why this priority**: This is the entire value proposition — moving a self-taught "vibe
coder" to a systems-engineering mindset. Even if no later phase is built, this path alone
transforms how the learner starts every future project.

**Independent Test**: Hand the foundational phases to a developer who codes with agents but
has never written an `AGENTS.md`. Verify they can, unaided afterward, explain and produce
a working agent-first scaffold for a fresh repo, and articulate why minimal-context and
deterministic-guardrail choices were made.

**Acceptance Scenarios**:

1. **Given** a learner at the first phase, **When** they complete the foundational track,
   **Then** their target repo contains a hand-authored `AGENTS.md`, at least one working
   `SKILL.md`, and at least one guardrail hook that actually blocks a violation.
2. **Given** a completed foundational track, **When** the learner is asked "why is a stale
   architecture overview harmful?", **Then** they can explain the inference-cost/context
   trade-off in their own words.
3. **Given** any single phase, **When** the learner finishes it, **Then** they have produced
   one concrete, inspectable artifact (not just read prose).

---

### User Story 2 - Visual, ELI5, one-concept-at-a-time pedagogy (Priority: P1)

The curriculum teaches the way the learner learns best: one lesson at a time, heavy on
diagrams and plain-language (ELI5) explanations, with interactive checkpoints rather than
walls of text. Each phase has a small number of lessons; each lesson has a diagram, a
concrete example, and a "your turn" action.

**Why this priority**: Pedagogy is co-equal with content here. The reference repo
("AI Engineering from Scratch") is valued specifically for being well-organized and
digestible; replicating that structure is a primary requirement, not a nicety.

**Independent Test**: Review any lesson in isolation — it must stand alone with a diagram,
an example, and a single actionable exercise, readable in one sitting without prerequisites
beyond the prior lesson.

**Acceptance Scenarios**:

1. **Given** any lesson, **When** it is opened, **Then** it contains at least one diagram,
   one worked example, and exactly one primary exercise.
2. **Given** a phase, **When** its lesson count is measured, **Then** it stays within a
   small, consistent range (no sprawling mega-lessons).
3. **Given** the repo, **When** a learner wants to know where to start, **Then** a
   placement mechanism points them to the right phase based on what they already know.

---

### User Story 3 - Capstone: graduate by generating what you learned (Priority: P2)

In the final phase the learner connects the curriculum to the Scaffolder (Deliverable B):
they run the scaffolder on a fresh project and recognize every artifact it produces as
something they learned to build by hand. The tool stops being magic and becomes
"automation of a process I understand."

**Why this priority**: This closes the "Teach and Generate in Lockstep" loop and gives the
curriculum a satisfying, practical endpoint — but it depends on B existing, so it follows
the P1 hand-built path.

**Independent Test**: A learner who finished the hand-built track runs the scaffolder and
can annotate each generated file with which lesson taught it; nothing produced is unfamiliar.

**Acceptance Scenarios**:

1. **Given** a graduate of the hand-built track, **When** they run the scaffolder, **Then**
   every generated artifact maps to a specific earlier lesson.
2. **Given** the capstone phase, **When** completed, **Then** the learner has scaffolded at
   least one real new project end-to-end.

---

### User Story 4 - Agent-agnostic throughout (Priority: P2)

Lessons never assume a single agent. Where a concrete agent is shown (Claude Code, as the
reference), the lesson also shows the open-standard equivalent and names how it maps to
Codex/Copilot/opencode. A learner who uses a different agent is never stranded.

**Why this priority**: Reinforces Constitution Principle II at the teaching level; protects
the curriculum's longevity as the agent landscape shifts.

**Independent Test**: Pick any lesson that shows a Claude-specific path; verify it also
states the `AGENTS.md`/`SKILL.md` open-standard form and at least one other agent's mapping.

**Acceptance Scenarios**:

1. **Given** a lesson referencing a vendor-specific file, **When** reviewed, **Then** the
   open-standard equivalent is shown alongside it.

---

### Edge Cases

- What happens when a learner arrives already past the basics (e.g. already writes
  `AGENTS.md`)? → The placement mechanism must let them skip ahead without missing
  dependencies.
- How does the curriculum handle the fast-moving ecosystem (a standard or tool changes)?
  → Content must isolate version-sensitive details so they can be updated without rewriting
  lessons; evergreen principles are separated from tool specifics.
- What if a learner's chosen agent doesn't support a feature shown (e.g. no hooks)? →
  Lessons must state the portable fallback and mark the feature's support level per agent.
- How does a learner self-check understanding? → Each phase needs a check-understanding
  mechanism (quiz/exercise) with deliberately non-trivial questions.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The curriculum MUST be organized into sequential **phases**, each phase
  containing a small, consistent number of **lessons**, mirroring the structural
  organization of the "AI Engineering from Scratch" reference repo.
- **FR-002**: Each lesson MUST include at least one diagram, one worked example, and exactly
  one primary hands-on exercise that produces an inspectable artifact.
- **FR-003**: The curriculum MUST cover, at minimum, these knowledge layers: (a) the
  agent-first mindset & why it matters; (b) the `AGENTS.md` open standard; (c) the `SKILL.md`
  open standard and progressive disclosure; (d) deterministic guardrails (lifecycle hooks,
  tests, CI gates) and the verification loop; (e) spec-driven development via Spec Kit;
  (f) agent-agnostic rendering across multiple agents; (g) the 12-factor-agents principles.
- **FR-004**: The curriculum MUST be **agent-agnostic**: any vendor-specific example MUST be
  accompanied by its open-standard equivalent and at least one cross-agent mapping.
- **FR-005**: The curriculum MUST include a **placement mechanism** that routes a learner to
  an appropriate starting phase based on prior knowledge.
- **FR-006**: Each phase MUST include a **check-understanding mechanism** (quiz or graded
  exercise) whose questions are non-trivial and not answerable by guessing from option
  phrasing.
- **FR-007**: The curriculum MUST culminate in a **capstone** that connects to the
  Scaffolder (Deliverable B), where the learner generates a project and recognizes every
  artifact from prior lessons.
- **FR-008**: Every layer taught MUST correspond to something the Scaffolder can generate,
  and this mapping MUST be explicit (Constitution Principle III — Teach and Generate in
  Lockstep).
- **FR-009**: Version-sensitive tool details MUST be isolated from evergreen principles so
  the ecosystem can move without invalidating whole lessons.
- **FR-010**: The curriculum MUST state, where relevant, each feature's **support level per
  agent** (full / partial / fallback), so learners on non-reference agents are never stranded.
- **FR-011**: The repository MUST be presentable as browsable markdown (phases as folders,
  lessons as files) for v1. A static-site/`data.js` presentation like the reference repo is a
  later enhancement, not required for the Thursday milestone.

### Key Entities *(include if feature involves data)*

- **Phase**: An ordered unit of the curriculum covering one knowledge layer; has a title,
  ordering index, learning objectives, a set of Lessons, and a check-understanding artifact.
- **Lesson**: The atomic teaching unit; has a diagram, a worked example, one exercise, and a
  link to the Scaffolder artifact it corresponds to.
- **Artifact Mapping**: The explicit link between a taught concept and the Scaffolder output
  that generates it (enables the Lockstep gate).
- **Placement Result**: The output of the placement mechanism — a recommended starting phase
  plus rationale.
- **Agent Support Matrix**: Per-feature record of support level across target agents.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer who codes with agents but has never authored an `AGENTS.md` can,
  after the foundational track, produce a working agent-first scaffold for a fresh repo
  unaided.
- **SC-002**: Every lesson satisfies the structural contract (diagram + example + one
  exercise) — 100% compliance, verifiable by inspection.
- **SC-003**: Every taught layer has an explicit mapping to a Scaffolder output — 100%
  coverage (the Lockstep gate passes).
- **SC-004**: 100% of vendor-specific examples include an open-standard equivalent.
- **SC-005**: A graduate can run the Scaffolder and correctly attribute each generated
  artifact to the lesson that taught it.
- **SC-006**: Time-to-first-artifact for a new learner (first produced `AGENTS.md`) is short
  enough to complete in a single sitting of the first phase.

## Assumptions

- The "AI Engineering from Scratch" repo is the structural/pedagogical model; this curriculum
  reuses its phase/lesson organization and digestible style, not its subject matter.
- Pedagogy preference is fixed: slow, visual, ELI5, one concept at a time, interactive
  checkpoints (per the learner's established teaching-style preference).
- Claude Code is the reference agent used in concrete examples; it is not a prerequisite —
  learners on other agents follow the open-standard form.
- The Scaffolder (Deliverable B) will exist for the capstone; the foundational hand-built
  track does NOT depend on B and ships first.
- Presentation format (static site vs. markdown-only) is to be confirmed (see FR-011).
- The curriculum and scaffolder live in the **same repository** (`agent-first-engineering`),
  consistent with the dogfooding gate.
