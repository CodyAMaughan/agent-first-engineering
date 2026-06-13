#!/bin/sh
# test-gate.sh — refuse to "finish" until the project's tests pass.
# Bind to canonical `turn.stop` (Claude `Stop`, Codex `Stop`, Cursor `stop`).
# Configure the test command via .agent/guardrails.conf:  TEST_CMD="npm test"
#
# Protocol: exit 0 = allow stop; exit 2 = block stop and feed `reason` back to the agent.
# (Claude/Codex honor exit 2 to block; Cursor needs failClosed:true on this hook.)

set -u

CONF="${SCAFFOLD_CONF:-.agent/guardrails.conf}"
TEST_CMD=""
TEST_TIMEOUT=""
[ -f "$CONF" ] && . "$CONF" 2>/dev/null || true

# How long any single TEST_CMD run may take before the gate reaps it. An
# unbounded run would block this hook — and the Stop event it is bound to — for
# the command's full duration, so a hung or pathologically slow suite would
# wedge the agent forever. Configurable (TEST_TIMEOUT in $CONF) for slow real
# suites; the default is a conservative ceiling.
TIMEOUT_SECS="${TEST_TIMEOUT:-15}"

# run_bounded <cmd...>: run a command but kill it after $TIMEOUT_SECS. Returns
# the command's own exit status on completion, or 124 (timeout convention) if it
# was reaped. Prefers GNU `timeout`/`gtimeout`; falls back to a portable perl
# alarm wrapper (perl is on every macOS / Linux) so the bound holds even where
# coreutils `timeout` is absent.
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECS" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT_SECS" "$@"
  else
    perl -e '
      my $t = shift;
      my $pid = fork();
      if (!defined $pid) { exit 127; }
      if ($pid == 0) { exec @ARGV or exit 127; }
      $SIG{ALRM} = sub { kill("TERM", $pid); sleep 2; kill("KILL", $pid); exit 124; };
      alarm $t;
      waitpid($pid, 0);
      my $rc = $?;
      alarm 0;
      exit($rc & 127 ? 128 + ($rc & 127) : $rc >> 8);
    ' "$TIMEOUT_SECS" "$@"
  fi
}

# Drain the stdin event.
cat >/dev/null 2>&1 || true

# No test command configured -> don't block (warn once to stderr).
if [ -z "${TEST_CMD:-}" ]; then
  echo "test-gate: no TEST_CMD configured in $CONF; skipping." >&2
  exit 0
fi

# Per-run output file (mktemp + PID): a concurrent stop must not clobber the
# file this run tails to build its `reason`, or it would leak another session's
# output. Fall back to a PID-suffixed path if mktemp is unavailable.
OUT=$(mktemp "${TMPDIR:-/tmp}/test-gate.$$.XXXXXX" 2>/dev/null) || OUT="/tmp/test-gate.$$.out"
trap 'rm -f "$OUT"' EXIT

# Bound the run: an unbounded `sh -c "$TEST_CMD"` would block this hook (and the
# Stop turn) for the command's full duration, so a hung/slow suite is reaped at
# $TIMEOUT_SECS and treated as a failure (block with a reason) rather than hanging.
run_bounded sh -c "$TEST_CMD" >"$OUT" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
  exit 0
fi

# Tests failed (or timed out) -> block the stop and tell the agent why.
if [ "$RC" -eq 124 ]; then
  REASON="Tests timed out after ${TIMEOUT_SECS}s — do not finish yet. The suite (\`$TEST_CMD\`) did not complete within the gate's budget; it may be hung or too slow. Speed it up or raise TEST_TIMEOUT in $CONF, then re-run. Last output:
$(tail -n 30 "$OUT" 2>/dev/null)"
else
  REASON="Tests are failing — do not finish yet. Fix them and re-run \`$TEST_CMD\`. Last output:
$(tail -n 30 "$OUT" 2>/dev/null)"
fi

# JSON form (Claude/Codex): a structured block decision.
# Encode REASON as a proper JSON string: escape backslash and quote, give TAB/CR/
# LF their short escapes, and — critically — turn EVERY OTHER C0 control char
# (0x00-0x08, 0x0b, 0x0c, 0x0e-0x1f) into a \uXXXX escape. RFC 8259 forbids any
# unescaped U+0000–U+001F inside a string, and REASON is built from the TEST_CMD's
# own output (tail of $OUT) — attacker/agent-influenceable — so a raw control byte
# would otherwise leak in and a JSON-only consumer could not json.loads() the
# block decision. perl slurps the whole reason (-0777) so no line-splitting can
# drop a byte; it is already required on every macOS/Linux (see run_bounded).
ESCAPED=$(printf '%s' "$REASON" | perl -0777 -pe '
  s/([\x00-\x1f"\\])/
    my $o = ord($1);
    $o == 0x5c ? "\\\\" :
    $o == 0x22 ? "\\\"" :
    $o == 0x08 ? "\\b"  :
    $o == 0x09 ? "\\t"  :
    $o == 0x0a ? "\\n"  :
    $o == 0x0c ? "\\f"  :
    $o == 0x0d ? "\\r"  :
    sprintf("\\u%04x", $o)
  /ge')
printf '{"decision":"block","reason":"%s"}\n' "$ESCAPED"
exit 2
