# Adapter: Cursor

**Context:** Cursor reads `AGENTS.md` natively; optionally also emit `.cursor/rules/*.mdc` for
glob-scoped rules.
**Skills:** `.agents/skills/` is native (Cursor also reads `.cursor/skills/`).
**Hooks:** register shared scripts in `.cursor/hooks.json` using **camelCase** events. Cursor splits
`tool.pre` into granular events.

```json
{
  "hooks": {
    "beforeShellExecution": [{ "command": "sh .agent/hooks/git-safety.sh", "failClosed": true }],
    "beforeReadFile":       [{ "command": "sh .agent/hooks/secret-scan.sh", "failClosed": true }],
    "stop":                 [{ "command": "sh .agent/hooks/test-gate.sh", "failClosed": true }],
    "preCompact":           [{ "command": "sh .agent/hooks/capture-learnings.sh", "failClosed": true }],
    "sessionStart":         [{ "command": "sh .agent/hooks/load-memory.sh" }]
  }
}
```

Notes — the portability traps the scaffolder handles automatically:
- **Cursor fails *open* by default** → every security/capture hook gets `"failClosed": true`.
- `PreToolUse` → map to `beforeShellExecution` / `beforeReadFile` / `beforeMCPExecution` as needed.
- No `PostCompact`; output schema is flat (`{ "permission": "...", "user_message": "...", "agent_message": "..." }`)
  rather than Claude's `hookSpecificOutput` envelope.
