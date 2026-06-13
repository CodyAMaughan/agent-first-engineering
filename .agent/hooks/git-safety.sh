#!/bin/sh
# git-safety.sh — block dangerous shell/git actions.
# Bind to canonical `tool.pre` for Bash (Claude `PreToolUse` matcher Bash; Cursor `beforeShellExecution`).
# Deterministic, NO LLM. Reads the tool-call JSON on stdin; exit 2 = block (Cursor needs failClosed:true).

set -u
INPUT=$(cat 2>/dev/null || true)

block() {
  reason="git-safety: blocked — $1. If you really mean it, run it yourself outside the agent."
  printf '{"decision":"block","reason":"%s"}\n' "$reason"
  echo "$reason" >&2
  exit 2
}

# Recursive delete of a top-level path. The flag bundle is attacker-controlled, so detect ANY
# recursive `rm` (-r/-R, bundled with -f and reordered: -rf, -fr, -Rf, -f -r) whose target is
# exactly / or ~ — not just the literal "rm -rf /" substring. We pad with spaces and require the
# target to be a standalone token (" / " / " ~ ") so legit paths like /tmp/foo don't false-trip.
# $nsq: whitespace-collapsed $INPUT — tabs/newlines→spaces and runs squeezed to one
# (`tr -s`), so the destructive-git globs below match `git\tclean`/`git  clean` the
# same as `git clean`. The shell collapses inter-token whitespace before exec, so a
# tab or double space must NOT let a destructive command slip past a single-space glob.
nsq=$(printf '%s' "$INPUT" | tr '\t\n"' '   ' | tr -s ' ')
npad=" $nsq "
case "$npad" in
  *" rm "*"-"*[rR]*" / "*|*" rm "*"-"*[rR]*" ~ "*)
                                              block "recursive delete of a top-level path" ;;
esac

# Git GLOBAL options (`-C <dir>`, `--git-dir[=...]`, `--work-tree[=...]`, `-c k=v`, `-p`, `--bare`,
# …) go BEFORE the subcommand, inserting tokens between `git` and the subcommand: `git -C foo clean
# -f`. That splits the contiguous `git clean`/`git checkout`/`git restore` substring the globs below
# anchor on, so a destructive command would run unblocked. Build $ngit by iteratively peeling those
# leading global-option tokens off the `git ` invocation, re-collapsing `git <subcmd>` to be
# contiguous again, then run the same globs against it. Pure POSIX parameter expansion (no `sed`
# alternation — BSD/macOS sed lacks BRE `\|`). $ngit is used for the destructive subcommand
# match AND the protected-branch check, so a leading global option can't split either substring.
ngit=" $nsq "
while :; do
  case "$ngit" in
    *" git -"*)
      pre=${ngit%%" git -"*}            # everything before the ` git ` (other commands in a chain)
      rest=${ngit#*" git -"}            # tokens after ` git ` (first global option, sans its '-')
      rest="-$rest"; tok=${rest%%" "*}  # $tok = the leading global-option token
      case "$tok" in
        # Two-token options: flag + separate argument (`-C foo`, `-c k=v`, `--git-dir foo`, …).
        -C|-c|--git-dir|--work-tree|--namespace)
          rest=${rest#*" "}; rest=${rest#*" "} ;;   # drop the flag AND its argument
        # One-token options incl. `=`-joined (`--git-dir=foo`, `-p`, `--bare`, `--no-pager`, …).
        *) rest=${rest#*" "} ;;                      # drop just the flag
      esac
      ngit="$pre git $rest" ;;
    *) break ;;
  esac
done

# Destructive / irreversible commands. Match the whitespace-collapsed $nsq (not raw
# $INPUT) so tab/double-space token separators can't evade these single-space globs;
# $ngit additionally has git global options peeled so they can't split the substring.
case "$ngit" in
  *"git push"*"--force"*|*"git push -f"*)    block "force-push (rewrites shared history)" ;;
  *"git push"*" +"*)                          block "force-push via leading-'+' refspec (rewrites shared history)" ;;
  *"git reset --hard"*)                       block "git reset --hard (discards uncommitted work)" ;;
  *"git clean -"*[fF]*)                        block "git clean -f (deletes untracked files)" ;;
  *"git checkout ."*|*"git restore ."*)       block "wholesale discard of working-tree changes" ;;
esac

# Wholesale discard where the `.` pathspec follows the subcommand after intervening tokens that don't
# narrow the scope — the idiomatic `git checkout -- .` (`--` end-of-options) and
# `git restore --staged --worktree .` discard the entire tree exactly like the bare forms above. Match
# `git checkout`/`git restore` anywhere ahead of a standalone `.` token, using the space-padded
# (and global-option-peeled) $ngit so a leading `git -C foo` can't split the substring while a path
# like `foo.txt` or `./x` (no surrounding spaces) still can't false-trip.
case "$ngit" in
  *" git checkout "*" . "*|*" git restore "*" . "*) block "wholesale discard of working-tree changes" ;;
esac

# Commits/pushes onto a protected branch. Configurable via .agent/guardrails.conf:
#   PROTECTED_BRANCHES="main master"   (default)   |   PROTECTED_BRANCHES=""  disables it.
# Some repos (solo, docs, trunk-based) legitimately commit to main — found via dogfooding.
CONF="${SCAFFOLD_CONF:-.agent/guardrails.conf}"
PROTECTED_BRANCHES="main master"
[ -f "$CONF" ] && . "$CONF" 2>/dev/null || true
if [ -n "${PROTECTED_BRANCHES:-}" ]; then
  # `git branch --show-current` reports the name even on an unborn branch, whereas
  # `git rev-parse --abbrev-ref HEAD` returns "HEAD" (unreliable). Found via dogfooding.
  branch=$(git branch --show-current 2>/dev/null || true)
  [ -n "$branch" ] || branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  for pb in $PROTECTED_BRANCHES; do
    [ "$branch" = "$pb" ] || continue
    case "$ngit" in
      *"git commit"*|*"git push"*) block "writing directly to the protected '$branch' branch — create a feature branch first (set PROTECTED_BRANCHES in $CONF to change)" ;;
    esac
  done
fi

exit 0
