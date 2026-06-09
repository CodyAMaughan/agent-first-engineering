#!/bin/sh
# validate.sh — assert a scaffolded repo's agent-first layer is well-formed.
# Usage: sh tests/validate.sh [target-dir]   (default: current dir)
# Exits non-zero on any failure. Deterministic, no deps beyond POSIX sh + grep.

set -u
# Resolve to an absolute path: the capture-learnings check `cd`s into a temp dir, so a
# relative ROOT (the default ".") would make "$ROOT/.agent/hooks/..." unreachable there.
ROOT=$(cd "${1:-.}" 2>/dev/null && pwd) || { echo "validate.sh: no such directory: ${1:-.}"; exit 1; }
fail=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fail=1; }

echo "Validating agent-first layer in: $ROOT"

# 1. AGENTS.md: exists, <200 lines, no YAML frontmatter.
if [ -f "$ROOT/AGENTS.md" ]; then
  lines=$(wc -l < "$ROOT/AGENTS.md" | tr -d ' ')
  [ "$lines" -lt 200 ] && ok "AGENTS.md present, $lines lines (<200)" || bad "AGENTS.md is $lines lines (must be <200)"
  head -1 "$ROOT/AGENTS.md" | grep -q '^---' && bad "AGENTS.md has frontmatter (must be plain markdown)" || ok "AGENTS.md has no frontmatter"
else
  bad "AGENTS.md missing at repo root"
fi

# 2. Every generated SKILL.md has name + description frontmatter.
# Check the canonical portable core only (.agents/skills); .claude/skills is a mirror, and may also
# contain third-party skills (e.g. Spec Kit's speckit-*) that aren't ours to validate.
found_skill=0
for s in $(find "$ROOT/.agents/skills" -name SKILL.md 2>/dev/null); do
  found_skill=1
  grep -q '^name:' "$s" && grep -q '^description:' "$s" \
    && ok "SKILL.md valid: $s" \
    || bad "SKILL.md missing name/description: $s"
done
[ "$found_skill" -eq 0 ] && echo "  note no SKILL.md found (skipped skill checks)"

# 3. Hook scripts are executable.
for h in $(find "$ROOT/.agent/hooks" -name '*.sh' 2>/dev/null); do
  [ -x "$h" ] && ok "hook executable: $h" || bad "hook not executable: $h"
done

# 4. capture-learnings fires: stage a learning, run the hook, assert the file appears.
HOOK="$ROOT/.agent/hooks/capture-learnings.sh"
if [ -x "$HOOK" ]; then
  td=$(mktemp -d)
  mkdir -p "$td/.agent/memory"
  printf '## tools/_validate\nfixture learning\n' > "$td/.agent/memory/_staging.md"
  ( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
  [ -f "$td/.agent/memory/tools/_validate.md" ] \
    && ok "capture-learnings hook fires (memory persisted)" \
    || bad "capture-learnings hook did not persist memory"
  rm -rf "$td"
fi

echo
[ "$fail" -eq 0 ] && echo "PASS — agent-first layer is well-formed." || echo "FAILURES above."
exit "$fail"
