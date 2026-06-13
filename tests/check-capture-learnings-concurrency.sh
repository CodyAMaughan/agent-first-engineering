#!/bin/sh
# check-capture-learnings-concurrency.sh — assert .agent/hooks/capture-learnings.sh
# serializes concurrent invocations so two near-simultaneous compact.pre /
# session.end runs cannot produce a torn / DUPLICATED memory audit trail.
#
# Bug under test (capture-learnings.sh:25,28-31,67): the hook reads staging
# non-empty (line 25 `[ -s "$STAGING" ]`), appends the ENTIRE staging as a dated
# rollup to session-log.md (lines 28-31 `>> "$LOG"`), merges each section, and
# only THEN truncates staging (line 67 `: > "$STAGING"`). Nothing serializes
# invocations (no flock / lockdir / lockfile). Two concurrent runs both observe
# the same non-empty staging before either truncates, so BOTH append the rollup
# and BOTH race to `:>`/`mv` the section temps. session-log.md ends up with the
# staged content appended TWICE — a duplicated/torn audit trail.
#
# Like check-test-gate-isolation.sh, this drives the REAL hook and makes the race
# DETERMINISTIC with a barrier (no sleeps, no flakiness). The barrier is injected
# WITHOUT editing the hook: we shim `date` on PATH. The hook calls `date` (line
# 29) AFTER it has read staging non-empty (line 25) but BEFORE it appends the
# rollup (line 31) and BEFORE it truncates (line 67). Run A's `date` shim opens a
# FIFO (releasing us), then blocks on a second FIFO until run B has fully
# completed (and thus already appended ITS rollup + truncated). Only then does A
# proceed to append + the merge loop. With the bug, the log holds two rollups;
# with a fix that serializes (lock), B blocks until A is done OR observes empty
# staging, so the log holds exactly ONE rollup.
# Deterministic, POSIX sh, deps: mktemp, mkfifo. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/capture-learnings.sh"
# Absolute path: runners cd into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# rollups_of <session-log-file>: count dated rollup headers ("## 20.." lines the
# hook writes at line 29). This is the single oracle: one staged flush == one
# dated rollup. Robust to the timestamp string (matches the "## 20YY-" prefix).
rollups_of() {
  grep -c '^## 20' "$1" 2>/dev/null || echo 0
}

# --- self-test (proves the duplication oracle isn't trivially always-pass) ------------------
self_test() {
  st_fail=0
  st_td=$(mktemp -d) || { echo "  FAIL self-test: mktemp -d"; exit 1; }
  # (a) a log with ONE dated header counts as 1 (clean, non-duplicated).
  printf '\n## 2026-06-13T00:00:00Z\n## tools/a\nA\n' > "$st_td/one.md"
  if [ "$(rollups_of "$st_td/one.md")" -eq 1 ]; then
    : # ok
  else
    echo "  FAIL self-test: a single-rollup log did not count as 1 (oracle broken)"; st_fail=1
  fi
  # (b) a log with TWO dated headers counts as 2 (the duplicated/torn trail).
  printf '\n## 2026-06-13T00:00:00Z\n## tools/a\nA\n\n## 2026-06-13T00:00:01Z\n## tools/a\nA\n' > "$st_td/two.md"
  if [ "$(rollups_of "$st_td/two.md")" -eq 2 ]; then
    : # ok
  else
    echo "  FAIL self-test: a duplicated-rollup log did not count as 2 (oracle too weak)"; st_fail=1
  fi
  rm -rf "$st_td"
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the duplication oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (single rollup counts 1; duplicated rollup counts 2)"
}

echo "Checking capture-learnings serializes concurrent runs (no duplicated/torn audit trail): $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
command -v mkfifo >/dev/null 2>&1 || { echo "FAIL — mkfifo required for the deterministic race"; exit 1; }
self_test

# --- real check: drive a DETERMINISTIC race against the REAL hook ---------------------------
# One shared throwaway repo: BOTH runs operate on the SAME .agent/memory (that is
# the contended resource). Staging holds two sections.
td=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
mkdir -p "$td/.agent/memory"
printf '## tools/a\nA\n## tools/b\nB\n' > "$td/.agent/memory/_staging.md"

# Barrier FIFOs: a_in — A signals it has entered the critical region (read staging,
# about to act); b_done — we signal A that B has fully finished.
barrier=$(mktemp -d) || { echo "FAIL — mktemp -d (barrier) failed"; rm -rf "$td"; exit 1; }
mkfifo "$barrier/a_in" "$barrier/b_done" 2>/dev/null \
  || { echo "FAIL — mkfifo failed"; rm -rf "$td" "$barrier"; exit 1; }

# A `date` shim, on a per-run PATH, that ONLY run A sees. It announces A has
# reached its date call (post staging-read, pre rollup-append), blocks until B is
# done, then emits a real timestamp so the hook proceeds normally. Run B uses the
# system `date` (no shim) so B sails straight through.
shimdir="$barrier/shim"
mkdir -p "$shimdir"
cat > "$shimdir/date" <<SHIM
#!/bin/sh
# release the test harness (A has entered the critical region)...
: > "$barrier/a_in"
# ...block until B has fully completed (appended ITS rollup + truncated)...
cat "$barrier/b_done" >/dev/null
# ...then behave as the real date so the hook's rollup header is well-formed.
exec /bin/date "\$@"
SHIM
chmod +x "$shimdir/date"

# Launch run A with the shimmed `date` first on PATH.
( cd "$td" && echo '{}' | PATH="$shimdir:$PATH" sh "$HOOK" >/dev/null 2>&1 ) &
apid=$!

# Wait for A to enter its critical region (its shimmed date opened a_in).
cat "$barrier/a_in" >/dev/null

# Now run B to completion with the REAL date (no shim) — B reads the SAME
# non-empty staging, appends its rollup, merges, truncates. B must finish here.
( cd "$td" && echo '{}' | sh "$HOOK" >/dev/null 2>&1 )
rcB=$?

# Release A so it proceeds to append its rollup + run its merge loop.
: > "$barrier/b_done"
wait "$apid"
rcA=$?

LOG="$td/.agent/memory/session-log.md"
n=$(rollups_of "$LOG")

echo "  ..   run A exited $rcA, run B exited $rcB"

# THE assertion: exactly ONE dated rollup for one staged flush. Two == the
# duplicated/torn audit trail the bug produces.
if [ "$n" -eq 1 ]; then
  echo "  ok   session-log.md holds exactly ONE dated rollup ($n) — runs serialized"
elif [ "$n" -gt 1 ]; then
  echo "  FAIL session-log.md holds $n dated rollups — the staged content was appended more than once (duplicated/torn audit trail)"
  fail=1
else
  echo "  FAIL session-log.md holds $n dated rollups (expected 1) — unexpected:"
  sed 's/^/         /' "$LOG" 2>/dev/null
  fail=1
fi

rm -rf "$td" "$barrier"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — capture-learnings serializes concurrent runs; one staged flush yields one rollup."
else
  echo "FAIL — .agent/hooks/capture-learnings.sh appends the whole staging as a dated rollup (lines 28-31) and defers truncation to line 67, with NO locking, so two concurrent compact.pre/session.end runs both read the same non-empty staging and both append — duplicating the memory audit trail and racing the per-section mv/:>."
fi
exit "$fail"
