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

# Destructive / irreversible commands. Match the whitespace-collapsed $nsq (not raw
# $INPUT) so tab/double-space token separators can't evade these single-space globs.
case "$nsq" in
  *"git push"*"--force"*|*"git push -f"*)    block "force-push (rewrites shared history)" ;;
  *"git push"*" +"*)                          block "force-push via leading-'+' refspec (rewrites shared history)" ;;
  *"git reset --hard"*)                       block "git reset --hard (discards uncommitted work)" ;;
  *"git clean -"*[fF]*)                        block "git clean -f (deletes untracked files)" ;;
  *"git checkout ."*|*"git restore ."*)       block "wholesale discard of working-tree changes" ;;
esac

# Wholesale discard where the `.` pathspec follows the subcommand after intervening tokens that don't
# narrow the scope — the idiomatic `git checkout -- .` (`--` end-of-options) and
# `git restore --staged --worktree .` discard the entire tree exactly like the bare forms above. Match
# `git checkout`/`git restore` anywhere ahead of a standalone `.` token, using the space-padded $npad
# so a path like `foo.txt` or `./x` (no surrounding spaces) can't false-trip.
case "$npad" in
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
    case "$nsq" in
      *"git commit"*|*"git push"*) block "writing directly to the protected '$branch' branch — create a feature branch first (set PROTECTED_BRANCHES in $CONF to change)" ;;
    esac
  done
fi

exit 0
