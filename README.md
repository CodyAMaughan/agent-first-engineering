# Agent-First Engineering

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Docs site](https://img.shields.io/badge/docs-GitHub%20Pages-3553ff?style=flat-square)](https://codyamaughan.github.io/agent-first-engineering/)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](CONTRIBUTING.md)
[![Stars](https://img.shields.io/github/stars/CodyAMaughan/agent-first-engineering?style=flat-square)](https://github.com/CodyAMaughan/agent-first-engineering/stargazers)

> Stop coding with AI agents "loosey-goosey." Design your codebase so agents *succeed* —
> the way a systems engineer would.

> 📖 **Read it online → [codyamaughan.github.io/agent-first-engineering](https://codyamaughan.github.io/agent-first-engineering/)**

This repository has **two deliverables that are two views of one body of knowledge**:

- **A — The Curriculum** *(`specs/001-curriculum/`)* — a phased, visual course that takes you
  from informal "vibe coding" to designing agent-first codebases. Modeled structurally on the
  well-organized [*AI Engineering from Scratch*] approach: one concept at a time, diagrams,
  ELI5, a real artifact at the end of every lesson.
- **B — The Scaffolder** *(`specs/002-scaffolder/`)* — an **agent-agnostic**, `SKILL.md`-first
  tool that *interviews* you about a project, then generates a proper agent-first setup:
  `AGENTS.md`, a `SKILL.md` library, and lifecycle-hook guardrails — wired to work across
  **Claude Code, Codex, and Cursor** (more agents via adapters). Think *create-react-app for
  agent-first repos*, but a conversation instead of a fixed form, and it runs *inside* your
  agent. Modes: `init` (new repo), `adopt` (clean up an existing one).

**Teach and generate in lockstep:** every layer the curriculum teaches, the scaffolder
generates; every artifact the scaffolder generates, the curriculum explains.

## Principles

The project is governed by its [Constitution](.specify/memory/constitution.md). In brief:

1. **Open Standards First** — `AGENTS.md` + `SKILL.md` are the source of truth; vendor formats
   are optional adapters.
2. **Agent-Agnostic by Construction** — author once, render per-agent. Claude Code is the
   *reference*, not the requirement.
3. **Teach and Generate in Lockstep** — A and B stay in sync, by rule.
4. **Guardrails Over Vibes** — correctness is enforced by hooks/tests/CI, not prose.
5. **Minimal Context, Progressive Disclosure** — short, command-first, machine-parseable.
6. **Adopt, Don't Reinvent** — build *alongside* mature, permissive tools (esp. GitHub
   Spec Kit), don't fork them.
7. **Specs Are the Source of Truth** — spec → plan → tasks → implement.

## What we build on (all permissive, all current)

| Layer | Adopted standard / tool | License |
|---|---|---|
| Context file | [`AGENTS.md`](https://agents.md/) | Open standard |
| Reusable skills | [Agent Skills / `SKILL.md`](https://agentskills.io/) | Apache-2.0 |
| Spec workflow | [GitHub Spec Kit](https://github.com/github/spec-kit) (complement, not fork) | MIT |
| Principles | [`12-factor-agents`](https://github.com/humanlayer/12-factor-agents) | Apache-2.0 |

See [`meta/prior-art.md`](meta/prior-art.md) for the full landscape and why this project's
niche is currently unfilled.

## The Curriculum

Six phases, from vibe coding to systems engineer for agents. Full index in
[`docs/curriculum/`](docs/curriculum/index.md). Quiz yourself with `/check-understanding <phase>` (the
[`check-understanding`](.claude/skills/check-understanding/SKILL.md) skill generates an interactive
quiz from each phase's lessons).

| # | Phase | # | Phase |
|---|---|---|---|
| 1 | [Fundamentals](docs/curriculum/01-fundamentals/index.md) | 4 | [Session & Memory](docs/curriculum/04-session-and-memory/index.md) |
| 2 | [Context Engineering](docs/curriculum/02-context-engineering/index.md) ★★★ | 5 | [Spec-Driven Development](docs/curriculum/05-spec-driven-development/index.md) |
| 3 | [Verification & TDD](docs/curriculum/03-verification-and-tdd/index.md) ★★★ | 6 | [Orchestration & Harness](docs/curriculum/06-orchestration-and-harness/index.md) |

## Status

**Foundations curriculum + scaffolder built and dogfooded.** Authored using Spec Kit itself (dogfooding). Advanced tier on the [Roadmap](docs/roadmap.md).

**Start here:**
- 📋 [`meta/executive-summary.md`](meta/executive-summary.md) — the thesis & recommendations (read this first)
- 🗺️ [`docs/translation-matrix.md`](docs/translation-matrix.md) — deep Claude→Codex→Cursor feature research, by layer, with diagrams
- 🎓 [`docs/curriculum/`](docs/curriculum/index.md) — the full 6-phase curriculum (30k+ words) + quiz skill
- 📐 [`meta/curriculum-outline.md`](meta/curriculum-outline.md) — curriculum design rationale
- 🔎 [`meta/prior-art.md`](meta/prior-art.md) — landscape & why this niche is unfilled

**Specs (Spec Kit format):**
- [`.specify/memory/constitution.md`](.specify/memory/constitution.md) — governing principles
- [`specs/001-curriculum/spec.md`](specs/001-curriculum/spec.md) — Deliverable A (curriculum)
- [`specs/002-scaffolder/spec.md`](specs/002-scaffolder/spec.md) — Deliverable B (scaffolder)

## Contributing

Contributions are welcome — fix a lesson, add a diagram, propose a topic from the
[Roadmap](docs/roadmap.md), or improve the scaffolder. Start with [CONTRIBUTING.md](CONTRIBUTING.md)
and our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © 2026 CodyAMaughan. Redistributed dependencies are MIT / Apache-2.0 / BSD.

[*AI Engineering from Scratch*]: https://github.com/rohitg00/ai-engineering-from-scratch
