#!/bin/sh
# load-memory.sh — re-inject persisted learnings at session start.
# Bind to canonical `session.start` (Claude `SessionStart`, Codex `SessionStart`, Cursor `sessionStart`).
# Prints the memory wiki to stdout; agents inject stdout as additional context at session start.
# Deterministic, NO LLM call. Excludes the staging buffer and the append-only log.

set -u
MEM_DIR="${SCAFFOLD_MEMORY_DIR:-.agent/memory}"
cat >/dev/null 2>&1 || true            # drain stdin

[ -d "$MEM_DIR" ] || exit 0

found=0
# Exclude ONLY the two top-level transient files by EXACT path (not a substring grep, which would
# also drop a legitimately-persisted nested learning like reference/session-log.md). [qa-loop found this]
find "$MEM_DIR" -type f -name '*.md' ! -path "$MEM_DIR/_staging.md" ! -path "$MEM_DIR/session-log.md" 2>/dev/null | sort | while IFS= read -r f; do
  if [ "$found" -eq 0 ]; then
    printf '# Project memory (persisted learnings)\n\n'
    found=1
  fi
  printf '<!-- %s -->\n' "$f"
  cat "$f"
  printf '\n'
done
exit 0
