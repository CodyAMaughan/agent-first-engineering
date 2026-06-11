#!/bin/sh
# format.sh — run the project's formatter/linter after an edit (non-blocking cleanup).
# Bind to canonical `tool.post` (Claude `PostToolUse` Edit|Write; Cursor `afterFileEdit`).
# Configure in .agent/guardrails.conf:  FORMAT_CMD="pnpm lint --fix"
# Deterministic, NO LLM. Always exits 0 (formatting is a convenience, not a gate).

set -u
CONF="${SCAFFOLD_CONF:-.agent/guardrails.conf}"
FORMAT_CMD=""
[ -f "$CONF" ] && . "$CONF" 2>/dev/null || true
cat >/dev/null 2>&1 || true            # drain the event

[ -n "${FORMAT_CMD:-}" ] || exit 0     # nothing configured -> no-op
sh -c "$FORMAT_CMD" >/dev/null 2>&1 || true
exit 0
