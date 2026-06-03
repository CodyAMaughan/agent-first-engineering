# Implementation Plan: Agent-First Scaffolder (Deliverable B)

**Branch**: `002-scaffolder` | **Date**: 2026-06-01 | **Spec**: [spec.md](spec.md)

## Summary

A `SKILL.md`-first scaffolder: the interview-then-generate flow is a portable Agent Skill that runs
*inside* any agent (Claude Code / Codex / Cursor). It interviews the developer, builds a Project
Profile, then generates the portable agent-first core (`AGENTS.md` + `.agents/skills/*/SKILL.md`),
a deterministic guardrail layer (lifecycle hooks incl. the capture-learnings memory loop), and
per-agent adapter renderings — with an optional Spec Kit hand-off. No required runtime/install.

## Technical Context

- **Primary medium**: `SKILL.md` (Agent Skills open standard) + POSIX `sh` hook scripts. The
  generation logic is *procedural instructions the host agent executes*, not a compiled program.
- **Languages**: Markdown (skill + templates), POSIX shell (hook scripts), small `jq`-free helpers.
- **Runtime deps**: none required (agent-native). Optional: `git` (worktrees/safety), `uvx`+Spec Kit
  (hand-off), `node`/`python` only if the user later wants a standalone CLI wrapper.
- **Source of truth**: open standards (`AGENTS.md`, `SKILL.md`); vendor formats are adapter outputs.
- **Testing**: fixture repos under `tests/fixtures/` + a `validate.sh` that asserts generated
  `AGENTS.md`/`SKILL.md` parse, hooks are executable and *fire* against a crafted violation, and
  multi-agent renders share one core.
- **Target platforms**: any agent reading `SKILL.md`; first-class adapters = Claude Code, Codex, Cursor.
- **Project type**: agent skill + reference templates + per-agent adapters + guardrail scripts.
- **Constraints**: portable hooks bind to canonical events with graceful downgrade; memory loop is
  deterministic (no LLM call); never clobber existing files without confirmation.

## Constitution Check (GATE)

| Principle | How this plan complies |
|---|---|
| I. Open Standards First | Core outputs are `AGENTS.md` + `SKILL.md`; vendor files are adapter-only |
| II. Agent-Agnostic | One Project Profile → per-agent adapters; no hardcoded single agent |
| III. Teach & Generate Lockstep | Each generated artifact maps to a curriculum phase |
| IV. Guardrails Over Vibes | Ships hooks that *fire*; memory loop = the "reason captured" step |
| V. Minimal Context | Generated `AGENTS.md` is command-first, <200 lines; progressive disclosure |
| VI. Adopt, Don't Reinvent | Complements Spec Kit (hand-off), no fork; reuses its adapter *pattern* |
| VII. Specs Source of Truth | This plan derives from spec.md; tasks derive from this plan |

**Result: PASS** — no deviations to justify.

## Project Structure

### Documentation (this feature)
```
specs/002-scaffolder/
├── spec.md          # WHAT/why (done)
├── plan.md          # this file — HOW
└── tasks.md         # the task breakdown
```

### Source (the tool itself)
```
.claude/skills/scaffold-agent-project/
├── SKILL.md                     # interview + generation procedure (the tool)
├── references/
│   ├── interview-guide.md       # the adaptive question set + Project Profile schema
│   ├── adapter-paths.md         # per-agent output paths/formats (the registry, as data)
│   ├── event-map.md             # canonical → native hook events + fallbacks
│   └── agents-md-template.md     # the AGENTS.md skeleton
└── assets/
    ├── hooks/                    # portable hook scripts (the guardrail logic)
    │   ├── capture-learnings.sh  # pre-compact/session-end → merge into .agent/memory
    │   ├── test-gate.sh          # stop-gate: refuse to finish until tests pass
    │   ├── secret-scan.sh        # pre-tool: block reading/committing secrets
    │   └── git-safety.sh         # pre-tool: block dangerous git ops / default-branch edits
    ├── adapters/                 # per-agent registration snippets (how to wire a hook)
    │   ├── claude.md  ├── codex.md  └── cursor.md
    └── skill-templates/          # starter .agents/skills the tool drops in
tests/
├── fixtures/                    # sample repos for init/adopt
└── validate.sh                  # asserts generated artifacts parse + hooks fire
```

## Design Phases

### Phase 0 — Research (DONE)
The deep Claude/Codex/Cursor research (`docs/translation-matrix.md`) IS the research artifact: it
fixes the canonical event map, the adapter paths, and what's portable vs agent-specific.

### Phase 1 — Design (this plan)
- **Project Profile schema** (interview output): purpose, stack, conventions, risk tier, target
  agents, team, test/CI setup. → `references/interview-guide.md`.
- **Adapter registry as data** (`references/adapter-paths.md` + `event-map.md`): the per-agent paths,
  formats, and event-name mappings the generator reads — mirroring Spec Kit's registry, but as
  reference data the skill consumes rather than code.
- **Guardrail catalog**: the hook scripts + per-risk-tier selection.
- **Generation contract**: given a Profile, which files are produced and where, per target agent.

### Phase 2 — Implementation
Build the skill + references + assets, then `validate.sh` and fixtures. Order in tasks.md.

## Quality Gates & Review Checklist
- [ ] Generated `AGENTS.md` is <200 lines, command-first, no frontmatter.
- [ ] Every generated `SKILL.md` validates (name+description; body <500 lines; refs split out).
- [ ] Each generated hook **fires** against a crafted violation in a fixture (not inert).
- [ ] A multi-agent run shares one `.agents/skills/` core; only adapter outputs differ.
- [ ] Adding an agent = new adapter entry, zero content change.
- [ ] `adopt` mode migrates a pre-existing `CLAUDE.md` into `AGENTS.md` without clobbering source.
- [ ] Declining the Spec Kit hand-off still yields a complete, valid scaffold.
- [ ] The tool can scaffold *this very repo* (dogfooding gate).
