#!/bin/sh
# check-skill-mirror-empty.sh — assert tests/check-skill-mirror.sh is NOT a
# false-green when there are zero first-party skills on both sides.
#
# Bug under test (check-skill-mirror.sh:13,21,29,43): with both .agents/skills
# and .claude/skills empty, names() returns "" for each side, so agents="" and
# claude="". The set-parity test `[ "$agents" != "$claude" ]` (line 21) is false
# ("" == ""), and the two for-loops (lines 29, 43) iterate over empty strings —
# zero iterations. `fail` stays 0, so the script prints
# "PASS — all first-party skills mirror byte-for-byte." and exits 0 — a verdict
# byte-identical to a healthy repo. A botched move/delete that wipes the entire
# first-party skills library on BOTH sides is declared clean by this CI gate.
#
# EXPECTED: a parity gate with nothing to mirror must NOT report PASS/exit 0.
#
# Like check-test-gate-isolation.sh / check-skill-frontmatter-encoding.sh, this
# drives the REAL target script in a throwaway temp repo and runs a built-in
# self-test first to prove the oracle isn't trivially always-fail: it must accept
# a healthy (non-empty, byte-identical) tree and reject the empty one.
# Deterministic, POSIX sh, deps: mktemp/cp/find. Run from the repo root.

set -u
ROOT="${1:-.}"
TARGET="$ROOT/tests/check-skill-mirror.sh"
# Absolute path: we run the target from inside a temp repo, so a relative path
# would vanish once we leave the real repo root.
case "$TARGET" in /*) ;; *) TARGET="$(pwd)/$TARGET" ;; esac
fail=0

[ -f "$TARGET" ] || { echo "FAIL — target not found: $TARGET"; exit 1; }

echo "Checking skill-mirror gate is not a false-green with zero first-party skills: $TARGET"

# run_gate <skills-tree-builder>: build a temp repo (.agents/skills + .claude/skills),
# let the caller-supplied function populate it, then run the REAL gate from that
# repo root. Echoes the gate's combined output. The gate's exit code is written
# to $RC_FILE (a file, not a var) so it survives the $(...) subshell capture.
RC_FILE=$(mktemp) || { echo "FAIL — mktemp failed"; exit 1; }
run_gate() {
  builder="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; echo 99 > "$RC_FILE"; return; }
  mkdir -p "$td/.agents/skills" "$td/.claude/skills" "$td/tests"
  cp "$TARGET" "$td/tests/check-skill-mirror.sh"
  ( cd "$td" && "$builder" "$td" )   # populate the trees for this scenario
  out=$( cd "$td" && sh tests/check-skill-mirror.sh 2>&1 ); rc=$?
  echo "$rc" > "$RC_FILE"
  rm -rf "$td"
  printf '%s\n' "$out"
}

# Scenario builders ------------------------------------------------------------
build_empty()   { :; }                       # both skills dirs left empty
build_healthy() {                            # one byte-identical first-party skill
  td="$1"
  mkdir -p "$td/.agents/skills/demo" "$td/.claude/skills/demo"
  printf 'name: demo\n' > "$td/.agents/skills/demo/SKILL.md"
  printf 'name: demo\n' > "$td/.claude/skills/demo/SKILL.md"
}

# --- self-test (proves this regression oracle isn't trivially always-fail) -----
# A healthy, non-empty, byte-identical tree MUST pass the gate (exit 0). If the
# oracle rejected even that, it would be meaningless.
healthy_out=$(run_gate build_healthy); healthy_rc=$(cat "$RC_FILE")
if [ "$healthy_rc" -eq 0 ]; then
  echo "  ok   self-test: healthy non-empty tree passes the gate (exit 0)"
else
  echo "  FAIL self-test: healthy non-empty tree did NOT pass (exit $healthy_rc) — oracle too strict:"
  printf '%s\n' "$healthy_out" | sed 's/^/         /'
  echo "FAIL — self-test failed; aborting."
  exit 1
fi

# --- real check: the EMPTY-both-sides scenario must NOT be a clean PASS ---------
empty_out=$(run_gate build_empty); empty_rc=$(cat "$RC_FILE")
echo "  ..   empty-both-sides gate exited $empty_rc"
if [ "$empty_rc" -eq 0 ]; then
  echo "  FAIL empty-both-sides parity gate reported success (exit 0) — nothing is being mirrored yet it passes:"
  printf '%s\n' "$empty_out" | sed 's/^/         /'
  fail=1
else
  echo "  ok   empty-both-sides gate flags that no skills are being mirrored (exit $empty_rc)"
fi

rm -f "$RC_FILE"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — skill-mirror gate refuses to false-green an empty (all-skills-wiped) tree."
else
  echo "FAIL — tests/check-skill-mirror.sh declares an EMPTY first-party skill set (both sides) a clean PASS/exit 0 (names() returns \"\" so the line-21 parity test and the line-29/43 loops are no-ops); a wiped skills library passes the CI gate. Guard that at least one skill is mirrored."
fi
exit "$fail"
