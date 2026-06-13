#!/bin/sh
# check-test-gate-control-chars.sh — assert .agent/hooks/test-gate.sh emits a
# PARSEABLE structured block decision even when the failing test's output contains
# a raw C0 control byte (e.g. 0x01).
#
# Bug under test (test-gate.sh:88-90): the `reason` is JSON-escaped with
#   sed 's/\\/\\\\/g; s/"/\\"/g; s/<TAB>/\\t/g; s/\r/\\r/g; s/$/\\n/' | tr -d '\n\r'
# which escapes ONLY backslash, double-quote, TAB (0x09), CR (0x0d) and the
# line-ending newline. Every other C0 control char (0x00-0x08, 0x0b, 0x0c,
# 0x0e-0x1f) passes through RAW into the double-quoted JSON string value — which is
# invalid JSON (RFC 8259 forbids unescaped U+0000–U+001F inside a string).
#
# The `reason` body is built from `tail -n 30 "$OUT"` (test-gate.sh:79), i.e. the
# TEST_CMD's own stdout/stderr — agent/attacker-influenceable content. The hook
# documents (line 82) that this JSON IS the structured block decision for
# Claude/Codex; a JSON-only consumer (Cursor-style) that parses the decision to
# honor the block hits `json.loads()` -> "Invalid control character" and loses the
# block `reason` (a strict parser may discard the whole decision). The exit-2
# channel still fires, so impact is bounded to JSON consumers — medium severity.
#
# This is a DISTINCT gap from check-test-gate-json.sh, which only exercises TAB
# (0x09) — a char the sed already handles. A raw 0x01 slips through that test.
#
# Like check-test-gate-json.sh, this runs a built-in self-test first to prove the
# JSON oracle isn't trivially always-pass: it must REJECT a payload carrying a raw
# 0x01 and ACCEPT a well-formed one.
# Deterministic, POSIX sh, deps: mktemp, python3, printf. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/test-gate.sh"
# Absolute path: run_hook_block cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# is_valid_json: reads stdin, exits 0 iff it parses as JSON (strict — the default
# json.loads rejects raw U+0000–U+001F control chars inside strings). The oracle.
is_valid_json() {
  python3 -c 'import sys,json; json.loads(sys.stdin.read())' 2>/dev/null
}

# A literal SOH (0x01) byte — the canonical "every other C0 control char" the
# escaper misses. Used to build the failing-test output and the self-test payload.
SOH=$(printf '\001')

# run_hook_block <test_cmd>: run the REAL hook with a failing TEST_CMD in a temp
# repo and echo its stdout (the structured block decision). Sourced config never
# leaks: the hook runs in its own `sh` subprocess. Returns the hook's exit status.
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

# --- self-test (proves the oracle catches a raw control char) -------------------------------
self_test() {
  st_fail=0
  # (a) a quoted reason carrying a RAW 0x01 control char must be REJECTED.
  printf '{"decision":"block","reason":"a%sb"}\n' "$SOH" | is_valid_json \
    && { echo "  FAIL self-test: accepted a raw 0x01 inside a JSON string (oracle is broken)"; st_fail=1; }
  # (b) the same byte PROPERLY escaped () must be ACCEPTED (no false positive).
  printf '{"decision":"block","reason":"a\\u0001b"}\n' | is_valid_json \
    || { echo "  FAIL self-test: rejected a valid \\u0001 escape (oracle too strict)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the JSON control-char oracle cannot tell good from bad. Aborting."
    exit 1
  fi
  echo "  ok   self-test (raw 0x01 rejected; \\u0001 escape accepted)"
}

echo "Checking test-gate JSON survives a raw C0 control char in test output: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: drive the REAL hook on a failing TEST_CMD that emits a raw 0x01 ------------
# `printf 'a\001b'` emits a literal SOH byte, then `false` fails the gate -> the hook
# must block with a JSON decision a consumer can json.loads().
out=$(run_hook_block 'printf "a\001b"; false'); rc=$?
if [ "$rc" -ne 2 ]; then
  echo "  FAIL hook did not block on failing tests (exit $rc, expected 2)"
  fail=1
fi
if printf '%s' "$out" | is_valid_json; then
  echo "  ok   block decision parses as valid JSON despite the raw control char"
else
  echo "  FAIL block decision is NOT valid JSON (raw control char leaked into the string):"
  printf '%s\n' "$out" | sed 's/^/         /'
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — test-gate escapes raw C0 control chars; the structured block decision stays parseable."
else
  echo "FAIL — .agent/hooks/test-gate.sh (lines 88-90) escapes only \\, \", TAB, CR and the trailing newline; every other C0 control char (0x00-0x08, 0x0b, 0x0c, 0x0e-0x1f) passes through raw into the double-quoted JSON value, which is invalid JSON. Because the reason is built from the TEST_CMD's own output (tail of \$OUT), attacker/agent-influenced content makes the structured block decision unparseable — a JSON-only consumer loses the block reason."
fi
exit "$fail"
