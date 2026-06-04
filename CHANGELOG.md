# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/). Update the `Unreleased` section when you make a
notable change — this is release-scoped, not a per-commit log.

## [Unreleased]

## [0.1.0] - 2026-06-03

### Added
- **Foundations curriculum** — 6 phases (Fundamentals, Context Engineering, Verification & TDD,
  Session & Memory, Spec-Driven Development, Orchestration & Harness), published as a MkDocs Material
  site on GitHub Pages, with per-lesson diagrams, footnote citations, and a `quiz.json`.
- **Agent-first scaffolder** — a `SKILL.md`-first tool (`init` / `adopt`) that generates `AGENTS.md`,
  a `.agents/skills/` library, deterministic guardrail hooks, and per-agent adapters.
- **`check-understanding` skill** — interactive quizzes driven by each phase's `quiz.json`.
- **Reference material** — a Claude Code → Codex → Cursor translation matrix and an Advanced Patterns
  roadmap.
- **Project standards** — MIT license, contributing guide, code of conduct, issue/PR templates, and
  CI that builds the site and validates quizzes.

[Unreleased]: https://github.com/CodyAMaughan/agent-first-engineering/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/CodyAMaughan/agent-first-engineering/releases/tag/v0.1.0
