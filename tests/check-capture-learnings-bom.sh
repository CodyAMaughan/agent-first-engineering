#!/bin/sh
# check-capture-learnings-bom.sh — assert .agent/hooks/capture-learnings.sh does
# NOT silently drop a staged learning (and wipe staging) when the first "## <path>"
# heading is preceded by a UTF-8 BOM (bytes EF BB BF).
#
# Bug under test (capture-learnings.sh:54-78): the merge loop classifies each line
# with `case "$line" in "## "*)`. A leading UTF-8 BOM before the first heading makes
# the line begin with the bytes EF BB BF, so the "## " glob does NOT match. The
# heading falls through to the `*)` body branch (line 69-70), but `current` is still
# "" so nothing is written and no target file is created. `unsaved` is never set to 1
# (that only happens INSIDE the matched branch for empty/absolute/.. paths), so the
# guard at line 78 `[ "$unsaved" -eq 0 ] && : > "$STAGING"` TRUNCATES staging. Net:
# the learning is dropped AND staging is wiped in the same run — permanent loss of
# the structured memory file that load-memory.sh would re-inject.
#
# A leading BOM is a realistic encoding artifact (Windows editors, some printf /
# redirect pipelines), and staging is the hook's own stated attacker-influenceable
# input (capture-learnings.sh:59-60). The fix must persist the first section anyway,
# OR (acceptably) leave staging intact for repair — what is NOT acceptable is the
# current "drop the learning AND wipe staging" combination.
#
# Deterministic, POSIX sh, deps: mktemp, printf, find. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/capture-learnings.sh"
# Absolute path: the runner cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# --- self-test (proves the oracle isn't trivially always-pass) ------------------------------
# The oracle is: after the hook runs over BOM-prefixed staging, EITHER the section was
# persisted (tools/db.md exists) OR staging was left intact for repair (still non-empty).
# It only FAILS on the bug's exact signature: file absent AND staging emptied.
self_test() {
  st_fail=0
  st_td=$(mktemp -d) || { echo "  FAIL self-test: mktemp -d"; exit 1; }

  # (a) persisted-file world: target present, staging emptied -> oracle PASS (not data loss).
  mkdir -p "$st_td/a/tools"
  printf '# tools/db\nx\n' > "$st_td/a/tools/db.md"
  : > "$st_td/a/_staging.md"
  if [ -f "$st_td/a/tools/db.md" ] || [ -s "$st_td/a/_staging.md" ]; then
    : # ok — persisted counts as not-lost
  else
    echo "  FAIL self-test: a persisted section was judged as data loss (oracle broken)"; st_fail=1
  fi

  # (b) intact-staging world: target absent but staging non-empty -> oracle PASS (repairable).
  mkdir -p "$st_td/b"
  printf '\357\273\277## tools/db\nx\n' > "$st_td/b/_staging.md"
  if [ -f "$st_td/b/tools/db.md" ] || [ -s "$st_td/b/_staging.md" ]; then
    : # ok — staging retained, learning recoverable
  else
    echo "  FAIL self-test: retained-staging was judged as data loss (oracle broken)"; st_fail=1
  fi

  # (c) the bug world: target absent AND staging emptied -> oracle must FLAG it.
  mkdir -p "$st_td/c"
  : > "$st_td/c/_staging.md"   # emptied
  if [ -f "$st_td/c/tools/db.md" ] || [ -s "$st_td/c/_staging.md" ]; then
    echo "  FAIL self-test: data-loss world (no file, empty staging) was NOT flagged (oracle too weak)"; st_fail=1
  else
    : # ok — correctly flagged as loss
  fi

  rm -rf "$st_td"
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the data-loss oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (persisted=safe, intact-staging=safe, no-file+empty-staging=loss)"
}

echo "Checking capture-learnings does not drop a BOM-prefixed learning + wipe staging: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: drive the REAL hook over BOM-prefixed staging ------------------------------
td=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
mkdir -p "$td/.agent/memory"
# Leading UTF-8 BOM (EF BB BF) then "## tools/db" then a body line.
printf '\357\273\277## tools/db\nimportant learning\n' > "$td/.agent/memory/_staging.md"

( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
rc=$?

target="$td/.agent/memory/tools/db.md"
staging="$td/.agent/memory/_staging.md"
persisted=0; [ -f "$target" ] && persisted=1
retained=0; [ -s "$staging" ] && retained=1

echo "  ..   hook exited $rc; persisted=$persisted (tools/db.md), retained=$retained (staging non-empty)"

# THE assertion: the learning must not be irrecoverably lost. Acceptable outcomes:
#   - persisted: tools/db.md exists (load-memory.sh can re-inject it), OR
#   - retained:  staging still non-empty (the section can be fixed and re-flushed).
# The bug produces NEITHER: file absent AND staging wiped.
if [ "$persisted" -eq 1 ] || [ "$retained" -eq 1 ]; then
  echo "  ok   BOM-prefixed learning is recoverable (persisted or staging retained)"
else
  echo "  FAIL BOM-prefixed learning was DROPPED: no tools/db.md AND staging wiped (0 bytes) — permanent memory loss"
  fail=1
fi

rm -rf "$td"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — a BOM-prefixed first heading does not cause silent learning loss."
else
  echo "FAIL — .agent/hooks/capture-learnings.sh's merge loop matches headings with \`case \"\$line\" in \"## \"*)\` (line 56); a leading UTF-8 BOM makes that glob miss, so the section is treated as body, \`current\` stays empty, no file is written, \`unsaved\` stays 0, and line 78 truncates staging — dropping the learning permanently."
fi
exit "$fail"
