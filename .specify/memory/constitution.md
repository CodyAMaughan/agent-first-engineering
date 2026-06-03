# Agent-First Engineering Constitution

<!--
  This constitution governs BOTH deliverables of this project:
    A. The Curriculum  — a phased, visual course that teaches agent-first engineering.
    B. The Scaffolder  — an agent-agnostic tool that generates agent-first project setups.
  Every principle below applies to both unless explicitly scoped.
-->

## Core Principles

### I. Open Standards First

Build on open, multi-vendor standards, never a single product's proprietary format.
The two load-bearing standards are **`AGENTS.md`** (the Linux Foundation context-file
standard read natively by Codex, Copilot, Cursor, opencode, Gemini, Claude Code, and
others) and **`SKILL.md`** (the Agent Skills open standard at agentskills.io). Any
vendor-specific artifact (e.g. a Claude Code `.claude-plugin/`, a Cursor `.mdc` rule)
is treated as an **optional output adapter**, never the source of truth. If a capability
cannot be expressed in an open standard, that is a signal to reconsider the capability,
not to abandon the standard.

### II. Agent-Agnostic by Construction

Content is authored **once** and rendered **per-agent** through a thin adapter layer —
the pattern proven by Spec Kit's integration registry. No feature may hardcode a single
agent's paths, command syntax, or invocation separator. Claude Code is the *reference
implementation* we develop against because it is today's clearest example of agentic
engineering — but "works only in Claude" is a defect, not a milestone. Every generated
project must be usable by a teammate on Codex, Copilot, or opencode without edits to the
shared core.

### III. Teach and Generate in Lockstep

The Curriculum and the Scaffolder are two views of one body of knowledge. **Every layer
the curriculum teaches, the scaffolder generates; every artifact the scaffolder generates,
the curriculum explains.** A concept that cannot be generated is incomplete pedagogy; an
artifact that cannot be explained is unjustified scaffolding. The Scaffolder is the
Curriculum's capstone artifact, and the Curriculum is the Scaffolder's documentation.

### IV. Guardrails Over Vibes (NON-NEGOTIABLE)

Correctness is enforced by **deterministic mechanisms** — lifecycle hooks, tests, CI
gates, schema validation — not by prose pleading in a markdown file. A rule that matters
is encoded as a hook that blocks the violation; a rule stated only in prose is documentation,
not a guardrail. Generated projects ship a verification loop (a mistake is *blocked* →
the reason is *captured* → the rule is *reinforced*) before they ship features. We hold
ourselves to the same bar: this project's own repo runs the guardrails it teaches.

### V. Minimal Context, Progressive Disclosure

Agent-facing files are short, command-first, and machine-parseable. Lead with commands,
not narrative. Honor progressive disclosure: metadata is always-loaded (~100 tokens),
full instructions load on activation (<5k tokens), and deep reference material lives in
`references/`/`scripts/`/`assets/` loaded only when needed. Stale architecture prose is
worse than none — it raises inference cost and sends agents wandering. When in doubt,
cut. Curate by hand; never ship auto-generated bloat.

### VI. Adopt, Don't Reinvent

Prefer mature, permissively-licensed, broadly-adopted tools over bespoke code. This
project **complements** Spec Kit (spec→plan→tasks→implement) rather than re-implementing
it, builds on the `SKILL.md` standard rather than inventing a skill format, and cites
`12-factor-agents` as its principles substrate. New code is justified only where no
mature open option exists. "Mature" means battle-tested and vendor-or-foundation backed;
clever-but-unproven tools may be referenced as options but never made dependencies.

### VII. Specs Are the Source of Truth

Work flows spec → plan → tasks → implementation. The spec is the durable artifact; code
is its regenerable output. This project dogfoods that discipline using Spec Kit itself —
the planning artifacts in `.specify/` and `specs/` are authored before implementation and
kept current as the design evolves.

## Licensing & Adoption Constraints

- **License**: This project ships under **MIT** (or a comparably permissive license).
  Every adopted dependency must be **MIT, Apache-2.0, BSD, or equivalently permissive**.
  Copyleft (GPL) and source-available/proprietary components are excluded from anything
  redistributed, and flagged if referenced.
- **Maturity bar for dependencies**: Backed by a foundation or major vendor (e.g.
  Anthropic, GitHub/Microsoft, Linux Foundation), or demonstrably battle-tested.
  Experimental/individual-maintainer tools may be surveyed and offered as *optional*
  presets, never made core dependencies.
- **Anchor dependencies** (all permissive, all current): GitHub **Spec Kit** (MIT),
  the **Agent Skills / `SKILL.md`** standard (Apache-2.0 reference skills),
  **`AGENTS.md`** (open standard), **`12-factor-agents`** (principles, Apache-2.0).

## Development Workflow & Quality Gates

- **Spec-driven**: No implementation work begins without an approved spec under `specs/`.
  Changes to behavior update the spec first.
- **Dogfooding gate**: The scaffolder must be able to scaffold *this very repo*; the
  curriculum must teach every layer the scaffolder emits. Drift between the two is a bug.
- **Agnosticism gate**: Any feature touching generated output must be verified against at
  least two agent targets (the Claude reference + one of Codex/Copilot/opencode) before
  it is considered done.
- **Guardrail gate**: Generated guardrails (hooks/tests/CI) must actually *fire* in a
  test fixture, not merely exist as files.

## Governance

This constitution supersedes ad-hoc preferences and "how we did it last time." Amendments
require: (1) a written rationale, (2) an update to any specs/curriculum the change affects,
and (3) a version bump below. Every plan and review must verify compliance with these
principles; any deviation must be justified in writing in the relevant spec's Complexity
or Assumptions section. Simplicity and portability win ties.

**Version**: 1.0.0 | **Ratified**: 2026-05-30 | **Last Amended**: 2026-05-30
