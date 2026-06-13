#!/bin/sh
# check-test-gate-json.sh — assert .agent/hooks/test-gate.sh emits a PARSEABLE
# structured block decision when tests fail. The hook's documented protocol
# (test-gate.sh lines 6-7, 32) feeds a JSON `{"decision":"block","reason":...}`
# back to the agent; a consumer that reads the structured verdict (not just the
# exit code) must be able to json.loads() it. A malformed payload silently loses
# the block reason — a false-gate / structured-output robustness bug.
#
# Like check-qa-manifest.sh, this runs a built-in self-test first to prove the
# detector isn't trivially always-pass: it must reject a known-bad payload
# (bare unquoted reason / raw TAB) and accept a known-good one.
# Deterministic, POSIX sh, deps: mktemp, python3. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/test-gate.sh"
# Absolute path: run_hook_block cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# is_valid_json: reads stdin, exits 0 iff it parses as JSON. The single oracle.
is_valid_json() {
  python3 -c 'import sys,json; json.loads(sys.stdin.read())' 2>/dev/null
}

# run_hook_block <test_cmd>: run the REAL hook with a failing TEST_CMD in a temp
# repo and echo its stdout (the structured block decision). Sourced config never
# leaks: the hook runs in its own `sh` subprocess.
run_hook_block() {
  tcmd="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 1; }
  mkdir -p "$td/.agent"
  printf 'TEST_CMD=%s\n' "'$tcmd'" > "$td/.agent/guardrails.conf"
  ( cd "$td" && echo '{}' | sh "$HOOK" 2>/dev/null )
  rc=$?
  rm -rf "$td"
  return "$rc"
}

# --- self-test (proves the detector catches a known-malformed payload) --------------------
self_test() {
  st_fail=0
  # (a) a bare, unquoted reason (the exact shape of the bug) must be REJECTED.
  printf '{"decision":"block","reason":Tests are failing}\n' | is_valid_json \
    && { echo "  FAIL self-test: accepted a bare unquoted reason (oracle is broken)"; st_fail=1; }
  # (b) a quoted reason carrying a raw TAB control char must be REJECTED.
  printf '{"decision":"block","reason":"col1\tcol2"}\n' | is_valid_json \
    && { echo "  FAIL self-test: accepted a raw TAB inside a JSON string (oracle is broken)"; st_fail=1; }
  # (c) a well-formed block decision must be ACCEPTED (no false positive).
  printf '{"decision":"block","reason":"Tests are failing\\ncol1\\tcol2\\n"}\n' | is_valid_json \
    || { echo "  FAIL self-test: rejected a valid block decision (oracle too strict)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the JSON oracle cannot tell good from bad. Aborting."
    exit 1
  fi
  echo "  ok   self-test (bare reason + raw TAB rejected; valid decision accepted)"
}

echo "Checking test-gate structured block decision is valid JSON: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: drive the REAL hook on a failing TEST_CMD whose output has a TAB ----------
# `printf` emits a literal TAB, then `false` fails the gate -> hook must block with JSON.
out=$(run_hook_block 'printf "col1\tcol2\n"; false'); rc=$?
if [ "$rc" -ne 2 ]; then
  echo "  FAIL hook did not block on failing tests (exit $rc, expected 2)"
  fail=1
fi
if printf '%s' "$out" | is_valid_json; then
  echo "  ok   block decision parses as valid JSON"
else
  echo "  FAIL block decision is NOT valid JSON:"
  printf '%s\n' "$out" | sed 's/^/         /'
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — test-gate emits a parseable structured block decision."
else
  echo "FAIL — .agent/hooks/test-gate.sh emits malformed JSON: the reason is unquoted and/or carries raw control chars, so a consumer reading the structured verdict gets a parse error and loses the block reason."
fi
exit "$fail"
