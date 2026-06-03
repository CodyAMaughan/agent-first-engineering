# Per-Agent Adapter Paths

The shared core is `AGENTS.md` (root) + `.agents/skills/*/SKILL.md`. Each agent adapter renders its
native files; the core stays byte-identical. (Source: `docs/translation-matrix.md`.)

| Concern | Claude Code | Codex | Cursor |
|---|---|---|---|
| Context file | `CLAUDE.md` = `@AGENTS.md` bridge | reads `AGENTS.md` natively | reads `AGENTS.md`; optional `.cursor/rules/*.mdc` |
| Skills dir | `.claude/skills/` (mirror of `.agents/skills/`) | `.agents/skills/` (native) | `.agents/skills/` (native) + `.cursor/skills/` |
| Hooks config | `.claude/settings.json` (`hooks` block) | `.codex/hooks.json` or `[hooks]` in `~/.codex/config.toml` | `.cursor/hooks.json` |
| Permissions | `.claude/settings.json` (`permissions` allow/deny/ask) | `[execpolicy]` / approval policy | `.cursor/permissions.json` |
| MCP | `.mcp.json` | `[mcp_servers]` in config.toml | shared editor/CLI MCP config |
| Shared vs personal | `settings.json` (git) vs `settings.local.json` (gitignored) | `config.toml` + profiles | `permissions.json` + personal |

## Rules
- Always write the **portable core** first (`AGENTS.md`, `.agents/skills/`). Then per selected agent,
  write only its adapter files.
- For Claude, **mirror** `.agents/skills/` → `.claude/skills/` (Claude auto-discovers `.claude/skills/`).
- Hook **scripts** are shared (`.agent/hooks/*.sh`); only the **registration** (the config file entry
  pointing at the script + the native event name) differs per agent.
- Use portable script paths (no absolute paths); reference repo root via the agent's project-dir var
  where available.
