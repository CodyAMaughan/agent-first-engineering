# Agent guardrails & memory (`.agent/`)

The agent-first control layer for this repo — installed by **dogfooding** the companion
`scaffold-agent-project` skill (the curriculum's capstone artifact). Registered for Claude Code in
`.claude/settings.json`; the scripts are portable POSIX sh with **no LLM calls**.

- **`hooks/`** — deterministic guardrail scripts the agent harness runs:
  - `git-safety` (PreToolUse/Bash) — blocks destructive commands (`rm -rf /`, force-push, `reset --hard`,
    `clean -f`) and, optionally, commits to a protected branch.
  - `secret-scan` (PreToolUse/Read) — blocks reading/committing likely secrets (`.env`, keys, creds).
  - `test-gate` (Stop) — refuses to finish until `TEST_CMD` passes.
  - `capture-learnings` / `load-memory` — the memory loop (below).
- **`guardrails.conf`** — project config the hooks read: `TEST_CMD`, `PROTECTED_BRANCHES`, `FORMAT_CMD`.
- **`memory/`** — the persisted **learnings wiki** (Phase 2's capture-learnings loop):
  - `load-memory.sh` re-injects every `memory/**/*.md` as context at `SessionStart`.
  - During a session, stage durable learnings into `memory/_staging.md` under `## <semantic/path>` headings.
  - `capture-learnings.sh` (on `PreCompact`) merges each section into `memory/<path>.md` (**replace, not
    append** — a living document), appends a dated rollup to `session-log.md`, and clears staging.
  - `_staging.md` and `session-log.md` are gitignored (transient); the wiki `.md` files are committed.

This directory is also what `tests/validate.sh` checks (hooks executable; the capture-learnings loop fires).
