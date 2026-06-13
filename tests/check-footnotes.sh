#!/bin/sh
# check-footnotes.sh — assert Markdown footnote integrity across every curriculum doc.
# An authoring non-negotiable is inline [^n] citations; this is the fast, deps-light,
# pre-render gate that catches imbalances (and the ORPHANS/DUPLICATES the strict mkdocs
# build tolerates). For each docs/curriculum/**/*.md it reports three per-file classes:
#   GAP       — id referenced ([^id]) but never defined ([^id]:) in that file
#   ORPHAN    — id defined ([^id]:) but never referenced in that file
#   DUPLICATE — id defined ([^id]:) 2+ times in that file
# Grammar: a DEFINITION is [^id]: at line start (leading whitespace allowed); a REFERENCE
# is any other [^id]; id is [^]]+. Only triple-backtick (```) fenced blocks are excluded
# (the toggling fence line itself too) — ~~~ fences and 4-space indented blocks are
# deliberately out of scope (the curriculum writes code samples with ``` fences).
# Deterministic (sorted files + sorted ids), POSIX sh, deps: find/awk/sort/mktemp.
# Runs a built-in self-test first (proves the detector catches a known break) then the
# real scan. Run from the repo root. Exits non-zero on any imbalance or self-test failure.

set -u
fail=0

# --- core checker -----------------------------------------------------------------------
# check_file <path>: prints nothing and returns 0 on a balanced file; on imbalance prints
# one "<CLASS> [^id]" line per offending id (sorted, stable) and returns 1. This single
# function is the only place footnote grammar lives, so the self-test exercises the *real*
# detector rather than a parallel reimplementation.
check_file() {
  awk '
    # A fence is a line whose first non-whitespace content is ```. Toggle, skip that line.
    /^[ \t]*```/ { in_fence = !in_fence; next }
    in_fence     { next }
    {
      line = $0
      # Walk the whole line so a definition line that also references is fully recorded,
      # e.g. "[^1]: Source, see also [^2]." => def[1] and ref[2].
      at_start = 1                          # first token on the line may be a definition
      while (match(line, /\[\^[^]]+\]/)) {
        tok = substr(line, RSTART, RLENGTH) # "[^id]"
        id  = substr(tok, 3, RLENGTH - 3)   # strip "[^" and "]"
        rest = substr(line, RSTART + RLENGTH)
        # Leading whitespace before the first token still counts as "line start".
        lead = substr(line, 1, RSTART - 1)
        is_def = (at_start && lead ~ /^[ \t]*$/ && rest ~ /^:/)
        if (is_def) def[id]++; else ref[id]++
        seen[id] = 1
        line = rest
        at_start = 0
      }
    }
    END {
      n = 0
      for (id in seen) ids[n++] = id
      # insertion sort for deterministic output without relying on gawk asort extensions
      for (i = 1; i < n; i++) {
        key = ids[i]; j = i - 1
        while (j >= 0 && ids[j] > key) { ids[j+1] = ids[j]; j-- }
        ids[j+1] = key
      }
      bad = 0
      for (i = 0; i < n; i++) {
        id = ids[i]
        if (ref[id] > 0 && def[id] == 0) { print "GAP [^" id "]";       bad = 1 }
        if (def[id] > 0 && ref[id] == 0) { print "ORPHAN [^" id "]";    bad = 1 }
        if (def[id] >= 2)                { print "DUPLICATE [^" id "]"; bad = 1 }
      }
      exit bad
    }
  ' "$1"
}

# --- self-test (proves the detector is not trivially always-pass) ------------------------
# Build a fixture with one of each imbalance class, a clean control, and an id that only
# appears inside a ``` fence (must NOT be flagged). Run the *real* check_file against it
# and assert it returns non-zero AND names each planted id. If the detector can't catch a
# known break, refuse to certify the repo.
self_test() {
  td=$(mktemp -d) || { echo "FAIL self-test (mktemp failed)"; exit 1; }
  trap 'rm -rf "$td"' EXIT
  fx="$td/fixture.md"
  {
    printf 'A gap: see [^gap].\n'                      # REFERENCE, never defined  -> GAP
    printf '[^orphan]: defined but never cited.\n'     # DEFINITION, never referenced -> ORPHAN
    printf 'A dup: see [^dup].\n'                       # REFERENCE for dup
    printf '[^dup]: first definition.\n'                # DEFINITION 1
    printf '[^dup]: second definition.\n'               # DEFINITION 2 -> DUPLICATE
    printf 'Clean: see [^ok] and more.\n'               # balanced control
    printf '[^ok]: a real source.\n'
    printf '```\n'                                      # fenced block: ids inside ignored
    printf 'code with [^fenced] marker, no def.\n'      # would be a GAP if fences counted
    printf '```\n'
  } > "$fx"

  out=$(check_file "$fx"); rc=$?
  st_fail=0
  [ "$rc" -ne 0 ]                          || { echo "  FAIL self-test: clean exit on unbalanced fixture"; st_fail=1; }
  echo "$out" | grep -q '^GAP \[\^gap\]$'       || { echo "  FAIL self-test: GAP [^gap] not detected"; st_fail=1; }
  echo "$out" | grep -q '^ORPHAN \[\^orphan\]$' || { echo "  FAIL self-test: ORPHAN [^orphan] not detected"; st_fail=1; }
  echo "$out" | grep -q '^DUPLICATE \[\^dup\]$' || { echo "  FAIL self-test: DUPLICATE [^dup] not detected"; st_fail=1; }
  echo "$out" | grep -q 'fenced'                && { echo "  FAIL self-test: id inside a fenced code block was flagged"; st_fail=1; }
  echo "$out" | grep -q 'ok'                    && { echo "  FAIL self-test: balanced id [^ok] was flagged"; st_fail=1; }

  rm -rf "$td"; trap - EXIT
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the detector cannot catch a known break. Aborting."
    exit 1
  fi
  echo "  ok   self-test (GAP/ORPHAN/DUPLICATE detected; fenced and balanced ids ignored)"
}

echo "Checking curriculum footnote integrity: docs/curriculum/**/*.md"
self_test

# --- real scan --------------------------------------------------------------------------
for f in $(find docs/curriculum -name '*.md' 2>/dev/null | sort); do
  out=$(check_file "$f")
  if [ -z "$out" ]; then
    echo "  ok   $f"
  else
    echo "  FAIL $f"
    echo "$out" | sed 's/^/         /'
    fail=1
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — every curriculum footnote is balanced (no GAPS/ORPHANS/DUPLICATES)."
else
  echo "FAIL — fix the imbalances above (GAP=referenced-never-defined, ORPHAN=defined-never-referenced, DUPLICATE=defined-2+×)."
fi
exit "$fail"
