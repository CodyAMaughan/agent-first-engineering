#!/bin/sh
# check-capture-learnings-crlf.sh — assert .agent/hooks/capture-learnings.sh does
# NOT embed a carriage return in the derived memory filename when a "## <path>"
# heading arrives with CRLF line endings.
#
# Bug under test (capture-learnings.sh:62-64): the merge loop derives the section
# path with `current=$(printf '%s' "$line" | sed 's/^## *//')`. That sed strips
# only the leading "## " — it does NOT strip a trailing carriage return. With a
# CRLF heading "## tools/db\r\n", IFS=read keeps the \r in $line, so current
# becomes "tools/db\r" and target becomes "$MEM_DIR/tools/db\r.md". The hook
# writes a file whose name literally contains a CR (renders as "db^M.md").
#
# Consequence (the real defect): the living-document "the section REPLACES the
# file" guarantee breaks. A later CLEAN heading "## tools/db\n" writes a DIFFERENT
# file (tools/db.md), so the CRLF file is orphaned — unreachable by the intended
# name and never re-merged. CRLF staging is a realistic encoding artifact (Windows
# editors, cross-platform pipelines), and staging is the hook's own stated
# attacker-influenceable input (capture-learnings.sh:65-66). The fix must derive a
# clean path (strip the trailing CR) so the CRLF and clean headings address the
# SAME file.
#
# Deterministic, POSIX sh, deps: mktemp, printf, find. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/capture-learnings.sh"
# Absolute path: the runner cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# CR byte, used both to build CRLF input and to detect a CR in a produced filename.
CR=$(printf '\r')

# --- self-test (proves the oracle isn't trivially always-pass) ------------------------------
# The oracle is: after the hook runs over CRLF staging, the produced memory file must be
# the CLEAN name "tools/db.md" — NOT a name containing a carriage return, and NOT a
# different name than a clean heading would produce. It only PASSES on the clean name.
self_test() {
  st_fail=0
  st_td=$(mktemp -d) || { echo "  FAIL self-test: mktemp -d"; exit 1; }

  # (a) clean world: exactly one *.md and its name has no CR -> oracle PASS.
  mkdir -p "$st_td/a/tools"
  printf '# tools/db\nx\n' > "$st_td/a/tools/db.md"
  cnt=$(find "$st_td/a" -name '*.md' | wc -l | tr -d ' ')
  crname=0; for f in $(find "$st_td/a" -name '*.md'); do case "$f" in *"$CR"*) crname=1 ;; esac; done
  if [ "$cnt" -eq 1 ] && [ "$crname" -eq 0 ]; then
    : # ok — single clean file
  else
    echo "  FAIL self-test: a single clean tools/db.md was judged bad (oracle broken)"; st_fail=1
  fi

  # (b) CR-in-name world: the oracle must FLAG a filename containing a carriage return.
  mkdir -p "$st_td/b/tools"
  printf '# tools/db\nx\n' > "$st_td/b/tools/db${CR}.md"
  crname=0; for f in $(find "$st_td/b" -name '*.md'); do case "$f" in *"$CR"*) crname=1 ;; esac; done
  if [ "$crname" -eq 1 ]; then
    : # ok — correctly detected the CR in the filename
  else
    echo "  FAIL self-test: a CR-bearing filename was NOT detected (oracle too weak)"; st_fail=1
  fi

  rm -rf "$st_td"
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the CR-in-filename oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (clean-name=ok, CR-in-name=flagged)"
}

echo "Checking capture-learnings does not embed a CR in the derived memory filename: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: drive the REAL hook over CRLF staging --------------------------------------
td=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
mkdir -p "$td/.agent/memory"
# CRLF heading + CRLF body line: "## tools/db\r\nlearning\r\n".
printf '## tools/db\r\nlearning\r\n' > "$td/.agent/memory/_staging.md"

( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
rc=$?

clean="$td/.agent/memory/tools/db.md"
clean_exists=0; [ -f "$clean" ] && clean_exists=1

# Did any produced *.md filename contain a carriage return?
crname=0
for f in $(find "$td/.agent/memory" -name '*.md'); do
  case "$f" in *"$CR"*) crname=1 ;; esac
done

echo "  ..   hook exited $rc; clean tools/db.md exists=$clean_exists; CR-in-filename=$crname"

# THE assertion: the CRLF heading must produce the CLEAN file tools/db.md and must NOT
# produce any filename containing a carriage return. The bug produces tools/db^M.md
# (CR in name) and no clean tools/db.md, so a later clean heading would orphan it.
if [ "$clean_exists" -eq 1 ] && [ "$crname" -eq 0 ]; then
  echo "  ok   CRLF heading produced the clean tools/db.md (no CR in any filename)"
else
  echo "  FAIL CRLF heading did NOT produce clean tools/db.md (or a filename contains a CR) — living-document replace breaks"
  fail=1
fi

rm -rf "$td"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — a CRLF heading maps to the same clean memory file as a clean heading."
else
  echo "FAIL — .agent/hooks/capture-learnings.sh derives the path with \`sed 's/^## *//'\` (line 64), which strips only the leading \"## \" and leaves the trailing CR from CRLF input; \$current becomes \"tools/db\\r\" and the file is written as tools/db^M.md. A later clean \"## tools/db\" heading writes a DIFFERENT file (tools/db.md), orphaning the CR file and breaking the living-document replace guarantee."
fi
exit "$fail"
