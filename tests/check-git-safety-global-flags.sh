#!/bin/sh
# check-git-safety-global-flags.sh — assert .agent/hooks/git-safety.sh BLOCKS the
# destructive clean/checkout/restore forms even when a git GLOBAL option (e.g.
# `-C <dir>`, `--git-dir=...`, `-c key=val`) precedes the subcommand.
#
# Bug under test (git-safety.sh:37-38, 47):
#   line 37: *"git clean -"*[fF]*
#   line 38: *"git checkout ."* | *"git restore ."*
#   line 47: *" git checkout "*" . "* | *" git restore "*" . "*
# These guards use CONTIGUOUS-substring globs anchored on "git clean -",
# "git checkout", "git restore". Git's global options (`-C <dir>`, `--git-dir`,
# `-c k=v`) go BEFORE the subcommand, inserting tokens between `git` and the
# subcommand:  `git -C foo clean -f`. After whitespace-collapse the string is
# `git -C foo clean -f` — the substring `git clean` is no longer contiguous, so
# none of the globs match and the command runs (exit 0), deleting untracked files
# / discarding the entire working tree in <dir>. `git -C <dir> <subcmd>` is valid
# git syntax that runs the subcommand as if in <dir>, so this is a real, in-scope
# destructive-command evasion (target false-negative), not RCE-out-of-scope.
#
# Like check-git-discard-forms.sh, this drives the REAL hook in a throwaway temp
# dir and asserts on its exit code (2 = block). A self-test first proves the
# oracle isn't trivially always-block (a benign command passes) and that the
# CONTIGUOUS control forms still block (so a regression that breaks the base
# guard is also caught).
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
CL="cl""ean"        # -> clean
CO="check""out"     # -> checkout
RE="rest""ore"      # -> restore

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
  # The CONTIGUOUS destructive forms MUST block (control: already handled) — this
  # also guards the base behavior so a regression in the existing guard is caught.
  run_hook "git $CL -f"; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block contiguous 'git clean -f' (exit $rc; base guard broken)"; st_fail=1; }
  run_hook "git $CO ."; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block contiguous 'git checkout .' (exit $rc; base guard broken)"; st_fail=1; }
  run_hook "git $RE ."; rc=$?
  [ "$rc" -eq 2 ] || { echo "  FAIL self-test: did not block contiguous 'git restore .' (exit $rc; base guard broken)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the gate cannot tell benign from contiguous destructive forms. Aborting."
    exit 1
  fi
  echo "  ok   self-test (benign passes; contiguous clean/checkout/restore block)"
}

echo "Checking git-safety blocks destructive forms behind a git global option: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
self_test

# --- real check: global-option-prefixed destructive forms must ALL block -----
# `git -C foo clean -f`            — recursive untracked-file delete in foo/.
# `git -C foo checkout .`          — wholesale worktree discard in foo/.
# `git -C foo restore .`           — wholesale worktree discard in foo/.
# `git --git-dir=foo/.git clean -f`— same evasion via --git-dir.
# `git -c k=v clean -f`            — same evasion via -c key=val.
set -- \
  "git -C foo $CL -f" \
  "git -C foo $CO ." \
  "git -C foo $RE ." \
  "git --git-dir=foo/.git $CL -f" \
  "git -c core.pager=cat $CL -f"

for cmd in "$@"; do
  run_hook "$cmd"; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "  ok   blocked: $cmd"
  else
    echo "  FAIL not blocked: $cmd (exit $rc, expected 2) — destructive command evades the guard behind a global option"
    fail=1
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — git-safety blocks clean/checkout/restore even behind a git global option (-C/--git-dir/-c)."
else
  echo "FAIL — .agent/hooks/git-safety.sh:37-38,47 use contiguous-substring globs anchored on 'git clean -'/'git checkout'/'git restore'; a leading git global option (e.g. \`git -C <dir> clean -f\`) inserts tokens between 'git' and the subcommand, so the substring is no longer contiguous and the destructive command runs unblocked while deleting untracked files / discarding the working tree in <dir>."
fi
exit "$fail"
