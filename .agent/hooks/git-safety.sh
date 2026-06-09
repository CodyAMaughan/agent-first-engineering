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

# Destructive / irreversible commands.
case "$INPUT" in
  *"rm -rf /"*|*"rm -rf ~"*)                 block "recursive delete of a top-level path" ;;
  *"git push"*"--force"*|*"git push -f"*)    block "force-push (rewrites shared history)" ;;
  *"git reset --hard"*)                       block "git reset --hard (discards uncommitted work)" ;;
  *"git clean -"*[fF]*)                        block "git clean -f (deletes untracked files)" ;;
  *"git checkout ."*|*"git restore ."*)       block "wholesale discard of working-tree changes" ;;
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
    case "$INPUT" in
      *"git commit"*|*"git push"*) block "writing directly to the protected '$branch' branch — create a feature branch first (set PROTECTED_BRANCHES in $CONF to change)" ;;
    esac
  done
fi

exit 0
