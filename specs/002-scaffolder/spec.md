# Feature Specification: Agent-First Scaffolder (Deliverable B)

**Feature Branch**: `002-scaffolder`

**Created**: 2026-05-30

**Status**: Draft

**Input**: User description: "An agent-agnostic tool that, when starting a new project,
interviews the developer about the project until it understands it, then generates a
proper agent-first setup: AGENTS.md, a SKILL.md library, lifecycle-hook guardrails, and
the agent-adapter wiring so the same content works across Claude Code, Codex, Copilot,
opencode, etc. Think 'create-react-app for agent-first repos,' but more open-ended — an
interview, not a fixed questionnaire. It complements GitHub Spec Kit (offering to add the
spec→plan→tasks loop) rather than replacing it. MIT-licensed, built on open standards."

## User Scenarios & Testing *(mandatory)*

<!--
  The interview-then-generate skill is the MVP. Multi-agent adapters and the Spec Kit
  hand-off are independently shippable layers on top.
-->

### User Story 1 - Interview-driven scaffold of a fresh project (Priority: P1) 🎯 MVP

A developer starting a new project invokes the scaffolder. Instead of a rigid form, it
**interviews** them — asking about the project's purpose, stack, conventions, risk areas,
and team — adapting follow-up questions to their answers until it has enough understanding.
It then generates a complete agent-first setup: a curated `AGENTS.md`, a starter `SKILL.md`
library, and guardrail hooks. The developer ends with a repo that is "agent-ready" on day one.

**Why this priority**: This is the core promise — replace "loosey-goosey" project starts
with a designed setup, via a conversation rather than blank-page paralysis.

**Independent Test**: Point the scaffolder at an empty directory, answer its interview for a
described project, and verify it emits a valid `AGENTS.md`, at least one valid `SKILL.md`,
and at least one working guardrail hook — all consistent with the answers given.

**Acceptance Scenarios**:

1. **Given** an empty project directory, **When** the developer completes the interview,
   **Then** the tool generates a root `AGENTS.md` that is command-first, minimal, and
   reflects the stated stack/conventions.
2. **Given** the same run, **When** generation completes, **Then** at least one `SKILL.md`
   is produced that validates against the Agent Skills standard (valid frontmatter:
   `name`, `description`).
3. **Given** the same run, **When** generation completes, **Then** at least one lifecycle
   guardrail hook is produced that **actually fires** (blocks the violation) in a test
   fixture, not merely a file that exists.
4. **Given** ambiguous or incomplete answers, **When** the interview proceeds, **Then** the
   tool asks targeted follow-ups rather than guessing silently, and records unresolved items.

---

### User Story 2 - Agent-agnostic output via an adapter layer (Priority: P1)

The same generated content is rendered for whichever agent(s) the developer targets. The
**source of truth is the open standard** (`AGENTS.md`, `SKILL.md`); a thin adapter layer
emits any vendor-specific form needed (e.g. Claude Code skill directories) so a teammate on
Codex, Copilot, or opencode gets a working setup without editing the shared core.

**Why this priority**: Constitution Principle II. The whole point of the user's request is
"agnostic to Claude" — Claude is the reference, not the requirement. Without this, the tool
is just another Claude-only kit.

**Independent Test**: Run the scaffolder selecting two different agent targets; verify the
shared `AGENTS.md`/`SKILL.md` core is identical and only the per-agent adapter outputs differ,
and that each target's output is valid for that agent.

**Acceptance Scenarios**:

1. **Given** a multi-agent target selection, **When** generation runs, **Then** one shared
   open-standard core is produced plus correct per-agent adapter artifacts.
2. **Given** any single agent target, **When** generation runs, **Then** no other agent's
   files are required for that target to work.
3. **Given** a new agent adapter is added, **When** the same project is regenerated, **Then**
   no change to authored content is needed — only the adapter renders new output.

---

### User Story 3 - Portable guardrail & verification-loop generation (Priority: P2)

The scaffolder generates a **guardrail layer**, not just context files: lifecycle hooks
(e.g. block bad git operations, enforce tests-before-merge, secret scanning), portable
across agents, plus the verification-loop wiring (a blocked mistake → reason captured →
rule reinforced). Guardrails are chosen based on the interview (risk tier, stack).

Critically, guardrails are authored **once** as portable hook definitions and rendered into
each target agent's native hook config via the same adapter layer used for skills/commands.
The hook *logic* lives in agent-neutral shell scripts that all agents call; only the
*registration* differs per agent. Hooks bind to **canonical event names** (e.g.
`session-start`, `pre-tool`, `pre-compact`, `session-end`) that each adapter maps to the
agent's native names (Claude `PreToolUse`/`PreCompact`, Cursor `preCompact`, Codex's
ported equivalents, etc.). Where a target lacks an event, the adapter binds to the closest
available event and records the downgrade rather than silently dropping the guardrail.

**Why this priority**: Constitution Principle IV. Deterministic guardrails are what separate
"3x productivity" setups from "negative ROI" setups — and hooks are now a near-universal,
converging feature across Claude Code, Codex, Cursor, Copilot, Gemini CLI, and opencode, so
a portable guardrail layer is both feasible and high-leverage. Layers on top of core context
generation.

**Independent Test**: For a project that declared a given risk profile, verify the generated
hooks match that profile, render correctly into at least two agents' native config formats,
and that each generated hook fires correctly against a crafted violation in a fixture.

**Acceptance Scenarios**:

1. **Given** a stated risk tier, **When** guardrails are generated, **Then** the hook set
   matches the tier (higher risk → stricter gates).
2. **Given** a generated hook, **When** a violating action is attempted in a fixture, **Then**
   the hook blocks it and emits a captured reason.
3. **Given** two different agent targets, **When** the same portable hook is rendered, **Then**
   both native configs invoke the **same** shared shell script and bind to the correct native
   event name for each agent.
4. **Given** a target agent that lacks a requested event (e.g. no `PreCompact`), **When** the
   hook is rendered, **Then** it binds to the nearest available event and the downgrade is
   recorded, never silently dropped.

---

### User Story 3b - "Capture learnings before compaction" memory loop (Priority: P2)

The scaffolder ships a flagship built-in guardrail: a **self-improving memory loop**. A
`pre-compact` (falling back to `session-end`) hook runs a deterministic, LLM-free script that
captures the session's durable learnings — decisions made, corrections received, gotchas
discovered — and **merges** them into a small markdown memory wiki (e.g. `.agent/memory/*.md`,
organized by semantic path so each file is a living document, not an append-only log). A
`session-start`/`prompt-submit` hook re-injects the relevant memory back into context. This
makes the repository "remember" across context-window compactions and sessions — the concrete
mechanism behind the constitution's "reason captured → rule reinforced" verification loop.

**Why this priority**: It is the single most compelling demonstration of why agent-first setup
beats vibe coding, and it is the user's own motivating example. It is portable because the
underlying lifecycle events (`PreCompact` on Claude/Codex/Cursor; `SessionEnd`/`Stop`
everywhere else) are broadly available. It is additive on top of the guardrail layer (US3).

**Independent Test**: Run a fixture session that records a "learning," trigger the compaction
(or session-end) event, and verify the learning is merged into the memory wiki; then start a
new session and verify the learning is re-injected into context.

**Acceptance Scenarios**:

1. **Given** the memory loop is installed, **When** a compaction/session-end event fires, **Then**
   a deterministic script merges the session's learnings into the markdown memory wiki without
   calling an LLM.
2. **Given** existing memory files, **When** a new session starts, **Then** relevant memory is
   re-injected into the agent's context.
3. **Given** an agent without a native `PreCompact` event, **When** the loop is installed, **Then**
   it binds to `SessionEnd`/`Stop` and still captures learnings (with the downgrade recorded).
4. **Given** a memory file that would grow without bound, **When** new learnings arrive, **Then**
   they are merged by semantic path (a living document), not blindly appended.

---

### User Story 4 - Spec Kit hand-off (complement, not replace) (Priority: P2)

After scaffolding the agent-first layer, the tool offers to add Spec Kit's spec→plan→tasks→
implement loop (e.g. by invoking `specify init`), wiring the two together so the developer
gets both the guardrail scaffold and the spec-driven workflow in one sitting. Declining
leaves a fully working scaffold; the two tools stay decoupled.

**Why this priority**: Constitution Principle VI (Adopt, Don't Reinvent) and the chosen
"build alongside Spec Kit" architecture. It's high value but strictly additive.

**Independent Test**: Complete a scaffold, accept the Spec Kit offer, and verify a working
`.specify/` setup coexists with the generated agent-first layer; then repeat declining the
offer and verify the scaffold is still complete and valid.

**Acceptance Scenarios**:

1. **Given** a completed scaffold, **When** the developer accepts the Spec Kit offer, **Then**
   a valid Spec Kit setup is added without conflicting with generated files.
2. **Given** a completed scaffold, **When** the developer declines, **Then** the agent-first
   scaffold is complete and self-sufficient.

---

### User Story 5 - Re-run / update an existing project (Priority: P3)

Run on an existing scaffolded repo, the tool detects prior output, compares it to the current
state, updates what changed, flags stale items, and preserves the developer's manual edits
(manifest/checksum-aware, following Spec Kit's update model).

**Why this priority**: Real projects evolve; non-destructive updates make the tool a living
companion rather than a one-shot generator. Lower priority than first-run generation.

**Independent Test**: Scaffold a project, hand-edit a generated file, re-run the tool, and
verify the manual edit is preserved while genuinely stale items are flagged/updated.

**Acceptance Scenarios**:

1. **Given** a previously scaffolded repo with a hand-edited generated file, **When** the
   tool re-runs, **Then** the manual edit is preserved (not silently overwritten).
2. **Given** a re-run, **When** a generated artifact is now stale, **Then** it is flagged for
   review rather than blindly replaced.

---

### User Story 6 - Adopt mode: bring an existing un-scaffolded repo up to standard (Priority: P2)

Run on an existing repository the tool has **never touched** — a "loosey-goosey" project with
no `AGENTS.md`, ad-hoc or missing skills, and no guardrails — the tool **analyzes** the repo
(languages, frameworks, test setup, existing `CLAUDE.md`/`.cursor` rules, CI), uses what it
learns to shorten the interview (confirming inferences rather than asking from scratch), and
then brings the repo up to the agent-first standard: a curated `AGENTS.md`, a starter skill
library, and a risk-appropriate guardrail layer — **without clobbering** existing config it
should preserve or migrate. This is the "like Claude Code's `/init`, but more robust and
broader" mode.

**Why this priority**: The user's projects (and most real-world repos) already exist; "clean up
what I have" is as important as "start fresh." It reuses the interview + generation machinery
of US1 with an analysis front-end, so it is high-value but additive.

**Independent Test**: Point the tool at an existing repo with a known stack and a pre-existing
`CLAUDE.md`. Verify it infers the stack correctly, confirms inferences with the developer,
produces a valid agent-first layer, and migrates/preserves the existing config rather than
overwriting it.

**Acceptance Scenarios**:

1. **Given** an existing repo with no agent-first setup, **When** adopt mode runs, **Then** the
   tool infers stack/conventions from the codebase and confirms them instead of asking every
   question cold.
2. **Given** a repo with a pre-existing `CLAUDE.md` or `.cursor/rules`, **When** adopt mode
   runs, **Then** that content is migrated/merged into the open-standard `AGENTS.md` rather
   than discarded or duplicated.
3. **Given** adopt mode completes, **Then** the repo has a valid agent-first layer and no
   pre-existing source or config file was destroyed without explicit confirmation.

---

### Edge Cases

- The interview is invoked in a **non-interactive** context (CI/headless). → The tool must
  support a non-interactive mode driven by a config/answers file, with sensible defaults.
- The developer targets an agent the tool has **no adapter** for. → Fall back to a generic
  open-standard output (`.agents/`-style) and clearly state the limitation, never fail hard.
- The target directory is **not empty** / already a git repo. → Detect and merge safely with
  confirmation; never clobber existing files without consent.
- The developer **abandons the interview** partway. → Partial state is saved/resumable; no
  half-written project is left in a broken state.
- A generated `SKILL.md` would exceed progressive-disclosure size budgets. → The tool splits
  reference material into `references/` rather than emitting a bloated skill body.
- The interview produces **conflicting** answers (e.g. "no external deps" + "uses Postgres").
  → The tool surfaces the conflict and asks the developer to resolve it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tool MUST run an **adaptive interview** (not a fixed questionnaire) that
  asks follow-up questions based on prior answers until it has sufficient understanding to
  generate the setup, and MUST record any unresolved/ambiguous items.
- **FR-002**: The tool MUST generate a root **`AGENTS.md`** that is command-first, minimal,
  human-curated in tone, and consistent with the interview answers.
- **FR-003**: The tool MUST generate a starter **`SKILL.md` library** where every skill
  validates against the Agent Skills open standard (required frontmatter `name` +
  `description`; progressive-disclosure structure; oversized reference material split out).
- **FR-004**: The tool MUST generate a **guardrail layer** of lifecycle hooks (at minimum
  covering git-safety, test-before-merge, and secret scanning) selected by the interview's
  risk profile, and each generated hook MUST be demonstrably able to fire.
- **FR-005**: The tool MUST keep the **open standard as the single source of truth** and emit
  any vendor-specific artifacts through a **per-agent adapter layer** (modeled on Spec Kit's
  integration registry).
- **FR-006**: The tool MUST support **multiple agent targets** in one run, producing one
  shared core plus correct per-agent outputs; each target MUST work standalone.
- **FR-007**: Adding a **new agent adapter** MUST require no change to authored content — only
  a new adapter that renders existing content.
- **FR-008**: For an unsupported agent target, the tool MUST fall back to a **generic
  open-standard output** and state the limitation rather than failing.
- **FR-009**: The tool MUST offer to **hand off to Spec Kit** (invoke its init flow) after
  scaffolding, and MUST leave a complete, valid scaffold whether the offer is accepted or
  declined. The two tools MUST remain decoupled (no fork of Spec Kit).
- **FR-010**: The tool MUST support **non-interactive mode** driven by an answers/config file
  for CI/headless use, with documented defaults.
- **FR-011**: On **re-run**, the tool MUST detect prior output, update changed items, flag
  stale ones, and **preserve manual edits** (manifest/checksum-aware).
- **FR-012**: The tool MUST **never clobber** existing files without explicit confirmation,
  and MUST handle existing/non-empty/already-git directories safely.
- **FR-013**: The tool MUST validate its own generated artifacts (`AGENTS.md`, `SKILL.md`,
  hooks) before declaring success.
- **FR-014**: The interview-then-generate capability MUST itself be expressible as a portable
  **`SKILL.md`** so it runs across agents (Constitution Principles II & III).
- **FR-015**: The tool and all redistributed dependencies MUST be **permissively licensed**
  (MIT/Apache/BSD); [NEEDS CLARIFICATION: primary implementation language/runtime — Spec Kit
  is Python/uvx; an `npx`/Node CLI is more familiar to JS/TS devs. Decide at plan time.]
- **FR-016**: The tool MUST expose its generation as discrete, inspectable steps so a learner
  from the Curriculum (Deliverable A) can map each generated artifact to a lesson.
- **FR-017**: Guardrails MUST be authored once in a **portable hook definition** (binding to
  canonical event names) and rendered into each target agent's native hook configuration via
  the adapter layer. The hook *logic* MUST live in agent-neutral scripts shared across agents;
  only the *registration* may differ per agent.
- **FR-018**: The adapter layer MUST map canonical events (at minimum: `session-start`,
  `prompt-submit`, `pre-tool`, `post-tool`, `pre-compact`, `session-end`) to each supported
  agent's native event names. Where a target lacks an event, it MUST bind to the nearest
  available event and **record the downgrade** (never silently drop a guardrail).
- **FR-019**: The tool MUST offer a built-in **"capture learnings" memory loop** guardrail: a
  deterministic, LLM-free `pre-compact`/`session-end` hook that **merges** session learnings
  into a markdown memory store (organized by semantic path, merged-not-appended), plus a
  `session-start`/`prompt-submit` hook that re-injects relevant memory into context.
- **FR-020**: The tool MUST support three operating modes: **`init`** (scaffold a new repo),
  **`adopt`** (analyze and upgrade an existing, previously-untouched repo), and **re-run/update**
  (FR-011, on a repo it previously scaffolded).
- **FR-021**: In `adopt` mode, the tool MUST infer stack/conventions/test/CI setup from the
  existing codebase to shorten the interview (confirm inferences rather than ask cold), and MUST
  **migrate/merge** any pre-existing agent config (`CLAUDE.md`, `.cursor/rules`, etc.) into the
  open-standard `AGENTS.md` rather than discarding or duplicating it.
- **FR-022**: The tool MUST treat any heavyweight memory backend (external DB / LLM-distillation
  "dream phase") as an **optional preset**, never a core dependency; the default memory loop is
  the dependency-free markdown store (Constitution Principle VI).

### Key Entities *(include if feature involves data)*

- **Interview Session**: The adaptive Q&A state — questions asked, answers, follow-ups,
  unresolved items, and the resulting project understanding; resumable.
- **Project Profile**: The structured understanding derived from the interview (purpose,
  stack, conventions, risk tier, team, target agents) — the input to generation.
- **Agent Adapter**: A unit that maps shared open-standard content to one agent's paths,
  format, and invocation syntax; the registry of these makes the tool agnostic.
- **Generated Artifact**: Any emitted file (`AGENTS.md`, a `SKILL.md`, a hook, an adapter
  output) plus its manifest entry (checksum, source, edit-state) for safe re-runs.
- **Guardrail / Hook**: A deterministic lifecycle check tied to a risk tier, with the event
  it binds to and the violation it blocks.
- **Generation Manifest**: The audit record enabling non-destructive updates (per-file
  checksums, provenance, user-modified flags).
- **Portable Hook Definition**: An agent-neutral declaration of a guardrail — canonical event,
  matcher, and the shared script to run — that the adapter layer renders into each agent's
  native hook config.
- **Canonical Event Map**: The per-agent mapping from canonical event names to native event
  names, including each agent's fallback when an event is unsupported.
- **Memory Store**: The markdown memory wiki (`.agent/memory/*.md`) written by the
  capture-learnings loop, organized by semantic path and merged-not-appended.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From an empty directory, a developer completes the interview and obtains a
  valid agent-ready scaffold (`AGENTS.md` + ≥1 `SKILL.md` + ≥1 firing guardrail) in a single
  sitting.
- **SC-002**: 100% of generated `SKILL.md` files validate against the Agent Skills standard.
- **SC-003**: 100% of generated guardrail hooks fire correctly against a crafted violation in
  a fixture (no inert "decoration" hooks).
- **SC-004**: For multi-agent runs, the shared open-standard core is byte-identical across
  targets; only adapter outputs differ; each target works standalone.
- **SC-005**: Adding a new agent adapter requires zero edits to authored content.
- **SC-006**: On re-run with a hand-edited generated file, the manual edit is preserved 100%
  of the time.
- **SC-007**: The tool can scaffold **this very repository** (dogfooding gate), and every
  artifact it emits maps to a Curriculum lesson (Lockstep gate).
- **SC-008**: Declining the Spec Kit hand-off still yields a complete, valid scaffold 100% of
  the time.
- **SC-009**: A single portable hook definition renders into ≥2 agents' native hook configs,
  both invoking the same shared script; 100% of rendered hooks fire in a fixture.
- **SC-010**: The capture-learnings loop merges a session learning into the markdown store on a
  compaction/session-end event and re-injects it on the next session start — verified end-to-end
  in a fixture, with no LLM call in the hook path.
- **SC-011**: In `adopt` mode on a repo with a pre-existing `CLAUDE.md`, the tool migrates that
  content into `AGENTS.md` and destroys no pre-existing file without confirmation (100%).

## Assumptions

- The architecture is **"build alongside Spec Kit"** (confirmed): adopt Spec Kit's adapter
  *pattern*, keep a separate lean codebase, offer Spec Kit as an optional hand-off — do not
  fork it.
- Open standards (`AGENTS.md`, `SKILL.md`) are the source of truth; vendor formats are adapter
  outputs only.
- Claude Code is the reference target for development and the first-class adapter; Codex,
  Copilot, and opencode are the initial additional adapters to prove agnosticism (final
  initial set to be confirmed at plan time).
- The interview UX is delivered first as a portable `SKILL.md` (works inside any agent), with
  a standalone CLI as a possible later front-end; the implementation language/runtime is open
  (see FR-015).
- The scaffolder and curriculum share **one repository** and are kept in lockstep per the
  Constitution.
- Spec Kit remains MIT and exposes a stable `specify init` interface for the hand-off.
- Hooks are a near-universal, converging agent feature (Claude Code, Codex, Cursor, Copilot,
  Gemini CLI, opencode all ship them; the shell-cmd + JSON-on-stdin model is becoming a de-facto
  standard). A portable guardrail layer is therefore feasible across the major agents, with
  graceful degradation where an event is missing.
- `PreCompact` exists natively on Claude Code, Codex, and Cursor; other agents fall back to
  `SessionEnd`/`Stop`. The capture-learnings loop is designed against this reality.
- No mature, broadly-adopted cross-agent hook-registration tool exists yet (`weykon/agent-hooks`
  is MIT but experimental); we therefore build a thin adapter ourselves rather than depend on
  one, while keeping the option to adopt a mature one later.
