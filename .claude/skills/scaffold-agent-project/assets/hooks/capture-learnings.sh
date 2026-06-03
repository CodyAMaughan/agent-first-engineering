#!/bin/sh
# capture-learnings.sh — deterministic, NO LLM call.
# Bind to canonical `compact.pre` (fallback `session.end`).
# Persists session learnings OUTSIDE the context window so compaction can't lose them
# (Anthropic "structured note-taking": https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents).
#
# Mechanism: during a session the agent (or user) stages durable learnings into
#   .agent/memory/_staging.md   using "## <semantic/path>" headings, e.g.:
#     ## tools/test-db
#     Needs --no-sandbox locally.
# On compaction/session-end this hook MERGES each section into .agent/memory/<semantic/path>.md
# (living document — the section REPLACES the file, not append), logs a dated rollup, clears staging.
# Re-injection is handled by load-memory.sh at session.start.
#
# Reads the agent's JSON event on stdin (drained, not required); exits 0 (non-blocking).

set -u

MEM_DIR="${SCAFFOLD_MEMORY_DIR:-.agent/memory}"
STAGING="$MEM_DIR/_staging.md"
LOG="$MEM_DIR/session-log.md"

mkdir -p "$MEM_DIR"
cat >/dev/null 2>&1 || true           # drain stdin so the agent isn't blocked
[ -s "$STAGING" ] || exit 0           # nothing staged -> done

# Append a dated rollup (append-only audit trail).
{
  printf '\n## %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo session)"
  cat "$STAGING"
} >> "$LOG"

# Merge by semantic path. Each "## <path>" heading => .agent/memory/<path>.md (replace, not append).
current=""
tmp=""
flush() {
  [ -n "$current" ] || return 0
  target="$MEM_DIR/$current.md"
  mkdir -p "$(dirname "$target")"
  mv "$tmp" "$target"
}
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    "## "*)
      flush
      current=$(printf '%s' "$line" | sed 's/^## *//')
      tmp=$(mktemp 2>/dev/null || echo "$MEM_DIR/.tmp.$$")
      printf '# %s\n' "$current" > "$tmp"
      ;;
    *)
      [ -n "$current" ] && printf '%s\n' "$line" >> "$tmp"
      ;;
  esac
done < "$STAGING"
flush

: > "$STAGING"                         # clear staging now that it's persisted
exit 0
