# Canonical → Native Hook Event Map

Author guardrails against the **canonical** event; the adapter renders the agent's native name. Where
a target lacks an event, bind the **fallback** and record the downgrade in the run summary. (Source:
`docs/translation-matrix.md`.)

| Canonical | Claude Code | Codex | Cursor | Fallback if missing |
|---|---|---|---|---|
| `session.start` | `SessionStart` | `SessionStart` | `sessionStart` | first `prompt.submit` injects context |
| `prompt.submit` | `UserPromptSubmit` | `UserPromptSubmit` | `beforeSubmitPrompt` | — |
| `tool.pre` | `PreToolUse` | `PreToolUse` | `preToolUse` / `beforeShellExecution` / `beforeReadFile` | — |
| `tool.post` | `PostToolUse` | `PostToolUse` | `afterFileEdit` / `afterShellExecution` | — |
| `subagent.start` | `SubagentStart` | `SubagentStart` | `subagentStart` | `session.start` in subagent |
| `subagent.stop` | `SubagentStop` | `SubagentStop` | `subagentStop` | `turn.stop` |
| `compact.pre` | `PreCompact` | `PreCompact` | `preCompact` | `session.end` |
| `compact.post` | `PostCompact` | `PostCompact` | *(none)* | re-run `session.start` |
| `turn.stop` | `Stop` | `Stop` | `stop` | last `tool.post` |
| `session.end` | `SessionEnd` | *(none — use `Stop`)* | `sessionEnd` | `turn.stop` cleanup |

## Protocol (shared)
- Hook receives a JSON event on **stdin**, returns a decision via **exit code** (0 = allow/continue,
  2 = block) and/or JSON on stdout.
- **Fail-safe direction differs:** Claude/Codex effectively fail *closed* on exit 2; **Cursor fails
  *open* by default** — set `"failClosed": true` on Cursor security hooks.
- Event-name case: Claude/Codex PascalCase; Cursor camelCase. Cursor splits `tool.pre` into granular
  events — map one canonical hook to the relevant Cursor event(s).

## Guardrail → event bindings (defaults)
| Guardrail | Canonical event |
|---|---|
| `secret-scan` | `tool.pre` (block reads/commits of secrets) |
| `git-safety` | `tool.pre` (block dangerous git / default-branch edits) |
| post-edit format/lint | `tool.post` |
| `test-gate` | `turn.stop` (refuse to finish until tests pass) |
| `capture-learnings` | `compact.pre` → fallback `session.end` |
| memory re-inject | `session.start` |
