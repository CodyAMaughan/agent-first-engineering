#!/bin/sh
# secret-scan.sh — block the agent from reading or committing secrets.
# Bind to canonical `tool.pre` (Claude `PreToolUse` Read/Bash; Cursor `beforeReadFile`/`beforeShellExecution`).
# Deterministic, NO LLM. Reads the tool-call JSON on stdin; exit 2 = block (Cursor needs failClosed:true).

set -u
INPUT=$(cat 2>/dev/null || true)

# Secret-ish path patterns (files the agent should never read/commit by default).
PATTERN='\.env($|\.|[^a-zA-Z])|\.pem|\.key($|[^a-zA-Z])|id_rsa|id_ed25519|credentials|\.pfx|\.p12|secrets?\.(ya?ml|json|toml)|\.aws/credentials|service-account.*\.json'

block() {
  reason="secret-scan: blocked — this action touches a likely secret ($1). Read it manually if truly needed, or add an explicit allow."
  printf '{"decision":"block","reason":"%s"}\n' "$reason"
  echo "$reason" >&2
  exit 2
}

# Match a secret path anywhere in the tool input (covers Read targets and Bash commands like cat/git add).
hit=$(printf '%s' "$INPUT" | grep -niE "$PATTERN" | head -1 || true)
[ -n "$hit" ] && block "$hit"

exit 0
