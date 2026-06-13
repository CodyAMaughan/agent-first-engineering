#!/bin/sh
# build-plugin.sh — regenerate the Claude Code plugin in plugin/ from the CANONICAL sources, so the
# distributed plugin can never drift from the repo's real skills/hooks/agents. The plugin/ tree is
# git-ignored and generated; the source of truth lives in .agents/skills/, .agent/hooks/, and
# .claude/agents/. Re-run this whenever those change. Deterministic, POSIX sh, deps: cp/find/mkdir.
#
# Usage: sh scripts/build-plugin.sh   (run from the repo root)

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

SKILLS_SRC=".agents/skills"           # canonical, open-standard skill library
HOOKS_SRC=".agent/hooks"              # canonical guardrail hooks
AGENTS_SRC=".claude/agents"           # subagent definitions (Claude-specific)
OUT="plugin"

# The skills we ship in the plugin (general-purpose + curriculum tooling). quality-loop/feature-lifecycle
# are repo-internal orchestration skills and are intentionally NOT distributed.
PLUGIN_SKILLS="scaffold-agent-project author-curriculum check-understanding"
# The reviewer subagents we ship (both are the documented adversarial reviewers in AGENTS.md).
PLUGIN_AGENTS="code-reviewer lesson-reviewer"
# The guardrail hooks we ship (the registered set, incl. the capture-learnings memory loop).
PLUGIN_HOOKS="git-safety secret-scan test-gate capture-learnings load-memory"

echo "Building plugin/ from canonical sources..."

# --- clean slate so a removed source can never linger in the output -------------------------------
rm -rf "$OUT"
mkdir -p "$OUT/skills" "$OUT/hooks" "$OUT/agents" "$OUT/.claude-plugin"

# --- skills: copy each canonical skill tree verbatim ----------------------------------------------
for s in $PLUGIN_SKILLS; do
  [ -d "$SKILLS_SRC/$s" ] || { echo "  ERROR: missing canonical skill $SKILLS_SRC/$s" >&2; exit 1; }
  cp -R "$SKILLS_SRC/$s" "$OUT/skills/$s"
  echo "  skill   $s"
done

# --- hooks: copy each canonical hook, keep it executable ------------------------------------------
for h in $PLUGIN_HOOKS; do
  [ -f "$HOOKS_SRC/$h.sh" ] || { echo "  ERROR: missing canonical hook $HOOKS_SRC/$h.sh" >&2; exit 1; }
  cp "$HOOKS_SRC/$h.sh" "$OUT/hooks/$h.sh"
  chmod +x "$OUT/hooks/$h.sh"
  echo "  hook    $h.sh"
done

# --- agents: copy each reviewer subagent ----------------------------------------------------------
for a in $PLUGIN_AGENTS; do
  [ -f "$AGENTS_SRC/$a.md" ] || { echo "  ERROR: missing canonical agent $AGENTS_SRC/$a.md" >&2; exit 1; }
  cp "$AGENTS_SRC/$a.md" "$OUT/agents/$a.md"
  echo "  agent   $a.md"
done

# --- plugin.json ----------------------------------------------------------------------------------
cat > "$OUT/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "agent-first-toolkit",
  "displayName": "Agent-First Toolkit",
  "version": "1.0.0",
  "description": "The agent-first toolkit from the Agent-First Engineering curriculum: skills (scaffold a repo agent-first; author and quiz curriculum), adversarial least-privilege reviewer subagents, and deterministic guardrail hooks — git-safety, secret-scan, test-gate, plus the capture-learnings memory loop.",
  "author": {
    "name": "Cody A. Maughan",
    "url": "https://github.com/CodyAMaughan"
  },
  "homepage": "https://codyamaughan.github.io/agent-first-engineering/",
  "repository": "https://github.com/CodyAMaughan/agent-first-engineering",
  "license": "MIT",
  "keywords": ["agents", "agent-first", "skills", "hooks", "subagents", "scaffold", "guardrails"]
}
JSON
echo "  meta    .claude-plugin/plugin.json"

# --- hooks.json (wires every shipped hook to its event via CLAUDE_PLUGIN_ROOT) --------------------
cat > "$OUT/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/git-safety.sh\"" }] },
      { "matcher": "Read", "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/secret-scan.sh\"" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/test-gate.sh\"" }] }
    ],
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/capture-learnings.sh\"" }] }
    ],
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/load-memory.sh\"" }] }
    ]
  }
}
JSON
echo "  meta    hooks/hooks.json"

# --- README ---------------------------------------------------------------------------------------
cat > "$OUT/README.md" <<'MD'
# Agent-First Toolkit (Claude Code plugin)

The agent-first tooling built across the [Agent-First Engineering curriculum](https://codyamaughan.github.io/agent-first-engineering/),
packaged as **one installable plugin** — the capstone of [Lesson 8.3 — Plugins & marketplaces](https://codyamaughan.github.io/agent-first-engineering/curriculum/08-production-patterns/03-plugins-and-marketplaces/).

> **This directory is GENERATED.** Do not hand-edit it — run `sh scripts/build-plugin.sh` from the repo
> root to regenerate it from the canonical sources (`.agents/skills/`, `.agent/hooks/`, `.claude/agents/`).
> The `plugin/` tree is git-ignored; the source of truth lives in the [repo](https://github.com/CodyAMaughan/agent-first-engineering).

## What's in the box

| Component | Type | General-purpose? |
|---|---|---|
| `scaffold-agent-project` | skill | ✅ turns any repo agent-first (AGENTS.md, skills, guardrail hooks) |
| `author-curriculum` | skill | curriculum-specific (authoring lessons against a rubric) |
| `check-understanding` | skill | curriculum-specific (quizzes from `quiz.json`) |
| `code-reviewer`, `lesson-reviewer` | subagents | adversarial, least-privilege reviewers (read + inspect, no write) |
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
MD
echo "  doc     README.md"

echo "Done — plugin/ is current."
