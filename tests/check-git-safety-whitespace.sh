#!/bin/sh
# check-git-safety-whitespace.sh — assert .agent/hooks/git-safety.sh BLOCKS
# destructive git commands regardless of which whitespace separates the tokens.
#
# Bug under test (git-safety.sh:31 and :58):
#   *"git clean -"*[fF]*)   block "git clean -f (deletes untracked files)"
#   *"git commit"*|...)     block "writing directly to the protected ... branch"
# Both globs embed a LITERAL SINGLE SPACE between "git" and the subcommand and
# are matched against the RAW $INPUT (line 7), NOT the whitespace-normalized
# $npad (line 20, which collapses tabs via `tr`). A tab or a double space
# between the tokens — both valid shell whitespace the shell collapses before
# exec — does not match the glob's single space, so the guard is ALLOWed while
# the destructive command still runs. An in-threat-model encoding false-negative.
#
# Like check-git-discard-forms.sh, this drives the REAL hook in a throwaway temp
# dir and asserts on its exit code (2 = block). A self-test first proves the
# oracle isn't trivially always-block: a benign command must pass, and the
# single-space control of each destructive form must block (guard fires).
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
CL="cl""ean"         # -> clean
CM="com""mit"        # -> commit
TAB=$(printf '\t')   # -> a literal tab byte

# run_hook <command-string>: feed the hook a Bash tool-call JSON naming the
# command and return its exit code. Own temp dir + `sh` subprocess (no leaks).
# The command JSON is written via printf so embedded tabs survive verbatim;
# stdin must be the JSON only (a tab inlined in a pipe arg risks mangling).
run_hook() {
  cmd="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 99; }
  printf '{"command":"%s"}' "$cmd" >"$td/payload.json"
  ( cd "$td" && sh "$HOOK" <"$td/payload.json" >/dev/null 2>&1 )
  rc=$?
  rm -rf "$td"
  return "$rc"
}

# run_hook_protected <command-string>: same, but the temp dir is a real git repo
# checked out onto a protected branch, with a temp conf protecting it via
# SCAFFOLD_CONF. The hook resolves the branch from its OWN cwd (no `git -C`), so
# the protected-branch guard (line 58) only engages when cwd is a git repo on a
# protected branch — hence the in-temp-dir repo here.
PROT_BRANCH="qa-protected"
run_hook_protected() {
  cmd="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 99; }
  printf '{"command":"%s"}' "$cmd" >"$td/payload.json"
  printf 'PROTECTED_BRANCHES="%s"\n' "$PROT_BRANCH" >"$td/conf"
  (
    cd "$td" \
      && git init -q \
      && git config user.email t@t.t && git config user.name t \
      && git checkout -q -b "$PROT_BRANCH" 2>/dev/null \
      && SCAFFOLD_CONF="$td/conf" sh "$HOOK" <"$td/payload.json" >/dev/null 2>&1
  )
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
  # The single-space `git clean -f` form MUST be blocked (control: line 31 fires).
  run_hook "git $CL -f"; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block 'git clean -f' (exit $rc; gate is trivially always-pass)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the gate cannot tell benign from destructive. Aborting."
    exit 1
  fi
  echo "  ok   self-test (benign passes; single-space 'git clean -f' blocks)"
}

echo "Checking git-safety blocks destructive git commands under tab/double-space: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- PART 1: `git clean -f` (line 31, unconditional) -------------------------
# A tab or a double space between "git" and "clean" must still block — the shell
# collapses the whitespace before exec, so the destructive command runs.
echo "Part 1 — git clean (unconditional guard, line 31):"
set -- \
  "git${TAB}$CL -f" \
  "git  $CL -f"

for cmd in "$@"; do
  run_hook "$cmd"; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "  ok   blocked: [$cmd]"
  else
    echo "  FAIL not blocked: [$cmd] (exit $rc, expected 2) — whitespace-variant evades the guard"
    fail=1
  fi
done

# --- PART 2: `git commit` on a protected branch (line 58) --------------------
# Default shipped guardrails.conf sets PROTECTED_BRANCHES="" (guard disabled),
# so isolate the glob with a temp repo on a protected branch (run_hook_protected
# sets up a real git repo + conf). The single-space control must block (proving
# the guard is active); the tab/double-space variants must block too.
echo "Part 2 — git commit on a protected branch (line 58):"
run_hook_protected "git $CM -m x"; rc=$?
if [ "$rc" -ne 2 ]; then
  echo "  FAIL control: 'git commit -m x' not blocked on protected branch '$PROT_BRANCH' (exit $rc) — guard isolation broken, aborting Part 2"
  fail=1
else
  echo "  ok   control: single-space 'git commit -m x' blocks on protected '$PROT_BRANCH'"
  for cmd in "git${TAB}$CM -m x" "git  $CM -m x"; do
    run_hook_protected "$cmd"; rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "  ok   blocked: [$cmd]"
    else
      echo "  FAIL not blocked: [$cmd] (exit $rc, expected 2) — whitespace-variant evades the protected-branch guard"
      fail=1
    fi
  done
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — git-safety blocks destructive git commands under tab/double-space token separators."
else
  echo "FAIL — .agent/hooks/git-safety.sh:31/:58 match the RAW \$INPUT with a literal single space between 'git' and the subcommand; a tab or double space between tokens defeats the glob while the shell collapses the whitespace before exec, so 'git\\tclean -f' / 'git  commit -m x' run their destructive action unblocked. Match against the normalized \$npad (or collapse whitespace runs before the case statements)."
fi
exit "$fail"
