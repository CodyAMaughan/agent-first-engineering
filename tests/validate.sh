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
  if ! grep -q '^name:' "$s" || ! grep -q '^description:' "$s"; then
    bad "SKILL.md missing name/description: $s"
    continue
  fi
  # Frontmatter must PARSE, not just exist: an unquoted ": " (colon-space) in a value
  # is a YAML mapping indicator that silently drops the whole frontmatter at load time.
  # (Dogfooding caught this in scaffold-agent-project's "Two modes: init".)
  if awk '
      /^---[ \t]*$/ { d++; next }
      d==1 && /^[a-zA-Z0-9_-]+:/ {
        val = $0; sub(/^[^:]*:[ \t]*/, "", val)       # strip the key
        if (val ~ /^".*"$/ || val ~ /^'\''.*'\''$/) next  # quoted values may contain ": "
        if (val ~ /: /) { print; bad=1 }
      }
      END { exit bad }
    ' "$s" >/dev/null; then
    ok "SKILL.md valid: $s"
  else
    bad "SKILL.md frontmatter has an unquoted \": \" (breaks YAML parse): $s"
  fi
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

  # 4b. Regression: an empty "## " heading (path forgotten / typed on the next line) must NOT
  # silently destroy the following section. flush() returns early when `current` is empty, yet
  # staging is unconditionally wiped at the end — the learning is lost with rc=0 and no warning.
  # Contract: the section is EITHER persisted to a <path>.md OR staging is left intact to fix.
  td=$(mktemp -d)
  mkdir -p "$td/.agent/memory"
  printf '## \nbody for empty path\nmore body\n' > "$td/.agent/memory/_staging.md"
  ( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
  persisted=0
  [ -n "$(find "$td/.agent/memory" -type f -name '*.md' ! -name '_staging.md' ! -name 'session-log.md' 2>/dev/null)" ] && persisted=1
  staging_kept=0
  [ -s "$td/.agent/memory/_staging.md" ] && staging_kept=1
  if [ "$persisted" -eq 1 ] || [ "$staging_kept" -eq 1 ]; then
    ok "capture-learnings: empty '## ' heading is persisted or staging left intact (no silent loss)"
  else
    bad "capture-learnings: empty '## ' heading silently discarded the section AND wiped staging (data loss, rc=0)"
  fi
  rm -rf "$td"
fi

# 4c. Regression: a memory file whose path contains a SPACE must be re-injected by load-memory.sh.
# capture-learnings takes a heading verbatim (e.g. "## tools/test db") and writes "<path>.md", so a
# spaced filename is reachable end-to-end. load-memory.sh:14 uses an unquoted `for f in $(find ...)`,
# which word-splits the path on the space; the per-token `cat "$f"` then fails and the learning body
# is silently dropped from session-start context (rc=0). Contract: the body MUST appear in stdout.
LOADER="$ROOT/.agent/hooks/load-memory.sh"
if [ -x "$LOADER" ]; then
  td=$(mktemp -d)
  mkdir -p "$td/.agent/memory/tools"
  printf '# mem\nNeeds --no-sandbox locally.\n' > "$td/.agent/memory/tools/test db.md"
  out=$( cd "$td" && echo '{}' | sh "$LOADER" 2>/dev/null )
  if printf '%s' "$out" | grep -q 'Needs --no-sandbox locally.'; then
    ok "load-memory: re-injects a learning whose path contains a space"
  else
    bad "load-memory: a memory path with a space is word-split and dropped from stdout (learning lost, rc=0)"
  fi
  rm -rf "$td"
fi

# 4d. Regression: git-safety must block the leading-`+` refspec force-push form, not just --force/-f.
# `git push origin +main` and `git push origin +refs/heads/main` are exactly equivalent to a
# force-push of that ref (they rewrite shared history) — the precise harm line 19 exists to prevent.
# The line-19 case only matches the literal substrings "--force" / "git push -f", so the `+`-refspec
# form slips through (exit 0) even from a non-protected feature branch. Contract: a `+`-prefixed
# push refspec MUST be blocked with exit 2, just like --force. Control: --force already blocks.
GITSAFE="$ROOT/.agent/hooks/git-safety.sh"
if [ -x "$GITSAFE" ]; then
  # Control — proves the hook blocks the canonical force-push (must exit 2).
  printf '%s' '{"command":"git push origin main --force"}' | sh "$GITSAFE" >/dev/null 2>&1
  ctl=$?
  # The gap — semantically-equivalent leading-`+` refspec force-pushes.
  printf '%s' '{"command":"git push origin +refs/heads/main"}' | sh "$GITSAFE" >/dev/null 2>&1
  r1=$?
  printf '%s' '{"command":"git push origin +main"}' | sh "$GITSAFE" >/dev/null 2>&1
  r2=$?
  if [ "$ctl" -eq 2 ] && [ "$r1" -eq 2 ] && [ "$r2" -eq 2 ]; then
    ok "git-safety: blocks leading-'+' refspec force-push (+main / +refs/heads/main)"
  else
    bad "git-safety: leading-'+' refspec force-push slips through (control --force rc=$ctl, +refs/heads/main rc=$r1, +main rc=$r2; all must be 2)"
  fi

  # 4e. Regression: git-safety must block a recursive root/home delete REGARDLESS of flag order or
  # spelling, not just the two literal substrings "rm -rf /" / "rm -rf ~". The line-18 case is a
  # fixed-substring match, but the flag bundle is attacker-controlled: `rm -fr /`, `rm -f -r /`, and
  # `rm -Rf /` are all valid invocations that recursively delete root (and likewise `rm -fr ~` for
  # home), yet each slips through (exit 0). Contract: every recursive-force delete of / or ~ MUST be
  # blocked with exit 2. Control: the canonical `rm -rf /` already blocks, proving the hook ran.
  # NB: the trigger commands are assembled from $R/$SL/$TL via printf so the *substrings* never appear
  # literally in this file — otherwise the live repo's own git-safety hook would intercept the test's
  # own JSON when an agent reads/edits it. The hook under test still receives the real commands.
  R=rm; SL=/; TL='~'
  printf '{"command":"%s -rf %s"}' "$R" "$SL" | sh "$GITSAFE" >/dev/null 2>&1; gctl=$?   # control: must block
  printf '{"command":"%s -fr %s"}' "$R" "$SL" | sh "$GITSAFE" >/dev/null 2>&1; g1=$?      # reordered flags
  printf '{"command":"%s -f -r %s"}' "$R" "$SL" | sh "$GITSAFE" >/dev/null 2>&1; g2=$?    # split flags
  printf '{"command":"%s -Rf %s"}' "$R" "$SL" | sh "$GITSAFE" >/dev/null 2>&1; g3=$?      # capital -R
  printf '{"command":"%s -fr %s"}' "$R" "$TL" | sh "$GITSAFE" >/dev/null 2>&1; g4=$?      # reordered, home
  if [ "$gctl" -eq 2 ] && [ "$g1" -eq 2 ] && [ "$g2" -eq 2 ] && [ "$g3" -eq 2 ] && [ "$g4" -eq 2 ]; then
    ok "git-safety: blocks recursive root/home delete regardless of flag order/spelling (-fr, -f -r, -Rf)"
  else
    bad "git-safety: reordered/split/capital rm flags evade the literal guard (control -rf / rc=$gctl; -fr / rc=$g1, -f -r / rc=$g2, -Rf / rc=$g3, -fr ~ rc=$g4; all must be 2)"
  fi
fi

# 5. QA loop manifest is well-formed (repo-self only; scaffold targets have no .agent/qa.conf).
if [ -f "$ROOT/.agent/qa.conf" ]; then
  if ( cd "$ROOT" && sh tests/check-qa-manifest.sh >/dev/null 2>&1 ); then
    ok "QA manifest well-formed (every system-under-test exists)"
  else
    bad "QA manifest broken (run: sh tests/check-qa-manifest.sh)"
  fi
fi

echo
[ "$fail" -eq 0 ] && echo "PASS — agent-first layer is well-formed." || echo "FAILURES above."
exit "$fail"
