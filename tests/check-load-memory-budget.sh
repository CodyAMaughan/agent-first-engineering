#!/bin/sh
# check-load-memory-budget.sh — assert .agent/hooks/load-memory.sh CAPS the bytes
# it re-injects at session start, so one oversized persisted learning can't flood
# the context window every session.
#
# Bug under test (.agent/hooks/load-memory.sh:14-22): the find|while loop does a
# bare `cat "$f"` (line 20) for every memory *.md file with NO per-file or total
# byte budget (no head -c / cut -c / fold / dd / truncate / wc -c guard). The
# hook's own header (line 4) says "agents inject stdout as additional context at
# session start", and it re-emits on EVERY session start. So a single large
# staged learning — staged content is agent/user-influenceable, see
# capture-learnings.sh:71 "staged content is attacker-influenceable" — becomes a
# persistent, repeatable context-flood DoS: ~1.3 MB out of one ~40k-line staging
# buffer, re-injected forever until manually pruned.
#
# Repro (the confirmed recipe, reproduced here against the REAL hooks):
#   { echo '## notes/x'; yes 'padding line of learning content' | head -40000; } \
#       > .agent/memory/_staging.md
#   echo '{}' | sh .agent/hooks/capture-learnings.sh     # persists notes/x.md
#   echo '{}' | sh .agent/hooks/load-memory.sh | wc -c   # >> any sane cap
#
# EXPECTED: load-memory.sh must emit a BOUNDED re-injection (cap at N KB per file
# or total). A multi-hundred-KB single-shot dump is the defect.
#
# Like check-test-gate-isolation.sh / check-skill-mirror-empty.sh, this drives the
# REAL target hooks in a throwaway temp repo and runs a self-test first to prove
# the oracle isn't trivially always-fail: a SMALL persisted learning must stay
# under the cap (and still be re-injected), while the OVERSIZED one must not.
# Deterministic, POSIX sh, deps: mktemp/cp/yes/head/wc. Run from the repo root.

set -u
ROOT="${1:-.}"
LOAD="$ROOT/.agent/hooks/load-memory.sh"
CAPTURE="$ROOT/.agent/hooks/capture-learnings.sh"
# Absolute paths: we run the hooks from inside a temp repo, so relative paths
# would vanish once we leave the real repo root.
case "$LOAD"    in /*) ;; *) LOAD="$(pwd)/$LOAD" ;; esac
case "$CAPTURE" in /*) ;; *) CAPTURE="$(pwd)/$CAPTURE" ;; esac
fail=0

[ -f "$LOAD" ]    || { echo "FAIL — target not found: $LOAD"; exit 1; }
[ -f "$CAPTURE" ] || { echo "FAIL — capture hook not found: $CAPTURE"; exit 1; }

# A generous total budget. A healthy memory wiki of real one-line learnings is a
# few KB; even a roomy cap of 256 KB is an order of magnitude under the ~1.3 MB
# the unbounded loop emits. The fix may cap per-file or total — either keeps the
# re-injection well under this.
CAP_BYTES=262144   # 256 KiB

echo "Checking load-memory re-injection is byte-bounded: $LOAD"

# run_scenario <staging-line-count>: build a temp repo, stage that many padding
# lines under a single "## notes/x" heading, persist it with the REAL capture
# hook, then run the REAL load-memory hook and echo the emitted byte count. The
# byte count is written to $CNT_FILE (a file, not a var) so it survives the
# $(...) subshell capture.
CNT_FILE=$(mktemp) || { echo "FAIL — mktemp failed"; exit 1; }
run_scenario() {
  lines="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; echo -1 > "$CNT_FILE"; return; }
  mkdir -p "$td/.agent/hooks" "$td/.agent/memory"
  cp "$LOAD"    "$td/.agent/hooks/load-memory.sh"
  cp "$CAPTURE" "$td/.agent/hooks/capture-learnings.sh"
  {
    echo '## notes/x'
    yes 'padding line of learning content' | head -"$lines"
  } > "$td/.agent/memory/_staging.md"
  ( cd "$td" && echo '{}' | sh .agent/hooks/capture-learnings.sh >/dev/null 2>&1 )
  bytes=$( cd "$td" && echo '{}' | sh .agent/hooks/load-memory.sh 2>/dev/null | wc -c )
  bytes=$(printf '%s' "$bytes" | tr -d ' ')
  echo "$bytes" > "$CNT_FILE"
  rm -rf "$td"
}

# --- self-test (proves this oracle isn't trivially always-fail) ----------------
# A SMALL persisted learning (a few lines) must re-inject some non-empty content
# AND stay well under the cap. If even that tripped the cap, the oracle would be
# meaningless.
run_scenario 5; small=$(cat "$CNT_FILE")
echo "  ..   small (5-line) learning re-injects $small bytes"
if [ "$small" -gt 0 ] && [ "$small" -le "$CAP_BYTES" ]; then
  echo "  ok   self-test: small learning is non-empty and under the $CAP_BYTES-byte cap"
else
  echo "  FAIL self-test: small learning ($small bytes) is empty or already over cap — oracle is broken"
  echo "FAIL — self-test failed; aborting."
  rm -f "$CNT_FILE"
  exit 1
fi

# --- real check: the OVERSIZED staged learning must NOT blow the budget --------
run_scenario 40000; big=$(cat "$CNT_FILE")
echo "  ..   oversized (40000-line) learning re-injects $big bytes (cap $CAP_BYTES)"
if [ "$big" -gt "$CAP_BYTES" ]; then
  echo "  FAIL load-memory emitted $big bytes (> $CAP_BYTES cap) from ONE staged learning — unbounded re-injection, context-flood DoS every session"
  fail=1
else
  echo "  ok   oversized learning is capped to $big bytes (<= $CAP_BYTES)"
fi

# --- real check: MULTIBYTE (UTF-8) memory must NOT blow the byte budget ---------
# The accumulator in load-memory.sh measures `${#chunk}` (line 37) and the title/
# header lengths in CHARACTERS under a UTF-8 locale (the agent runtime defaults to
# LANG=en_US.UTF-8 and /bin/sh is bash-in-posix-mode where ${#s} is a char count),
# while `head -c "$remain"` (line 35) bounds each emitted chunk in BYTES. So every
# 2-3-byte UTF-8 char counts as 1 toward `used`, undercounting the budget ~2-3x and
# letting the find|while loop keep emitting past the cap. The ASCII scenario above
# can NEVER catch this (there ${#chunk} == byte count), so build fixtures directly
# with multibyte content. run_mb_scenario <file-count> <chars-per-file> <utf8-char>.
run_mb_scenario() {
  files="$1"; chars="$2"; ch="$3"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; echo -1 > "$CNT_FILE"; return; }
  mkdir -p "$td/.agent/hooks" "$td/.agent/memory"
  cp "$LOAD" "$td/.agent/hooks/load-memory.sh"
  i=1
  while [ "$i" -le "$files" ]; do
    python3 -c "import sys; print('# h'); print(sys.argv[1]*int(sys.argv[2]))" \
      "$ch" "$chars" > "$td/.agent/memory/f$i.md"
    i=$((i + 1))
  done
  bytes=$( cd "$td" && echo '{}' | sh .agent/hooks/load-memory.sh 2>/dev/null | wc -c )
  bytes=$(printf '%s' "$bytes" | tr -d ' ')
  echo "$bytes" > "$CNT_FILE"
  rm -rf "$td"
}

# 6 files x 30000 'é' (2-byte) chars: ~360 KB of bytes, char-counted as ~180 KB.
run_mb_scenario 6 30000 'é'; mb=$(cat "$CNT_FILE")
echo "  ..   multibyte (UTF-8 'é') memory re-injects $mb bytes (cap $CAP_BYTES)"
if [ "$mb" -gt "$CAP_BYTES" ]; then
  echo "  FAIL load-memory emitted $mb bytes (> $CAP_BYTES cap) from multibyte UTF-8 memory — \${#chunk} char-vs-byte undercount lets the cap be exceeded ~2-3x every session"
  fail=1
else
  echo "  ok   multibyte memory is capped to $mb bytes (<= $CAP_BYTES)"
fi

rm -f "$CNT_FILE"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — load-memory.sh caps its session-start re-injection; one oversized learning can't flood context."
else
  echo "FAIL — .agent/hooks/load-memory.sh re-injects memory with NO byte budget: the find|while 'cat \"\$f\"' loop (lines 14-22, cat on line 20) has no per-file/total cap, so one ~40k-line staged learning emits >256 KB to stdout — injected as session-start context EVERY session (a persistent context-flood DoS). Add a head -c / total-byte budget."
fi
exit "$fail"
