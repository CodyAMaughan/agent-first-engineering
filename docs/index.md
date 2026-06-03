# Agent-First Engineering

> Stop coding with AI agents "loosey-goosey." Design your codebase so agents *succeed* —
> the way a systems engineer would.

**Stop coding with AI agents loosely. Design the repository and its surrounding harness so that
*any* competent agent succeeds by construction** — then the human's job shifts from reviewing every
diff to engineering the environment the agent operates in. The bet isn't on a vendor; it's on the
**open standards** the major coding agents converged on in 2026 (`AGENTS.md`, `SKILL.md`, MCP) and
on **two load-bearing disciplines**: context engineering and verification. That makes agent-first
setup a portable, teachable discipline rather than a vendor lock-in bet.

This project is two views of one body of knowledge:

- **The Curriculum** — a phased, visual course that takes you from informal "vibe coding" to
  designing agent-first codebases: one concept at a time, diagrams, ELI5, a real artifact at the end
  of every lesson.
- **The Scaffolder** — an agent-agnostic, `SKILL.md`-first tool that *interviews* you about a
  project, then generates a proper agent-first setup (`AGENTS.md`, a `SKILL.md` library, and
  lifecycle-hook guardrails) wired to work across Claude Code, Codex, and Cursor.

**Teach and generate in lockstep:** every layer the curriculum teaches, the scaffolder generates;
every artifact the scaffolder generates, the curriculum explains.

## Start here

- 🎓 **[The Curriculum →](curriculum/index.md)** — the full 6-phase course, from vibe coding to
  systems engineer for agents. Start with [Phase 1 — Fundamentals](curriculum/01-fundamentals/index.md).
- 🚀 **[Roadmap →](roadmap.md)** — the Advanced Patterns tier coming next (skills/hooks deep-dives,
  security, token optimization, cloud/voice/mobile agents, and more).
- 🗺️ **[Translation Matrix →](translation-matrix.md)** — deep Claude→Codex→Cursor feature research, by layer.

## What we build on

All permissive, all current open standards:

| Layer | Adopted standard / tool |
|---|---|
| Context file | [`AGENTS.md`](https://agents.md/) |
| Reusable skills | [Agent Skills / `SKILL.md`](https://agentskills.io/) |
| Spec workflow | [GitHub Spec Kit](https://github.com/github/spec-kit) (complement, not fork) |
| Principles | [`12-factor-agents`](https://github.com/humanlayer/12-factor-agents) |

The two load-bearing competencies — **context engineering** (treat the window as the scarce
resource) and **verification** (give the agent an external oracle so it closes its own loop) — carry
the most weight across every researched source. Everything else is scaffolding around those two.
