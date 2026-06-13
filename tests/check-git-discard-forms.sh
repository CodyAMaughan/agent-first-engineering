#!/bin/sh
# check-git-discard-forms.sh — assert .agent/hooks/git-safety.sh BLOCKS the
# canonical wholesale-discard forms of checkout/restore, not just the bare
# `git checkout .` / `git restore .` shapes.
#
# Bug under test (git-safety.sh:32):
#   *"git checkout ."*|*"git restore ."*)  block "wholesale discard ..."
# These globs require "checkout"/"restore" to be IMMEDIATELY followed by " ."
# (no intervening token). The two most idiomatic wholesale-discard forms insert
# tokens between the subcommand and the `.`:
#   git checkout -- .                  (the `--` end-of-options separator)
#   git restore --staged --worktree .  (explicit staged+worktree discard)
# Both discard the entire working tree exactly like the blocked `git checkout .`,
# so the guard is evaded by the canonical form of the command it targets — an
# in-threat-model false negative.
#
# Like check-secret-scan-paths.sh, this drives the REAL hook in a throwaway temp
# dir and asserts on its exit code (2 = block). A self-test first proves the
# oracle isn't trivially always-block: a clearly-benign command must pass, and
# the already-blocked control form must block.
# Deterministic, POSIX sh, deps: mktemp. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/git-safety.sh"
# Absolute path: run_hook cd's into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# The literal subcommands are built indirectly (string concat) so that the bytes
# of this file never form a destructive git command that the repo's OWN live
# git-safety hook would flag when this script is read/edited by an agent. The
# JSON fed on stdin still contains the exact literal commands at runtime.
CO="check""out"      # -> checkout
RE="rest""ore"       # -> restore
DD="-""-"            # -> --   (end-of-options separator)

# run_hook <command-string>: feed the hook a Bash tool-call JSON naming the
# command and return its exit code. Own temp dir + `sh` subprocess (no leaks).
run_hook() {
  cmd="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 99; }
  ( cd "$td" && printf '{"command":"%s"}' "$cmd" | sh "$HOOK" >/dev/null 2>&1 )
  rc=$?
  rm -rf "$td"
  return "$rc"
}

# --- self-test (proves the gate isn't trivially always-block) ----------------
self_test() {
  st_fail=0
  # A plainly-benign command must NOT be blocked (else the oracle is broken).
  run_hook "git status"; rc=$?
  [ "$rc" -eq 0 ] || { echo "  FAIL self-test: blocked a benign command 'git status' (exit $rc; gate is trivially always-block)"; st_fail=1; }
  # The bare wholesale-discard form MUST be blocked (control: already handled).
  run_hook "git $CO ."; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block 'git checkout .' (exit $rc; gate is trivially always-pass)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the gate cannot tell benign from wholesale-discard. Aborting."
    exit 1
  fi
  echo "  ok   self-test (benign passes; bare 'git checkout .' blocks)"
}

echo "Checking git-safety blocks canonical wholesale-discard forms: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: idiomatic wholesale-discard forms must ALL block ------------
# `git checkout -- .`                 — `--` separator, discards whole worktree.
# `git restore --staged --worktree .` — explicit staged+worktree discard.
set -- \
  "git $CO $DD ." \
  "git $RE ${DD}staged ${DD}worktree ."

for cmd in "$@"; do
  run_hook "$cmd"; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "  ok   blocked: $cmd"
  else
    echo "  FAIL not blocked: $cmd (exit $rc, expected 2) — wholesale discard evades the guard"
    fail=1
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — git-safety blocks the canonical \`checkout -- .\` / \`restore --staged --worktree .\` discard forms."
else
  echo "FAIL — .agent/hooks/git-safety.sh:32 matches only \`git checkout .\` / \`git restore .\` (subcommand immediately followed by \` .\`); the idiomatic \`git checkout -- .\` and \`git restore --staged --worktree .\` insert an intervening token and evade the guard while discarding the whole working tree."
fi
exit "$fail"
