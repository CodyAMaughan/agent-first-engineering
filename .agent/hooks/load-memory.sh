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

# Take the SAME lock capture-learnings.sh holds during its per-section `mv` flush
# ($MEM_DIR/.capture.lock, an atomic mkdir). capture persists each staged section
# with its own `mv "$tmp" "$target"`, so while that loop runs the memory dir is a
# half-applied merge — some sections already flipped to the new body, the rest still
# stale. We snapshot the dir (find|sort) and stream each file (head -c) with no
# atomicity of our own, so a re-injection that fires mid-flush would straddle the loop
# and emit a TORN wiki mixing pre- and post-merge sections.
#
# `mkdir` is atomic, so this is non-blocking mutual exclusion:
#   - We WIN the lock  -> no flush is in progress; the dir is a consistent snapshot.
#     Read it, then release the lock on exit (only the lock WE created).
#   - We LOSE the lock -> capture owns it and is mid-flush; the dir is half-merged.
#     Rather than re-inject a torn wiki, SKIP this re-injection (exit 0, emit nothing).
#     The next session.start fires after the flush completes and re-injects the
#     consistent, fully-merged tree. We must NOT remove a lock capture owns.
LOCK="$MEM_DIR/.capture.lock"
if mkdir "$LOCK" 2>/dev/null; then
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
else
  exit 0                                 # capture is flushing -> skip the torn read
fi

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
