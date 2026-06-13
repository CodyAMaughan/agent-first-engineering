#!/bin/sh
# check-test-gate-timeout.sh — assert .agent/hooks/test-gate.sh BOUNDS the
# runtime of TEST_CMD so a hung or pathologically slow test suite cannot wedge
# the Stop turn forever.
#
# Bug under test (test-gate.sh:30): the hook runs the configured suite with a
# bare `sh -c "$TEST_CMD"` — no `timeout`, no `ulimit -t`, no wrapper of any
# kind. A non-terminating or very slow TEST_CMD (a realistic misconfigured or
# hung suite — no malice required) therefore blocks the hook, and thus the Stop
# event it is bound to, for the FULL duration of the command. The agent can
# never finish. The Stop hook registration in .claude/settings.json sets no
# per-hook timeout either, so nothing upstream rescues it.
#
# Expected behavior (what the fix must deliver): the gate caps each run at a
# bounded budget (e.g. wraps the command in `timeout <N>`), and treats a
# timeout as a TEST FAILURE — it blocks the stop (exit 2) with a reason so the
# agent is unblocked and told why, rather than hanging.
#
# Like check-test-gate-json.sh / check-test-gate-isolation.sh, this drives the
# REAL hook in a throwaway temp repo and runs a built-in self-test first to
# prove the timing oracle isn't trivially always-pass: it must accept a run
# that returns quickly and reject one that blocks past the budget.
# Deterministic-ish (wall-clock bound only), POSIX sh, deps: mktemp.
# Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/test-gate.sh"
# Absolute path: run_hook cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# The hook must bound any single run to at most BUDGET seconds. We make the
# misbehaving TEST_CMD sleep far longer than BUDGET so the two are unambiguous:
# a bounded hook returns within ~BUDGET; an unbounded hook returns only after
# the full HANG.
BUDGET=20      # generous upper bound the fixed gate is expected to enforce <= this
HANG=99999     # the pathological / non-terminating suite (effectively forever)
GRACE=10       # slack for process spin-up + JSON emission on a loaded host

# run_hook <test_cmd>: run the REAL hook with the given TEST_CMD in its own temp
# repo. Echoes the hook's stdout; returns the hook's exit code. Sourced config
# never leaks — the hook runs in its own `sh` subprocess. To keep THIS check
# itself from hanging if the bug is present, the hook is run under our own
# wall-clock watchdog (a background killer), so a wedged hook is reaped and
# reported as a hang rather than blocking the test runner forever. The watchdog
# fires just past the allowed budget+grace: a CORRECT hook always returns before
# it; a BUGGY (unbounded) hook is reaped here and its measured runtime lands
# above the budget, which is exactly what we assert against.
WATCH_BUDGET=$((BUDGET + GRACE + 15))   # self-protection killer: just past the allowed budget
run_hook() {
  tcmd="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 99; }
  mkdir -p "$td/.agent"
  printf 'TEST_CMD=%s\n' "'$tcmd'" > "$td/.agent/guardrails.conf"
  ( cd "$td" && echo '{}' | sh "$HOOK" 2>/dev/null ) &
  hpid=$!
  # Self-protection watchdog: never let THIS test hang forever on the very bug
  # it is probing. Kill the hook subtree if it outlives WATCH_BUDGET.
  ( sleep "$WATCH_BUDGET"; kill -9 "$hpid" 2>/dev/null ) &
  wpid=$!
  wait "$hpid" 2>/dev/null
  rc=$?
  kill "$wpid" 2>/dev/null
  wait "$wpid" 2>/dev/null
  rm -rf "$td"
  return "$rc"
}

# elapsed_of <test_cmd>: run the hook and print the wall-clock seconds it took.
elapsed_of() {
  s=$(date +%s)
  run_hook "$1" >/dev/null 2>&1
  e=$(date +%s)
  echo $((e - s))
}

# --- self-test (proves the timing oracle isn't trivially always-pass) ---------------------
self_test() {
  st_fail=0
  budget="$((BUDGET + GRACE))"
  # (a) a value at/under budget is acceptable -> must NOT be flagged.
  if [ "5" -gt "$budget" ]; then
    echo "  FAIL self-test: flagged an in-budget runtime as a hang (oracle too strict)"; st_fail=1
  fi
  # (b) a value far over budget is a hang -> must be flagged.
  if [ "$((budget + 1000))" -le "$budget" ]; then
    echo "  FAIL self-test: did not flag an over-budget runtime as a hang (oracle is broken)"; st_fail=1
  fi
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the timing oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (in-budget runtime accepted; over-budget runtime flagged as a hang)"
}

echo "Checking test-gate bounds TEST_CMD runtime (a hung suite cannot wedge Stop): $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: drive the REAL hook on a pathologically slow TEST_CMD --------------------
# A bounded gate returns within ~BUDGET and BLOCKS (exit 2) on the timeout; an
# unbounded gate blocks for the full HANG (reaped at WATCH_BUDGET by our killer).
echo "  ..   running the real hook with TEST_CMD='sleep $HANG' (budget ${BUDGET}s, grace ${GRACE}s)"
secs=$(elapsed_of "sleep $HANG")
limit=$((BUDGET + GRACE))
if [ "$secs" -le "$limit" ]; then
  echo "  ok   hook returned in ${secs}s (<= ${limit}s) — runtime is bounded"
else
  echo "  FAIL hook ran ${secs}s for a 'sleep $HANG' TEST_CMD (> ${limit}s budget) — runtime is UNBOUNDED; a hung suite wedges the Stop turn"
  fail=1
fi

# When the gate trips its timeout it must BLOCK the stop (treat timeout as a
# failure) so the agent is unblocked WITH a reason — not silently allowed.
# Only meaningful once we know the runtime IS bounded: if it is not (fail=1),
# re-running the hung command would just block for the full budget again with
# no new signal, so skip it.
if [ "$fail" -eq 0 ]; then
  run_hook "sleep $HANG" >/dev/null; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "  ok   timeout is treated as a test failure (exit 2 blocks the stop with a reason)"
  else
    echo "  FAIL on timeout the hook exited $rc (expected 2 = block); a timed-out suite must block, not silently allow stop"
    fail=1
  fi
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — test-gate bounds TEST_CMD runtime and blocks on timeout; a hung suite cannot wedge Stop."
else
  echo "FAIL — .agent/hooks/test-gate.sh runs \`sh -c \"\$TEST_CMD\"\` (line 30) with no timeout/ulimit wrapper, so a non-terminating or pathologically slow TEST_CMD blocks the hook — and the Stop turn it is bound to — for the command's full duration, wedging the agent. Wrap the run in \`timeout <N>\` (with a perl/busybox fallback) and treat a timeout as a test failure (exit 2)."
fi
exit "$fail"
