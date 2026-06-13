#!/bin/sh
# check-skill-mirror.sh — assert every first-party skill is byte-identical in both
# .agents/skills/ (canonical, open-standard source of truth) and .claude/skills/
# (the Claude Code mirror). Third-party skills under .claude/skills/ (speckit-*) are
# not ours to mirror and are ignored. Exits non-zero on any missing mirror or drift.
# Deterministic, POSIX sh, deps: find/diff/sort/grep. Run from the repo root.

set -u
AG=".agents/skills"
CL=".claude/skills"
fail=0

names() { find "$1" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort; }

agents=$(names "$AG")
claude=$(names "$CL" | grep -v '^speckit-')   # our skills only

echo "Checking skill mirror parity: $AG  <->  $CL"

# 0. There must be at least one first-party skill to mirror. With both sides empty
#    names() returns "", the parity test "" != "" is false, and the for-loops below
#    iterate zero times — a wiped skills library would otherwise pass as clean.
if [ -z "$agents" ] && [ -z "$claude" ]; then
  echo "  FAIL no first-party skills found in $AG or $CL — nothing is being mirrored"
  fail=1
fi

# 1. The set of first-party skills must be the same on both sides.
if [ "$agents" != "$claude" ]; then
  echo "  FAIL skill sets differ (a skill is missing from one side)"
  echo "       canonical (.agents/skills): $(echo $agents)"
  echo "       mirror    (.claude/skills): $(echo $claude)   [speckit-* ignored]"
  fail=1
fi

# 2. Each canonical skill must be byte-identical to its mirror.
for name in $agents; do
  if [ ! -d "$CL/$name" ]; then
    echo "  FAIL $name: present in $AG but missing from $CL"
    fail=1
  elif diff -r "$AG/$name" "$CL/$name" >/dev/null 2>&1; then
    echo "  ok   $name"
  else
    echo "  FAIL $name: contents differ —"
    diff -r "$AG/$name" "$CL/$name" 2>&1 | sed 's/^/         /'
    fail=1
  fi
done

# 3. Catch a first-party skill that exists only in the mirror (never made canonical).
for name in $claude; do
  [ -d "$AG/$name" ] || { echo "  FAIL $name: present in $CL but missing from canonical $AG"; fail=1; }
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — all first-party skills mirror byte-for-byte."
else
  echo "FAIL — sync them, e.g.:  cp -R .agents/skills/<name> .claude/skills/<name>  (canonical wins)"
fi
exit "$fail"
