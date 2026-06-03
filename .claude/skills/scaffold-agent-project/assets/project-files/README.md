<!-- Template — the scaffolder writes this as the project `README.md`, filled from the Profile. -->
# {{NAME}}

{{PURPOSE}}

## Stack
{{STACK}}

## Getting started
```bash
{{INSTALL_CMD}}
{{DEV_CMD}}
```

## Commands
| | |
|---|---|
| Test | `{{TEST_CMD}}` |
| Lint | `{{LINT_CMD}}` |
| Build | `{{BUILD_CMD}}` |

## This is an agent-first repo
It's set up so AI coding agents (Claude Code{{OTHER_AGENTS}}) succeed by construction:
- **`AGENTS.md`** — the command-first context every agent reads (Claude via the `CLAUDE.md` bridge).
- **`.agents/skills/`** — reusable `SKILL.md` capabilities (mirrored to `.claude/skills/`).
- **`.agent/hooks/`** — deterministic guardrails (secret-scan, git-safety, test-gate, a capture-learnings
  memory loop). See `.claude/settings.json` for how they're wired.

Generated with the [agent-first-engineering](https://github.com/CodyAMaughan/agent-first-engineering) scaffolder.
