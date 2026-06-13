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
[ -f "$CONF" ] && . "$CONF" 2>/dev/null || true

# Drain the stdin event.
cat >/dev/null 2>&1 || true

# No test command configured -> don't block (warn once to stderr).
if [ -z "${TEST_CMD:-}" ]; then
  echo "test-gate: no TEST_CMD configured in $CONF; skipping." >&2
  exit 0
fi

if sh -c "$TEST_CMD" >/tmp/test-gate.out 2>&1; then
  exit 0
fi

# Tests failed -> block the stop and tell the agent why.
REASON="Tests are failing — do not finish yet. Fix them and re-run \`$TEST_CMD\`. Last output:
$(tail -n 30 /tmp/test-gate.out 2>/dev/null)"

# JSON form (Claude/Codex): a structured block decision.
# Encode REASON as a proper JSON string: escape backslashes and quotes, turn
# control chars (TAB, CR, and the line-ending newlines) into their \uXXXX-free
# short escapes, then wrap the result in double quotes. Without the quotes and
# control-char escaping a TAB or unquoted value yields a payload a consumer
# can't json.loads() — losing the block reason.
ESCAPED=$(printf '%s' "$REASON" \
  | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g; s/\r/\\r/g; s/$/\\n/' \
  | tr -d '\n\r')
printf '{"decision":"block","reason":"%s"}\n' "$ESCAPED"
exit 2
