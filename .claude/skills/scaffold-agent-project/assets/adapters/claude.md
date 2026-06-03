# Adapter: Claude Code

**Context:** write `CLAUDE.md` = a single line `@AGENTS.md` (+ Claude-only notes if any).
**Skills:** mirror `.agents/skills/` → `.claude/skills/`.
**Hooks:** register shared scripts in `.claude/settings.json` under `hooks`, using PascalCase events.

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "sh .agent/hooks/git-safety.sh" }] },
      { "matcher": "Read", "hooks": [{ "type": "command", "command": "sh .agent/hooks/secret-scan.sh" }] }
    ],
    "Stop":       [{ "hooks": [{ "type": "command", "command": "sh .agent/hooks/test-gate.sh" }] }],
    "PreCompact": [{ "hooks": [{ "type": "command", "command": "sh .agent/hooks/capture-learnings.sh" }] }],
    "SessionStart":[{ "hooks": [{ "type": "command", "command": "sh .agent/hooks/load-memory.sh" }] }]
  }
}
```

Notes: Claude honors exit-2 to block (fails closed). Event names: `PreToolUse`, `PostToolUse`,
`Stop`, `PreCompact`/`PostCompact`, `SessionStart`/`SessionEnd`, `UserPromptSubmit`,
`SubagentStart`/`SubagentStop`.
