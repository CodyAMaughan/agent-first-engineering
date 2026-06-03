# Adapter: Codex

**Context:** Codex reads `AGENTS.md` natively — no bridge file needed.
**Skills:** `.agents/skills/` is native — no mirror needed.
**Hooks:** register shared scripts in `.codex/hooks.json` (or `[hooks]` in `~/.codex/config.toml`).
Codex's schema is a near-port of Claude's (same PascalCase events, same exit-2-blocks, same
`additionalContext`/`decision` shapes).

```json
{
  "hooks": {
    "PreToolUse":  [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "sh .agent/hooks/git-safety.sh" }] }],
    "Stop":        [{ "hooks": [{ "type": "command", "command": "sh .agent/hooks/test-gate.sh" }] }],
    "PreCompact":  [{ "hooks": [{ "type": "command", "command": "sh .agent/hooks/capture-learnings.sh" }] }],
    "SessionStart":[{ "hooks": [{ "type": "command", "command": "sh .agent/hooks/load-memory.sh" }] }]
  }
}
```

Notes: Codex has **no distinct `SessionEnd`** — `capture-learnings` already binds `PreCompact`; if you
also want end-of-thread capture, bind `Stop`. Fails closed on exit 2 (like Claude).
