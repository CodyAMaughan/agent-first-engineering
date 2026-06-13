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

# Serialize concurrent runs: rollup-append + per-section merge + staging-truncate is a
# read-modify-write of shared files with no atomicity. Two near-simultaneous compact.pre/
# session.end runs would both see non-empty staging and both append, duplicating/tearing the
# audit trail (and racing the per-section mv/:>). `mkdir` is atomic, so exactly one run wins
# the lock; a loser exits cleanly (the winner persists the staged content, and load-memory.sh
# re-injects it). Released on exit so a crash can't wedge the next session.
LOCK="$MEM_DIR/.capture.lock"
mkdir "$LOCK" 2>/dev/null || exit 0   # another run owns this flush -> it will persist staging
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

[ -s "$STAGING" ] || exit 0           # nothing staged -> done

# Append a dated rollup (append-only audit trail).
{
  printf '\n## %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo session)"
  cat "$STAGING"
} >> "$LOG"

# Merge by semantic path. Each "## <path>" heading => .agent/memory/<path>.md (replace, not append).
current=""
tmp=""
unsaved=0                              # 1 if any section had no valid path -> keep staging to fix
flush() {
  [ -n "$current" ] || return 0
  target="$MEM_DIR/$current.md"
  mkdir -p "$(dirname "$target")"
  mv "$tmp" "$target"
}
while IFS= read -r line || [ -n "$line" ]; do
  # Strip a leading UTF-8 BOM (bytes EF BB BF) so a BOM-prefixed first heading is still
  # recognized by the "## " glob below — otherwise the section would be misclassified as
  # body, never persisted, and staging wiped (silent memory loss).
  case "$line" in
    "$(printf '\357\273\277')"*) line=${line#"$(printf '\357\273\277')"} ;;
  esac
  case "$line" in
    "## "*)
      flush
      # Strip the leading "## " AND a trailing carriage return: with CRLF staging
      # (Windows editors / cross-platform pipelines) IFS=read keeps the \r in $line,
      # so without this the path becomes "tools/db\r" and the file is written as
      # tools/db^M.md — orphaned from the clean "tools/db.md" a later LF heading writes,
      # breaking the living-document replace guarantee.
      current=$(printf '%s' "$line" | sed 's/^## *//; s/'"$(printf '\r')"'$//')
      # Reject a path that is empty, absolute, or traverses upward ("..") — staged content is
      # attacker-influenceable, so a heading like "## ../../OUTSIDE" must not escape the memory lane.
      case "$current" in
        ""|/*|*..*) current=""; unsaved=1 ;;   # can't persist -> keep staging to fix
        *)
          tmp=$(mktemp 2>/dev/null || echo "$MEM_DIR/.tmp.$$")
          printf '# %s\n' "$current" > "$tmp"
          ;;
      esac
      ;;
    *)
      [ -n "$current" ] && printf '%s\n' "$line" >> "$tmp"
      ;;
  esac
done < "$STAGING"
flush

# Only clear staging if every section was persisted; otherwise leave it intact so the
# malformed section (empty "## " path) can be fixed instead of silently lost.
[ "$unsaved" -eq 0 ] && : > "$STAGING"
exit 0
