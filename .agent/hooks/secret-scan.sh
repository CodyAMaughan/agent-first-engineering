#!/bin/sh
# secret-scan.sh — block the agent from reading or committing secrets.
# Bind to canonical `tool.pre` (Claude `PreToolUse` Read/Bash; Cursor `beforeReadFile`/`beforeShellExecution`).
# Deterministic, NO LLM. Reads the tool-call JSON on stdin; exit 2 = block (Cursor needs failClosed:true).

set -u
INPUT=$(cat 2>/dev/null || true)

# Secret-ish path patterns (files the agent should never read/commit by default).
PATTERN='\.env($|[^a-zA-Z])|\.envrc|\.pem|\.key($|[^a-zA-Z])|id_rsa|id_dsa|id_ecdsa|id_ed25519|credentials|\.pfx|\.p12|secrets?\.(ya?ml|json|toml)|\.aws/credentials|service-account.*\.json'

block() {
  reason="secret-scan: blocked — this action touches a likely secret ($1). Read it manually if truly needed, or add an explicit allow."
  printf '{"decision":"block","reason":"%s"}\n' "$reason"
  echo "$reason" >&2
  exit 2
}

# Defeat encoding evasions: a secret path hidden as a JSON \uXXXX escape or a
# percent-encoded byte never contains the literal pattern, so decode both forms
# to their actual bytes before matching (e.g. .env, %2eenv, and .env ->
# .env; id_rsa -> id_rsa). Decode EVERY hex byte, not just %2e/%2f —
# a letter escape like i ('i') must round-trip too or it evades the scan.
DECODED=$(printf '%s' "$INPUT" | perl -pe 's/\\u00([0-9a-fA-F]{2})/chr(hex($1))/ge; s/%([0-9a-fA-F]{2})/chr(hex($1))/ge')

# Match a secret path anywhere in the tool input (covers Read targets and Bash commands like cat/git add).
# Scan both the raw and the decoded bytes so encoded representations can't slip past.
hit=$(printf '%s\n%s' "$INPUT" "$DECODED" | grep -niE "$PATTERN" | head -1 || true)
[ -n "$hit" ] && block "$hit"

exit 0
