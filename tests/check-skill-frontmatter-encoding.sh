#!/bin/sh
# check-skill-frontmatter-encoding.sh — assert tests/validate.sh's SKILL.md
# "unquoted ': '" frontmatter detector (validate.sh:38-50) is not defeated by
# CRLF line endings or a leading UTF-8 BOM.
#
# Bug under test (validate.sh:38-50): the detector arms only after its awk
# delimiter /^---[ \t]*$/ matches the opening "---" fence (d reaches 1). With
# CRLF the fence line is "---\r": the trailing CR is not [ \t] and the $ anchor
# sits before it, so the delimiter NEVER matches, d stays 0, and the ": "
# detector at line 43 is never reached. With a UTF-8 BOM the first fence is
# "\xEF\xBB\xBF---": the leading BOM bytes break the ^--- anchor, same result.
# Meanwhile the step-1 existence greps (validate.sh:31) are NOT EOL-anchored
# (`grep -q '^name:'` / `'^description:'`), so they still pass — the SKILL.md is
# judged "ok   SKILL.md valid" even though its frontmatter carries the exact
# unquoted-": " YAML-mapping-drop bug the detector exists to catch.
#
# Consequence (the real defect): a gate false-negative / encoding evasion. The
# canonical "description: Two modes: init and adopt" bug — the one the detector
# was written to catch (validate.sh:37) — passes inspection on any SKILL.md
# authored on Windows or by tooling that emits CRLF/BOM. CLAUDE.md/AGENTS.md
# require the .claude/skills mirror to be byte-identical to .agents/skills, so a
# SKILL.md whose YAML silently drops at load time can sail through CI undetected.
# The fix must normalize encoding before matching (strip CR/BOM), or allow an
# optional CR/BOM on the awk fence anchor, so the detector fires on CRLF/BOM
# exactly as it does on LF.
#
# Oracle: drive the REAL tests/validate.sh over a minimal scaffolded target whose
# .agents/skills/foo/SKILL.md carries the unquoted ": " bug, in three encodings —
# LF (control), CRLF, and BOM. For EVERY encoding the SKILL.md frontmatter check
# must report FAIL, because the unquoted ": " is present byte-for-byte in all
# three. LF establishes the detector works at all; CRLF and BOM are the evasions.
#
# Deterministic, POSIX sh, deps: mktemp, printf, grep, sh. Run from the repo root.

set -u
ROOT="${1:-.}"
VALIDATE="$ROOT/tests/validate.sh"
# Absolute path: each fixture cd's / runs validate.sh against a temp dir, so a
# relative VALIDATE would vanish once we point it elsewhere.
case "$VALIDATE" in /*) ;; *) VALIDATE="$(pwd)/$VALIDATE" ;; esac
fail=0

echo "Checking validate.sh SKILL.md ': ' detector survives CRLF/BOM: $VALIDATE"
[ -f "$VALIDATE" ] || { echo "FAIL — validate.sh not found: $VALIDATE"; exit 1; }

# Build a minimal but valid agent-first target dir, then drop in a SKILL.md whose
# frontmatter carries the canonical unquoted ": " bug in the requested encoding.
# Encodings: lf | crlf | bom.  Echoes validate.sh's stdout for the caller to judge.
make_target() {
  enc="$1"
  td=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
  # AGENTS.md so validate.sh's step 1 is satisfied (plain markdown, no frontmatter).
  printf '# T\n\nA minimal agent-first target for the SKILL.md encoding regression.\n' > "$td/AGENTS.md"
  mkdir -p "$td/.agents/skills/foo"
  sk="$td/.agents/skills/foo/SKILL.md"
  case "$enc" in
    lf)   printf -- '---\nname: foo\ndescription: Two modes: init and adopt\n---\n# body\n'         > "$sk" ;;
    crlf) printf -- '---\r\nname: foo\r\ndescription: Two modes: init and adopt\r\n---\r\n# body\r\n' > "$sk" ;;
    bom)  printf '\xEF\xBB\xBF---\nname: foo\ndescription: Two modes: init and adopt\n---\n# body\n'   > "$sk" ;;
    *)    echo "FAIL — unknown encoding: $enc"; exit 1 ;;
  esac
  echo "$td"
}

# The oracle for one encoding: validate.sh must emit a SKILL.md FAIL line (and must
# NOT call this SKILL.md "valid"). Returns 0 when the bug is correctly caught.
detector_fires() {
  enc="$1"
  td=$(make_target "$enc")
  out=$(sh "$VALIDATE" "$td" 2>&1)
  rm -rf "$td"
  flagged=0; greened=0
  printf '%s\n' "$out" | grep -q 'FAIL SKILL.md frontmatter has an unquoted' && flagged=1
  printf '%s\n' "$out" | grep -q 'ok   SKILL.md valid' && greened=1
  echo "  ..   [$enc] detector-FAIL=$flagged  false-green=$greened"
  [ "$flagged" -eq 1 ] && [ "$greened" -eq 0 ]
}

# --- self-test: the oracle is non-trivial — LF (control) MUST be caught --------------------
# This proves the detector works at all and that detector_fires() really keys on the FAIL
# line. If LF were NOT caught, the whole detector would be dead and CRLF/BOM checks moot.
if detector_fires lf; then
  echo "  ok   self-test: LF fixture with the bug is correctly FLAGGED (detector alive)"
else
  echo "FAIL — self-test: validate.sh did NOT flag the unquoted ': ' bug even on LF;"
  echo "       the detector is entirely dead, not merely encoding-evadable. Aborting."
  exit 1
fi

# --- real checks: the SAME bug under CRLF and BOM must be flagged just like LF -------------
for enc in crlf bom; do
  if detector_fires "$enc"; then
    echo "  ok   [$enc] SKILL.md ': ' bug flagged (detector survives encoding)"
  else
    echo "  FAIL [$enc] SKILL.md ': ' bug NOT flagged — encoding defeats the detector (false green)"
    fail=1
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — the SKILL.md ': ' detector fires on LF, CRLF, and BOM alike."
else
  echo "FAIL — validate.sh's SKILL.md ': ' detector (lines 38-50) false-greens on CRLF/BOM: its awk fence anchor /^---[ \t]*\$/ never matches '---\\r' (trailing CR) or '\\xEF\\xBB\\xBF---' (leading BOM), so d never reaches 1 and the ': ' check at line 43 is never armed, while the un-anchored '^name:'/'^description:' greps (line 31) still pass. Normalize encoding (strip CR/BOM) before matching, or allow an optional CR/BOM on the fence anchor."
fi
exit "$fail"
