#!/bin/sh
# check-secret-scan-paths.sh — assert .agent/hooks/secret-scan.sh BLOCKS the
# secret-file paths it is meant to catch, with no letter-boundary evasions.
#
# Bug under test (secret-scan.sh:10): the `\.env($|\.|[^a-zA-Z])` alternative
# demands EOL, a dot, or a NON-letter immediately after `env`. `.envrc` (a
# direnv file that routinely holds `export SECRET=...`) has the letter `r`
# after `env`, so it matches no alternative and the hook exits 0 — a secret
# file the scanner is meant to block reads cleanly. The same enumerate-only
# SSH-key list misses `id_dsa` (only id_rsa / id_ed25519 are listed).
#
# Like check-test-gate-json.sh, this drives the REAL hook in a throwaway temp
# dir and asserts on its exit code (2 = block). A self-test first proves the
# oracle isn't trivially always-block: a clearly-benign path must pass (exit 0).
# Deterministic, POSIX sh, deps: mktemp. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/secret-scan.sh"
# Absolute path: run_hook cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# run_hook <path>: feed the hook a Read tool-call JSON naming <path> and return
# its exit code. Runs in its own temp dir + `sh` subprocess (no state leaks).
run_hook() {
  p="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 99; }
  ( cd "$td" && printf '{"file_path":"%s"}' "$p" | sh "$HOOK" >/dev/null 2>&1 )
  rc=$?
  rm -rf "$td"
  return "$rc"
}

# --- self-test (proves the gate isn't trivially always-block) ----------------
self_test() {
  st_fail=0
  # A plainly-benign source path must NOT be blocked (else the oracle is broken).
  run_hook "src/main.py"; rc=$?
  [ "$rc" -eq 0 ] || { echo "  FAIL self-test: blocked a benign path src/main.py (exit $rc; gate is trivially always-block)"; st_fail=1; }
  # A canonical secret path MUST be blocked (else the oracle is broken the other way).
  run_hook ".env"; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block .env (exit $rc; gate is trivially always-pass)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the gate cannot tell secret from benign. Aborting."
    exit 1
  fi
  echo "  ok   self-test (benign path passes; .env blocks)"
}

echo "Checking secret-scan blocks secret paths without letter-boundary evasion: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: paths the scanner is documented to catch must ALL block -----
# .envrc          — direnv env/secret file (the primary evasion).
# .env.local      — control: already blocked (proves the gate works here).
# id_dsa          — DSA SSH private key (enumerate-only list misses it).
for p in ".envrc" ".env.local" "id_dsa"; do
  run_hook "$p"; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "  ok   blocked: $p"
  else
    echo "  FAIL not blocked: $p (exit $rc, expected 2) — secret file reads cleanly"
    fail=1
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — secret-scan blocks .envrc / id_dsa and friends (no letter-boundary evasion)."
else
  echo "FAIL — .agent/hooks/secret-scan.sh lets a secret file through: the \`\\.env(\$|\\.|[^a-zA-Z])\` alternative requires a non-letter after \`env\`, so \`.envrc\` (letter \`r\`) evades the gate; \`id_dsa\` is likewise absent from the enumerate-only SSH-key list."
fi
exit "$fail"
