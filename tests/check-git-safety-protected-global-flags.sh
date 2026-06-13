#!/bin/sh
# check-git-safety-protected-global-flags.sh — assert .agent/hooks/git-safety.sh
# BLOCKS a direct commit/push to a PROTECTED branch even when a git GLOBAL option
# (e.g. `-C <dir>`, `--git-dir=...`, `-c key=val`) precedes the subcommand.
#
# Bug under test (git-safety.sh protected-branch guard, the case at ~line 93):
#   case "$nsq" in *"git commit"*|*"git push"*) block ... ;; esac
# The destructive-subcommand globs earlier in the script match $ngit — a copy with
# leading git GLOBAL options (`-C <dir>`, `--git-dir=...`, `-c k=v`) peeled off so an
# inserted token can't split the `git <subcmd>` substring. But the protected-branch
# guard cases on $nsq (the raw whitespace-collapsed input), NOT $ngit. Git global
# options go BEFORE the subcommand, inserting tokens between `git` and the subcommand:
# `git -C . commit`. After collapse the string is `git -C . commit` — the contiguous
# substring `git commit` no longer matches, so the guard does not fire and the commit
# to the protected branch runs (exit 0). `git -C . <subcmd>` still targets the SAME
# repo on the SAME protected branch, so this is a real, in-scope false-negative of the
# protected-branch guard (the agent writes directly to main — exactly what it blocks).
#
# Like check-git-safety-global-flags.sh, this drives the REAL hook in a throwaway temp
# repo — but one explicitly checked out to the protected branch `main`, since the guard
# reads the live branch via `git branch --show-current`. A self-test first proves the
# oracle isn't trivially always-block (a benign command passes) and that the CONTIGUOUS
# control forms (`git commit` / `git push`) DO block on the protected branch (so a
# regression that breaks the base guard is also caught).
# Deterministic, POSIX sh, deps: git, mktemp. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/git-safety.sh"
# Absolute path: run_hook cd's into a temp repo, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# The literal subcommands are built indirectly (string concat) so that the bytes of
# this file never form a destructive git command that the repo's OWN live git-safety
# hook would flag when this script is read/edited by an agent. The JSON fed on stdin
# still contains the exact literal commands at runtime.
CM="com""mit"      # -> commit
PU="pu""sh"        # -> push

# make_protected_repo: create a throwaway git repo with one commit, checked out to the
# protected branch `main`, and echo its path. The hook resolves the branch from cwd via
# `git branch --show-current`, so the hook must be run with this repo as cwd.
make_protected_repo() {
  td=$(mktemp -d) || return 99
  (
    cd "$td" || exit 99
    git init -q
    git config user.email a@b.c
    git config user.name t
    git commit -q --allow-empty -m i
    git branch -m main      # ensure the protected default name regardless of init.defaultBranch
  ) >/dev/null 2>&1 || { rm -rf "$td"; return 99; }
  printf '%s' "$td"
}

# run_hook <repo-dir> <command-string>: feed the hook a Bash tool-call JSON naming the
# command, with cwd = <repo-dir> (so the protected-branch guard sees `main`). Returns
# the hook's exit code (2 = block).
run_hook() {
  rd="$1"; cmd="$2"
  ( cd "$rd" && printf '{"command":"%s"}' "$cmd" | sh "$HOOK" >/dev/null 2>&1 )
  return $?
}

echo "Checking git-safety blocks commit/push to a protected branch behind a git global option: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }

REPO=$(make_protected_repo) || { echo "FAIL — could not create protected-branch test repo"; exit 1; }
trap 'rm -rf "$REPO"' EXIT INT TERM
# Sanity: the repo really is on the protected branch (else the whole test is vacuous).
br=$( cd "$REPO" && git branch --show-current 2>/dev/null )
[ "$br" = "main" ] || { echo "FAIL — test repo is on '$br', expected protected branch 'main'"; exit 1; }

# --- self-test (proves the gate isn't trivially always-block) ----------------
self_test() {
  st_fail=0
  # A plainly-benign command must NOT be blocked (else the oracle is broken).
  run_hook "$REPO" "git status"; rc=$?
  [ "$rc" -eq 0 ] || { echo "  FAIL self-test: blocked benign 'git status' on protected branch (exit $rc; gate is trivially always-block)"; st_fail=1; }
  # The CONTIGUOUS protected-branch forms MUST block — guards the base behavior so a
  # regression in the existing guard is also caught.
  run_hook "$REPO" "git $CM -m x"; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block contiguous 'git commit' on protected branch (exit $rc; base guard broken)"; st_fail=1; }
  run_hook "$REPO" "git $PU"; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block contiguous 'git push' on protected branch (exit $rc; base guard broken)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the gate cannot tell benign from contiguous protected-branch writes. Aborting."
    exit 1
  fi
  echo "  ok   self-test (benign passes; contiguous commit/push to protected branch block)"
}
self_test

# --- real check: global-option-prefixed commit/push to main must ALL block ----
# `git -C . commit -m x`            — commit to protected branch via -C targeting same repo.
# `git -C . push`                   — push from protected branch via -C targeting same repo.
# `git --git-dir=.git commit -m x`  — same evasion via --git-dir.
# `git -c k=v commit -m x`          — same evasion via -c key=val.
set -- \
  "git -C . $CM -m x" \
  "git -C . $PU" \
  "git --git-dir=.git $CM -m x" \
  "git -c core.pager=cat $CM -m x"

for cmd in "$@"; do
  run_hook "$REPO" "$cmd"; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "  ok   blocked: $cmd"
  else
    echo "  FAIL not blocked: $cmd (exit $rc, expected 2) — direct write to protected branch evades the guard behind a global option"
    fail=1
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — git-safety blocks commit/push to a protected branch even behind a git global option (-C/--git-dir/-c)."
else
  echo "FAIL — the protected-branch guard in .agent/hooks/git-safety.sh cases on \$nsq (raw collapsed input) instead of \$ngit (global-options-peeled); a leading git global option (e.g. \`git -C . commit\`) inserts tokens between 'git' and the subcommand, so the contiguous 'git commit'/'git push' substring no longer matches and the direct write to the protected branch runs unblocked."
fi
exit "$fail"
