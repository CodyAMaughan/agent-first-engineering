---
name: scaffold-agent-project
version: 0.1.0
description: Interview the developer about a project, then generate a complete agent-first setup — a command-first AGENTS.md, a portable .agents/skills/ library, and deterministic guardrail hooks (incl. a capture-learnings memory loop) — rendered for Claude Code, Codex, and Cursor. Two modes — init (new repo) and adopt (upgrade an existing one). Trigger with "scaffold an agent-first project", "set up this repo for agents", "/scaffold-agent-project", or "make my repo agent-ready".
---

# Scaffold Agent-First Project

Turn a repo into an **agent-first** repo: the open-standard core (`AGENTS.md` + `.agents/skills/`),
a deterministic guardrail layer, and per-agent adapters — produced from a short interview. This skill
IS the tool (it runs inside any agent; no install). It is the capstone artifact of the
[curriculum](../../../docs/curriculum/index.md): every file it emits maps to a phase that explains it.

## Operating principle

> **Author once to the open standard; adapt per-agent at the edges.** The source of truth is
> `AGENTS.md` + `SKILL.md`; vendor files (`.claude/`, `.codex/`, `.cursor/`) are adapter outputs.
> Hooks bind to **canonical events** and degrade gracefully where an agent lacks one.

## Reference data (read these as you go)
- `references/interview-guide.md` — the adaptive questions + **Project Profile** schema
- `references/adapter-paths.md` — where each agent's files go + format
- `references/event-map.md` — canonical → native hook events + fallbacks
- `references/agents-md-template.md` — the `AGENTS.md` skeleton
- `assets/hooks/*` — the portable guardrail scripts · `assets/adapters/*` — per-agent registration
- `assets/skill-templates/*` & `assets/agent-templates/*` — starter skills & subagents

## Procedure

### Step 0 — Detect mode
- Target dir **empty / fresh** → **`init`**.
- Target dir is an **existing repo** with code → confirm **`adopt`** (don't clobber). Read the repo
  first (languages, test runner, CI, any `CLAUDE.md`/`.cursor/rules`/`AGENTS.md`) to pre-fill answers.

### Step 1 — Interview
Follow `references/interview-guide.md`. Ask **adaptively** — one topic at a time, follow up on vague
answers, and in `adopt` mode *confirm inferences* instead of asking cold. Build a **Project Profile**:
purpose · stack · conventions · risk tier · target agents · team · test/CI commands. Record any
**unresolved** items and **surface conflicts** (e.g. "no external deps" + "uses Postgres") for the
user to resolve. Do not guess silently.

### Step 2 — Confirm targets
Confirm which agents to render for (default: **Claude Code + Codex + Cursor**). Unknown agent →
generic `.agents/` output + tell the user it's a fallback.

### Step 3 — Generate the open-standard core
1. **`AGENTS.md`** at repo root from `references/agents-md-template.md`, filled from the Profile —
   command-first, <200 lines, **no frontmatter**, only what the agent can't infer.
2. **`CLAUDE.md`** = a thin bridge: a single `@AGENTS.md` line (+ Claude-only notes if any).
3. **Starter skills** into `.agents/skills/` from `assets/skill-templates/` (e.g. `run-tests`,
   `project-conventions`), customized to the stack; **mirror** to `.claude/skills/` for Claude.
4. **Project files** from `assets/project-files/`, filled from the Profile: `.gitignore`,
   `.env.example` (list the env vars/secrets this project needs), and a project `README.md`. In
   `adopt` mode, never overwrite an existing `README.md`/`.gitignore` without confirmation (merge instead).
5. **Starter subagent(s)** from `assets/agent-templates/` (e.g. `code-reviewer`) into each target's
   native location — Claude Code `.claude/agents/*.md` — **least-privilege** (read + inspect, no
   write/edit). Subagents are per-tool (see `references/adapter-paths.md`): emit project files only for
   agents that support them, and name the equivalent (Cursor custom agents/modes, OpenAI Agents SDK)
   for the others.

### Step 4 — Generate the guardrail layer (by risk tier)
Pick a hook set from the Profile's risk tier:

| Risk tier | Hooks installed |
|---|---|
| low | `git-safety` + post-edit `format` |
| standard | + `secret-scan` + `test-gate` (Stop until tests pass) |
| high | + branch protection + stricter command denylist |

**Present the selected hook set as a short checklist and get a quick confirm** before writing
(e.g. "standard tier → `secret-scan`, `git-safety`, `test-gate`, `format`, + the capture-learnings
memory loop — install these?"). Then for each hook: copy the script from `assets/hooks/`, then **render its registration per target agent**
using `references/event-map.md` + `references/adapter-paths.md` + `assets/adapters/<agent>.md`. The
script is shared; only registration differs. If a target lacks the event, bind the nearest one and
**record the downgrade** in the run summary. ⚠️ Cursor fails *open* by default — set `failClosed:true`
on security hooks.

### Step 5 — Install the capture-learnings memory loop (flagship)
Install `assets/hooks/capture-learnings.sh` on canonical `pre-compact` (fallback `session-end`) and a
session-start memory re-injection. It deterministically merges learnings into `.agent/memory/*.md`
(by semantic path, merged-not-appended) — **no LLM call**. This is the "reason captured" step of the
verification loop (Phase 2 / Phase 3).

### Step 6 — `adopt` only: migrate existing config
Merge any pre-existing `CLAUDE.md` / `.cursor/rules` content into `AGENTS.md` (dedupe, keep the
imperative bits). Leave the originals or replace with bridges — **never delete source files without
explicit confirmation**.

### Step 7 — Offer the Spec Kit hand-off
Offer to add the spec→plan→tasks→implement loop via `uvx --from git+https://github.com/github/spec-kit.git specify init --here --ai claude`
(or the user's agent). Accept → run it; decline → the scaffold is already complete and valid. Stay
decoupled (never fork Spec Kit).

### Step 8 — Validate & summarize
Run `tests/validate.sh` if present (assert `AGENTS.md` parses & is <200 lines; each `SKILL.md` has
`name`+`description`; each hook is executable and fires in a fixture). Then print a **summary** that
lists every generated file, the per-agent renderings, any recorded downgrades, and a **lockstep map**
(artifact → curriculum phase). Offer next steps.

## Safety rules
- **Never overwrite** an existing file without showing a diff and getting confirmation.
- Write a **generation manifest** (`.agent/.scaffold-manifest.json`: per-file checksum + provenance)
  so re-runs update changed files, flag stale ones, and **preserve manual edits**.
- The portable core (`AGENTS.md`, `.agents/skills/`) must be byte-identical across agent targets;
  only adapter outputs differ.
- Default memory loop is dependency-free markdown — heavyweight backends (DB/LLM "dream phase") are
  opt-in only.

## Lockstep map (what this generates ↔ what the curriculum teaches)
| Generated artifact | Phase |
|---|---|
| the interview UX itself | 1 — Fundamentals |
| capture-learnings memory loop | 2 — Context Engineering |
| `test-gate` / Stop-gate hooks | 3 — Verification & TDD |
| `AGENTS.md` + `.agents/skills/` | 4 — Session & Memory |
| Spec Kit hand-off | 5 — Spec-Driven Development |
| guardrail layer + adapters + CI | 6 — Orchestration & Harness |
