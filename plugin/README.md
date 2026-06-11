# Agent-First Toolkit (Claude Code plugin)

The agent-first tooling built across the [Agent-First Engineering curriculum](https://codyamaughan.github.io/agent-first-engineering/),
packaged as **one installable plugin** — the capstone of [Lesson 8.3 — Plugins & marketplaces](https://codyamaughan.github.io/agent-first-engineering/curriculum/08-production-patterns/03-plugins-and-marketplaces/).

## What's in the box

| Component | Type | General-purpose? |
|---|---|---|
| `scaffold-agent-project` | skill | ✅ turns any repo agent-first (AGENTS.md, skills, guardrail hooks) |
| `author-curriculum` | skill | curriculum-specific (authoring lessons against a rubric) |
| `check-understanding` | skill | curriculum-specific (quizzes from `quiz.json`) |
| `lesson-reviewer` | subagent | adversarial, least-privilege reviewer (read + inspect, no write) |
| `git-safety`, `secret-scan` | hooks (PreToolUse) | ✅ block destructive commands / reading secrets |
| `test-gate` | hook (Stop) | ✅ refuse to finish until `TEST_CMD` passes |
| `capture-learnings` + `load-memory` | hooks (PreCompact / SessionStart) | ✅ the persisted memory loop |

## Install

```shell
# add this repo as a marketplace, then install the plugin
/plugin marketplace add CodyAMaughan/agent-first-engineering
/plugin install agent-first-toolkit@agent-first-engineering
```

Or try it locally without installing:

```shell
claude --plugin-dir ./plugin
```

## Configuration

The guardrail hooks read an optional `.agent/guardrails.conf` in *your* repo:

```sh
TEST_CMD="npm test"           # what `test-gate` runs on Stop (empty = skip)
PROTECTED_BRANCHES="main"     # branches `git-safety` blocks direct commits to ("" = none)
FORMAT_CMD=""                 # optional post-edit formatter
```

With no config the hooks degrade safely: `test-gate` skips, `git-safety` keeps its destructive-command
blocks (and protects `main`/`master` by default). Hook scripts reference themselves via
`${CLAUDE_PLUGIN_ROOT}`, so the plugin is fully self-contained.

> This plugin is generated from the repo's own `.agents/skills/`, `.claude/agents/`, and `.agent/hooks/`.
> It's a snapshot for distribution — the source of truth lives in the [repo](https://github.com/CodyAMaughan/agent-first-engineering).
