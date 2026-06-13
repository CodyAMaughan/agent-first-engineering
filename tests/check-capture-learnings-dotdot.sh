#!/bin/sh
# check-capture-learnings-dotdot.sh — assert .agent/hooks/capture-learnings.sh does
# NOT reject a benign "## <path>" heading that merely CONTAINS the substring ".."
# but has no ".." PATH SEGMENT (no upward traversal), e.g. a version note like
# "## tools/v1.2..3" or "## tools/my..notes".
#
# Bug under test (capture-learnings.sh:72-73): the traversal guard
#     case "$current" in ""|/*|*..*) current=""; unsaved=1 ;;
# is meant to block path escapes ("../../OUTSIDE", "tools/../../x"). But the glob
# `*..*` matches ANY embedded double-dot, including "tools/v1.2..3" — a filename
# with NO ".." path segment, which `dirname` resolves to ".agent/memory/tools",
# fully INSIDE the memory lane. So a benign section is misclassified as a traversal
# attempt: no <path>.md is written, AND `unsaved` is set to 1 so the guard at
# line 89 `[ "$unsaved" -eq 0 ] && : > "$STAGING"` never truncates staging.
#
# Because the heading LOOKS valid to a human, nobody ever "fixes" it, so staging is
# wedged permanently. Worse, lines 39-42 UNCONDITIONALLY append the whole staging to
# session-log.md on EVERY run — so re-running the hook keeps re-appending the same
# section to the append-only log without bound, while the learning is never persisted.
#
# This is a false-negative on a benign filename (a robustness/encoding-class defect:
# the spec at line 70-71 only intends to block ESCAPES) plus a permanent gate-wedge
# that silently loses memory and grows the log unbounded. The fix must persist a
# heading with no ".." path segment (and the log must not grow on a repeat run that
# stages nothing new). What is NOT acceptable is the current "reject the benign path,
# wedge staging, append to the log forever" combination.
#
# Deterministic, POSIX sh, deps: mktemp, printf, find, wc. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/capture-learnings.sh"
# Absolute path: the runner cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# A heading that EMBEDS ".." but has no ".." path SEGMENT -> no traversal, must persist.
BENIGN="tools/v1.2..3"

# --- self-test (proves the oracle isn't trivially always-pass) ------------------------------
# Oracle: a benign (non-traversal) heading is "safe" iff its <path>.md was persisted.
# It must (a) call a persisted file safe, (b) call a missing file unsafe.
# Separately we assert that ".." as a real PATH SEGMENT is genuinely a traversal that the
# hook is RIGHT to reject — so the fix must not weaken the actual security guard.
self_test() {
  st_fail=0
  st_td=$(mktemp -d) || { echo "  FAIL self-test: mktemp -d"; exit 1; }

  # (a) persisted-file world: target present -> oracle PASS (benign path was kept).
  mkdir -p "$st_td/a/tools"
  printf '# tools/v1.2..3\nx\n' > "$st_td/a/tools/v1.2..3.md"
  if [ -f "$st_td/a/tools/v1.2..3.md" ]; then
    : # ok — persisted counts as safe
  else
    echo "  FAIL self-test: a persisted benign section was judged unsafe (oracle broken)"; st_fail=1
  fi

  # (b) the bug world: target absent -> oracle must FLAG it.
  mkdir -p "$st_td/b"
  if [ -f "$st_td/b/tools/v1.2..3.md" ]; then
    echo "  FAIL self-test: missing benign file was NOT flagged (oracle too weak)"; st_fail=1
  else
    : # ok — correctly flagged as a drop
  fi

  # (c) a REAL ".." path segment IS traversal — confirm our segment test agrees, so the
  #     fix narrows the guard to actual segments rather than removing it.
  has_dotdot_segment() {
    # echo each '/'-split component; succeed if any component is exactly "..".
    printf '%s\n' "$1" | tr '/' '\n' | grep -qx '\.\.'
  }
  has_dotdot_segment "../../OUTSIDE" || { echo "  FAIL self-test: '../../OUTSIDE' not seen as traversal"; st_fail=1; }
  has_dotdot_segment "tools/../x"    || { echo "  FAIL self-test: 'tools/../x' not seen as traversal"; st_fail=1; }
  if has_dotdot_segment "$BENIGN"; then
    echo "  FAIL self-test: benign '$BENIGN' wrongly seen as traversal (oracle broken)"; st_fail=1
  fi

  rm -rf "$st_td"
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the no-traversal oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (persisted=safe, missing=drop; real '..' segment still = traversal)"
}

echo "Checking capture-learnings persists a benign embedded-'..' (non-traversal) heading: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: drive the REAL hook over a benign embedded-'..' heading --------------------
td=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
mkdir -p "$td/.agent/memory"
printf '## %s\nversion notes\n' "$BENIGN" > "$td/.agent/memory/_staging.md"

# Run 1: should persist tools/v1.2..3.md and clear staging.
( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
rc1=$?
log1=$( [ -f "$td/.agent/memory/session-log.md" ] && wc -l < "$td/.agent/memory/session-log.md" || echo 0 )

# Run 2 + 3: nothing NEW should be staged after run 1, so the append-only log must NOT keep
# growing. With the bug, staging is never cleared, so each run re-appends the same section.
( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
log3=$( [ -f "$td/.agent/memory/session-log.md" ] && wc -l < "$td/.agent/memory/session-log.md" || echo 0 )

target="$td/.agent/memory/tools/v1.2..3.md"
staging="$td/.agent/memory/_staging.md"
persisted=0; [ -f "$target" ] && persisted=1
retained=0; [ -s "$staging" ] && retained=1

# Did any traversal actually occur? (Nothing should be written OUTSIDE the memory dir.)
escaped=0
[ -e "$td/.agent/v1.2..3.md" ] && escaped=1
[ -e "$td/v1.2..3.md" ] && escaped=1

echo "  ..   run1 rc=$rc1; persisted=$persisted (tools/v1.2..3.md); staging-retained=$retained; escaped=$escaped"
echo "  ..   session-log lines after run1=$log1, after run3=$log3"

# THE assertion, two parts:
#  (1) the benign heading must be PERSISTED (it does not escape the memory lane), AND
#  (2) the append-only log must NOT grow on repeat runs that stage nothing new.
# The bug fails (1) (no file, staging wedged unsaved=1) and (2) (log grows every run).
if [ "$escaped" -ne 0 ]; then
  echo "  FAIL the benign heading ESCAPED the memory lane — must never happen"
  fail=1
elif [ "$persisted" -eq 1 ] && [ "$log3" -le "$log1" ]; then
  echo "  ok   benign embedded-'..' heading persisted and the log is bounded across repeat runs"
else
  [ "$persisted" -eq 0 ] && echo "  FAIL benign heading '$BENIGN' was REJECTED as traversal: no tools/v1.2..3.md written (staging-retained=$retained, wedged)"
  [ "$log3" -gt "$log1" ] && echo "  FAIL append-only log grew on repeat no-op runs ($log1 -> $log3 lines): wedged staging is re-appended every compaction (unbounded)"
  fail=1
fi

rm -rf "$td"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — a heading that merely contains '..' (no '..' path segment) is persisted, and the log stays bounded."
else
  echo "FAIL — .agent/hooks/capture-learnings.sh:73 \`case \"\$current\" in \"\"|/*|*..*)\` rejects ANY heading containing the substring '..', including benign filenames like '$BENIGN' with no '..' PATH SEGMENT. The section is never persisted, \`unsaved=1\` wedges staging permanently (line 89 never truncates), and lines 39-42 re-append the wedged staging to session-log.md on every run — unbounded log growth + permanent memory loss. Narrow the guard to reject only a real '..' path SEGMENT (or a normalized path that escapes \$MEM_DIR), not any embedded double-dot."
fi
exit "$fail"
