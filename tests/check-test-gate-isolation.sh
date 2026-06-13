#!/bin/sh
# check-test-gate-isolation.sh — assert .agent/hooks/test-gate.sh isolates each
# run's test output so a concurrent stop cannot cross-contaminate the failure
# `reason` it feeds back to the agent.
#
# Bug under test (test-gate.sh:24,30): the hook writes its test output to the
# FIXED, host-wide path `/tmp/test-gate.out` (line 24) and tails that SAME fixed
# path to build the block `reason` (line 30). There is no per-run isolation
# token (`$$`/`mktemp`). When two stops run near-simultaneously — two agents,
# worktrees, or users — run B's TEST_CMD overwrites `/tmp/test-gate.out` between
# the moment run A writes it and the moment run A tails it. Run A then blocks
# (correctly, exit 2) but embeds run B's output in its `reason` — a misleading
# failure detail and a cross-session output leak.
#
# Like check-test-gate-json.sh / check-secret-scan-paths.sh, this drives the
# REAL hook and runs a built-in self-test first to prove the detector isn't
# trivially always-pass: it must reject a known cross-contaminated reason and
# accept a clean (own-output) one.
#
# The race is made DETERMINISTIC with a barrier: run A's TEST_CMD prints its own
# marker, then blocks on a FIFO until run B has fully completed (and thus
# clobbered the shared output file); only then does A proceed to its tail. No
# sleeps, no flakiness — A's tail always observes B's clobber if (and only if)
# the hook shares one fixed output path.
# Deterministic, POSIX sh, deps: mktemp, mkfifo. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/test-gate.sh"
# Absolute path: runners cd into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

MARKER_A="RUN_A_OWN_FAILING_OUTPUT"
MARKER_B="RUN_B_OTHER_SESSION_PASSING_OUTPUT"

# run_block <test_cmd>: run the REAL hook with a failing TEST_CMD in its own temp
# repo and echo its stdout (the structured block decision). Returns the hook's
# exit code. Sourced config never leaks: the hook runs in its own `sh` subprocess.
run_block() {
  tcmd="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 99; }
  mkdir -p "$td/.agent"
  printf 'TEST_CMD=%s\n' "'$tcmd'" > "$td/.agent/guardrails.conf"
  ( cd "$td" && echo '{}' | sh "$HOOK" 2>/dev/null )
  rc=$?
  rm -rf "$td"
  return "$rc"
}

# reason_of <block-json>: extract the `reason` string from the hook's JSON block
# decision (the field a consumer reads back). Pure python3 — the single oracle.
reason_of() {
  python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("reason",""))' 2>/dev/null
}

# --- self-test (proves the contamination detector isn't trivially always-pass) -----------
self_test() {
  st_fail=0
  # (a) a reason that contains the OTHER session's marker is contaminated -> must be flagged.
  if printf 'Last output:\n%s\n' "$MARKER_B" | grep -q "$MARKER_B"; then
    : # ok, detector sees the foreign marker
  else
    echo "  FAIL self-test: cannot detect a foreign marker in a reason (oracle is broken)"; st_fail=1
  fi
  # (b) a reason that contains ONLY this run's own marker is clean -> must NOT be flagged.
  if printf 'Last output:\n%s\n' "$MARKER_A" | grep -q "$MARKER_B"; then
    echo "  FAIL self-test: flagged a clean own-output reason (oracle too strict)"; st_fail=1
  fi
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the contamination oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (foreign marker detected; clean own-output not flagged)"
}

echo "Checking test-gate isolates each run's output (no cross-session reason contamination): $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
command -v mkfifo >/dev/null 2>&1 || { echo "FAIL — mkfifo required for the deterministic race"; exit 1; }
self_test

# --- real check: drive a DETERMINISTIC race against the REAL hook -------------------------
# Barrier dir holds two FIFOs:
#   a_wrote  — A signals it has written its marker to the shared output file.
#   b_done   — B (driven from this shell) signals it has finished (and clobbered).
# A's TEST_CMD: print own marker (-> hook writes it to the shared file), open
# a_wrote (releasing us), then read b_done (block until B has clobbered), then
# `false` (fail the gate). A's hook then tails the shared file — which now holds
# B's output iff the path is shared. If the hook used a per-run path, A's tail
# still sees A's own marker and the reason is clean.
barrier=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
mkfifo "$barrier/a_wrote" "$barrier/b_done" 2>/dev/null || { echo "FAIL — mkfifo failed"; rm -rf "$barrier"; exit 1; }

A_CMD="printf '%s\\n' '$MARKER_A'; : > '$barrier/a_wrote'; cat '$barrier/b_done' >/dev/null; false"
B_CMD="printf '%s\\n' '$MARKER_B'; true"

# Launch A in the background; capture its block JSON to a file.
outA="$barrier/outA.json"
( run_block "$A_CMD" > "$outA"; echo "$?" > "$barrier/rcA" ) &
apid=$!

# Wait for A to announce it has written its marker (open-for-read blocks until A opens-for-write).
cat "$barrier/a_wrote" >/dev/null

# Now run B to completion. B passes (exit 0) and clobbers the shared output path.
run_block "$B_CMD" >/dev/null; rcB=$?

# Release A so it proceeds to its tail + block-decision emission.
: > "$barrier/b_done"
wait "$apid"

rcA=$(cat "$barrier/rcA" 2>/dev/null)
reasonA=$(reason_of < "$outA")

# A must still BLOCK (its own tests failed) — the decision is expected to stay correct.
if [ "${rcA:-X}" = "2" ]; then
  echo "  ok   run A still blocks its own stop (exit 2)"
else
  echo "  FAIL run A did not block (exit ${rcA:-?}, expected 2) — gate decision wrong"
  fail=1
fi
# B is just the racing companion; note its result for the record.
echo "  ..   run B (other session) exited $rcB (passing companion that clobbers the shared file)"

# The CONTAMINATION assertion: A's reason must carry A's OWN output, not B's.
if printf '%s' "$reasonA" | grep -q "$MARKER_B"; then
  echo "  FAIL run A's reason embeds the OTHER session's output ($MARKER_B) — cross-session contamination"
  fail=1
elif printf '%s' "$reasonA" | grep -q "$MARKER_A"; then
  echo "  ok   run A's reason carries its own output ($MARKER_A)"
else
  echo "  FAIL run A's reason carries NEITHER marker — unexpected:"
  printf '%s\n' "$reasonA" | sed 's/^/         /'
  fail=1
fi

rm -rf "$barrier"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — test-gate isolates each run's output; no cross-session reason contamination."
else
  echo "FAIL — .agent/hooks/test-gate.sh writes and tails the FIXED host-wide path /tmp/test-gate.out (lines 24, 30) with no per-run \$\$/mktemp token, so a concurrent stop overwrites the shared file and run A's block reason reports another session's test output instead of its own."
fi
exit "$fail"
