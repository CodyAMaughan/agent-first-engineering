#!/bin/sh
# load-memory.sh — re-inject persisted learnings at session start.
# Bind to canonical `session.start` (Claude `SessionStart`, Codex `SessionStart`, Cursor `sessionStart`).
# Prints the memory wiki to stdout; agents inject stdout as additional context at session start.
# Deterministic, NO LLM call. Excludes the staging buffer and the append-only log.

set -u
# Force a byte-oriented locale so ${#var} counts BYTES, not characters. The byte
# budget below is bounded with `head -c` (bytes), but the `used` accumulator uses
# ${#...}; under a UTF-8 locale that counts characters, undercounting multibyte
# (2-3 byte) content ~2-3x and letting the cap be exceeded every session.
LC_ALL=C
export LC_ALL
MEM_DIR="${SCAFFOLD_MEMORY_DIR:-.agent/memory}"
cat >/dev/null 2>&1 || true            # drain stdin

[ -d "$MEM_DIR" ] || exit 0

# Total byte budget for the re-injection. stdout is injected as session-start
# context EVERY session, so an oversized staged learning must not flood it:
# cap the total emitted bytes (override with SCAFFOLD_MEMORY_MAX_BYTES).
BUDGET="${SCAFFOLD_MEMORY_MAX_BYTES:-262144}"   # 256 KiB

found=0
used=0
find "$MEM_DIR" -type f -name '*.md' 2>/dev/null | grep -v '_staging.md' | grep -v 'session-log.md' | sort | while IFS= read -r f; do
  [ "$used" -lt "$BUDGET" ] || break
  if [ "$found" -eq 0 ]; then
    title='# Project memory (persisted learnings)'
    printf '%s\n\n' "$title"
    used=$((used + ${#title} + 2))
    found=1
  fi
  header="<!-- $f -->"
  printf '%s\n' "$header"
  used=$((used + ${#header} + 1))
  # Leave 1 byte for the trailing newline printf adds below.
  remain=$((BUDGET - used - 1))
  [ "$remain" -gt 0 ] || break
  # head -c bounds each file to whatever budget remains; total stays <= BUDGET.
  chunk=$(head -c "$remain" "$f")
  printf '%s\n' "$chunk"
  used=$((used + ${#chunk} + 1))
done
exit 0
