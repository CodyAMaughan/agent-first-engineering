# Executive Summary: Agent-First Engineering

*Prepared 2026-06-01. Scope: Claude Code, OpenAI Codex CLI, Cursor.*

## Thesis

**Stop coding with AI agents loosely. Design the repository and its surrounding harness so that *any* competent agent succeeds by construction** — then the human's job shifts from reviewing every diff to engineering the environment the agent operates in.

The timing is right because of one underappreciated 2026 development: **the major coding agents have converged on a shared set of open standards.** That means agent-first setup is now a portable, teachable discipline rather than a vendor lock-in bet.

## The problem

Informal "vibe coding" — one long chat, react to whatever the agent emits — works for toys and collapses on real systems. The agent forgets decisions, re-architects on a whim, and the human becomes the bottleneck (the verification loop, the memory, the reviewer). The fix is not a better model; it is **engineering**: persistent context, deterministic guardrails, external verification, and disciplined context management.

## Key finding: convergence on open standards

| Layer | Standard | Claude Code | Codex | Cursor | Verdict |
|---|---|---|---|---|---|
| Context file | **`AGENTS.md`** | reads `CLAUDE.md`; bridges via `@AGENTS.md` | **native** | **native** | Portable |
| Reusable skills | **`SKILL.md`** (agentskills.io) | native (`.claude/skills/`) | native (`.agents/skills/`) | native (`.agents/skills/` + `.cursor/skills/`) | **Highly portable** |
| Tool integration | **MCP** (modelcontextprotocol.io) | native | native | native | **Highly portable** |
| Guardrails | hooks (`hooks.json`, JSON-on-stdin) | 32 events | ~11 (near-port of Claude) | ~20 (renamed/granular) | ~10 events portable |
| CI / headless | print-mode + JSON + GH Action | `claude -p` | `codex exec` | `cursor-agent -p` | Portable idiom |

All three even **deprecated their older bespoke command systems and merged them into the `SKILL.md` standard** in 2026. `AGENTS.md` is stewarded by the Agentic AI Foundation (Linux Foundation), native in Codex and Cursor, with a one-line bridge for Claude.

**What stays agent-specific** (treat as edges, not core): Claude's `@`-imports, auto-memory, checkpoints/`rewind`, output styles, dynamic context injection, and its 32-event hook superset; Codex's `config.toml`/sandbox model; Cursor's `.mdc` rule-activation taxonomy and Agents Window. None of these are load-bearing for a portable setup.

## The architectural implication

> **Author once to the open standard; adapt per-agent only at the edges.**

This is the exact pattern GitHub's Spec Kit (MIT) uses to support 30+ agents from one source. Our scaffolder adopts it: a shared open-standard core (`AGENTS.md` + `.agents/skills/*/SKILL.md` + a canonical hook/MCP spec) plus a thin **adapter layer** that renders each agent's native form. Add a new agent = add an adapter, change zero content.

## The two load-bearing competencies

Across all four ecosystems (incl. OpenAI's "harness engineering" and the 12-factor-agents principles), two practices carry the most weight. If a team learns only two things:

1. **Context engineering** — treat the context window as the scarce resource: minimal steering files, `/clear` between tasks, compaction with intent, fresh sessions over long ones. (12-factor: *own your context window*, *small focused agents*.)
2. **Verification** — give the agent an external oracle (tests, builds, linters, screenshot-diffs) so it closes its own loop instead of stopping at "looks done." TDD is the strongest form.

Everything else (planning, memory files, spec-driven dev, multi-agent orchestration, harness engineering) is scaffolding around these two.

## Recommendation — what this project ships

- **A scaffolder** (`init` for new repos, `adopt` for existing ones) that generates the portable agent-first core + per-agent adapters + a deterministic guardrail layer (incl. a flagship "capture-learnings-before-compaction" memory loop). Built *alongside* Spec Kit, not replacing it.
- **A curriculum** that teaches the same competencies it generates — moving a developer from vibe coding to "systems engineer for agents," with the capstone being **harness engineering** (designing the environment, not the edit).

## How I'd frame this to a team

The bet is not on a vendor; it's on the **standards** (AGENTS.md, SKILL.md, MCP) and on **two disciplines** (context engineering, verification). Standardize the repo's agent-first core so the team is tool-portable, enforce the non-negotiables with hooks/CI rather than prose, and measure success by how little the humans have to babysit. That is a direction a team can adopt regardless of which agent each engineer prefers.

## Scope & timeline

- **Now → Thu (portfolio milestone):** Constitution + specs + this research + executive summary + curriculum outline + diagrams. A clear, defensible POV and design — implementation-ready.
- **After:** implement the scaffolder MVP (`init` → `AGENTS.md` + one `SKILL.md` + one firing guardrail), then the adapter layer, then the curriculum content.

*Full feature-level evidence in [`translation-matrix.md`](translation-matrix.md); landscape in [`prior-art.md`](prior-art.md).*
