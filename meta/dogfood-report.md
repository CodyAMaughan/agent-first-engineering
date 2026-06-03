# Dogfood Report — Scaffolder (`scaffold-agent-project`)

_2026-06-01. Ran the scaffolder end-to-end against a fresh sample project to verify it actually
produces a working, multi-agent, agent-first layer — and to surface gaps the spec couldn't._

## Setup
Sample **Project Profile** (the interview result):

| Field | Value |
|---|---|
| purpose | REST API for a personal task manager |
| stack | TypeScript · Node 20 · Express · PostgreSQL · pnpm |
| testing | Vitest · GitHub Actions |
| conventions | Prettier/ESLint · Conventional Commits · feature-branches only |
| risk tier | standard |
| target agents | Claude Code · Codex · Cursor |
| out of scope | `migrations/` |

Generated into a fresh dir, then ran `tests/validate.sh` and fired each guardrail.

## What worked ✅
- `AGENTS.md` (31 lines, command-first, no frontmatter) + `CLAUDE.md` = `@AGENTS.md` bridge.
- `.agents/skills/` (`run-tests`, `project-conventions`) mirrored to `.claude/skills/`.
- One shared hook layer (`.agent/hooks/`) + **three valid per-agent registrations**:
  `.claude/settings.json`, `.codex/hooks.json`, `.cursor/hooks.json` (Cursor with `failClosed`).
- `validate.sh`: **PASS** — AGENTS.md well-formed, every `SKILL.md` valid, every hook executable,
  capture-learnings hook fires and persists memory.
- Guardrails fire in context: `secret-scan` blocks reading `.env`; `test-gate` wired to `pnpm test`.

## Bug found & fixed 🐛
- **`git-safety` failed to detect the `main` branch** → it allowed a direct commit to `main`.
  Root cause: `git rev-parse --abbrev-ref HEAD` returns `HEAD` (not the branch name) on unborn/edge
  states. **Fix:** use `git branch --show-current` (with a rev-parse fallback). Re-tested: now blocks
  commit-on-`main`, allows feature branches, still blocks force-push. _This is the value of
  dogfooding — a guardrail that silently doesn't guard is worse than none._

## Gaps closed 🔧
- The `SKILL.md` referenced `assets/skill-templates/` that **didn't exist** (had to hand-write the two
  starter skills). → Added generic `run-tests` + `project-conventions` templates (with `{{…}}` the
  scaffolder fills). Closes tasks T009/T010.
- The risk-tier table referenced a "post-edit format/lint" hook that wasn't shipped. → Added
  `format.sh` (configurable `FORMAT_CMD`, `tool.post`, non-blocking).

## Still open (tracked in `tasks.md`)
- `adopt` mode branch (analyze existing repo + migrate `CLAUDE.md`/`.cursor/rules`).
- Spec Kit hand-off wiring; re-run manifest (T024–T031).

**Verdict:** the scaffolder produces a valid, working, three-agent agent-first layer from a profile,
and the guardrails fire. Dogfooding hardened one real bug and made the tool reproducible.
