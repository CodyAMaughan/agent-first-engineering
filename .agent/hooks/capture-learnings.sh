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

# Atomically SNAPSHOT staging before we read it, so the producer (agent/user) can
# keep appending learnings to _staging.md DURING this flush without losing them.
# Without this, the read loop + truncate (`: > "$STAGING"`) was a non-atomic
# test-read-truncate of the SAME live file: a section appended AFTER the read loop
# hit EOF but BEFORE the truncate was read by nobody and then wiped (silent lost
# write, rc=0). The lockdir above only serializes capture-vs-capture; it takes no
# lock against the producer. Renaming the live file out of the way (rename is
# atomic on one filesystem) decouples us from the producer: every section we act on
# is the snapshot, and any append the producer makes lands on a FRESH _staging.md
# that this run never touches, so it survives to the next flush. We deliberately
# rename WITHOUT the external `mv` binary (a shell-internal claim) and keep the
# per-section flush as the only `mv`, so the merge below is unaffected.
SNAP="$MEM_DIR/.staging.$$"
# Hardlink-then-unlink is an atomic claim: SNAP names the staged inode, then we
# drop the _staging.md name. A producer append after this point either created a
# brand-new _staging.md (its open(O_CREAT) lost the race only against our unlink,
# never against our read) which we leave intact. ln/rm avoids the `mv` binary the
# per-section flush (and its test shim) relies on.
if ln "$STAGING" "$SNAP" 2>/dev/null; then
  rm -f "$STAGING"
else
  # No hardlink support (or cross-device): fall back to a copy. Still safe — we
  # truncate ONLY the bytes we copied, leaving any concurrently-appended tail.
  cp "$STAGING" "$SNAP" 2>/dev/null || exit 0
  rm -f "$STAGING"
fi
[ -s "$SNAP" ] || { rm -f "$SNAP"; exit 0; }

# Append a dated rollup (append-only audit trail).
{
  printf '\n## %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo session)"
  cat "$SNAP"
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
      # Only a real ".." path SEGMENT is traversal (".." alone, or bounded by "/"): a benign
      # filename that merely embeds the substring ".." (e.g. "tools/v1.2..3") stays INSIDE the
      # lane and must persist, so we match the four segment forms, not the broad glob "*..*".
      case "$current" in
        ""|/*|".."|"../"*|*"/.."|*"/../"*) current=""; unsaved=1 ;;   # can't persist -> keep staging to fix
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
done < "$SNAP"
flush

# Staging was already claimed (renamed to $SNAP) atomically, so a producer append
# during this flush is safe in the live _staging.md and untouched here.
#   unsaved==0: every section persisted -> drop the snapshot.
#   unsaved!=0: a malformed section (e.g. empty "## " path) couldn't be persisted ->
#     PREPEND the snapshot back onto the live _staging.md (ahead of anything the
#     producer appended meanwhile) so the bad section can be fixed instead of lost.
if [ "$unsaved" -eq 0 ]; then
  rm -f "$SNAP"
else
  restore="$MEM_DIR/.restore.$$"
  if [ -s "$STAGING" ]; then
    cat "$SNAP" "$STAGING" > "$restore" 2>/dev/null && mv "$restore" "$STAGING"
  else
    mv "$SNAP" "$STAGING" 2>/dev/null
  fi
  rm -f "$SNAP" "$restore"
fi
exit 0
