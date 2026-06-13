#!/bin/sh
# check-capture-learnings-staging-race.sh — assert .agent/hooks/capture-learnings.sh
# does not LOSE a learning that the PRODUCER (the agent/user) appends to
# _staging.md while a flush is in flight.
#
# Bug under test (capture-learnings.sh:36,54-87,92): the flush is a non-atomic
# test-process-truncate of _staging.md:
#   line 36  [ -s "$STAGING" ]          # staging non-empty?
#   line 54  while ... done < "$STAGING"  # read each "## <path>" section
#   line 92  [ "$unsaved" -eq 0 ] && : > "$STAGING"   # truncate (UNCONDITIONAL on success)
# The line-33 mkdir lock only serializes capture-vs-capture; it takes NO lock
# against the PRODUCER appending learnings to the SAME _staging.md. A section
# appended AFTER the read loop hits EOF but BEFORE the line-92 truncate is read by
# nobody and then wiped — permanently, silently (rc=0, nothing left in staging,
# nothing in the session-log rollup).
#
# Contract: "no learning lost" — every staged section is either PERSISTED to
# .agent/memory/<path>.md OR LEFT in _staging.md to be flushed next time. It must
# NEVER vanish from both.
#
# Like check-capture-learnings-concurrency.sh, this drives the REAL hook and makes
# the race DETERMINISTIC with a barrier (no sleeps, no flakiness) — and WITHOUT
# editing the hook. We shim `mv` on a per-run PATH. For single-section staging
# ("## tools/a\nbody-a\n") the hook's external-command order is:
#   1. date    (line 40, BEFORE the read loop)
#   2. mktemp  (line 78, inside the loop, for section a)
#   3. mv      (line 52, in the FINAL flush at line 88) -- the LAST external
#              command in the EOF -> truncate window (read loop is already DONE).
# So when the hook's `mv` fires, the read loop has already hit EOF on staging but
# the line-92 truncate has NOT yet run. Our mv shim: (a) releases the producer to
# append a brand-new section "## tools/b\nbody-b\n" to the SAME _staging.md, (b)
# blocks until that append has fully completed, (c) execs the REAL mv so tools/a is
# still persisted faithfully and the hook proceeds to its truncate. With the bug
# the line-92 `: > "$STAGING"` wipes body-b (read by nobody): tools/b.md absent AND
# staging empty. A correct hook (lock/atomic snapshot covering the producer) leaves
# body-b recoverable: tools/b.md present OR _staging.md still holds body-b.
# Deterministic, POSIX sh, deps: mktemp, mkfifo. Run from the repo root.

set -u
ROOT="${1:-.}"
HOOK="$ROOT/.agent/hooks/capture-learnings.sh"
# Absolute path: runners cd into a temp dir, so a relative HOOK would vanish.
case "$HOOK" in /*) ;; *) HOOK="$(pwd)/$HOOK" ;; esac
fail=0

# body_b_recoverable <repo>: the contract oracle. body-b is recoverable iff it was
# PERSISTED (tools/b.md exists with its body) OR LEFT in staging (still grep-able).
# Returns 0 (recoverable) / 1 (LOST).
body_b_recoverable() {
  _r="$1"
  if [ -f "$_r/.agent/memory/tools/b.md" ] && grep -q 'body-b' "$_r/.agent/memory/tools/b.md" 2>/dev/null; then
    return 0
  fi
  if grep -q 'body-b' "$_r/.agent/memory/_staging.md" 2>/dev/null; then
    return 0
  fi
  return 1
}

# --- self-test (proves the oracle isn't trivially always-pass) ------------------
self_test() {
  st_fail=0
  st_td=$(mktemp -d) || { echo "  FAIL self-test: mktemp -d"; exit 1; }
  mkdir -p "$st_td/.agent/memory/tools"
  # (a) PERSISTED: tools/b.md holds body-b, staging empty -> recoverable.
  : > "$st_td/.agent/memory/_staging.md"
  printf '# tools/b\nbody-b\n' > "$st_td/.agent/memory/tools/b.md"
  body_b_recoverable "$st_td" || { echo "  FAIL self-test: persisted tools/b.md judged LOST (oracle too strict)"; st_fail=1; }
  # (b) LEFT IN STAGING: no tools/b.md, staging still holds body-b -> recoverable.
  rm -f "$st_td/.agent/memory/tools/b.md"
  printf '## tools/b\nbody-b\n' > "$st_td/.agent/memory/_staging.md"
  body_b_recoverable "$st_td" || { echo "  FAIL self-test: staged body-b judged LOST (oracle too strict)"; st_fail=1; }
  # (c) LOST: no tools/b.md AND staging empty -> NOT recoverable (the bug state).
  : > "$st_td/.agent/memory/_staging.md"
  rm -f "$st_td/.agent/memory/tools/b.md"
  if body_b_recoverable "$st_td"; then
    echo "  FAIL self-test: missing-everywhere body-b judged recoverable (oracle too weak)"; st_fail=1
  fi
  rm -rf "$st_td"
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the loss oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (persisted OK; staged OK; absent-everywhere == LOST)"
}

echo "Checking capture-learnings does not lose a producer append during a flush: $HOOK"
[ -f "$HOOK" ] || { echo "FAIL — hook not found: $HOOK"; exit 1; }
command -v mkfifo >/dev/null 2>&1 || { echo "FAIL — mkfifo required for the deterministic race"; exit 1; }
self_test

# --- real check: drive a DETERMINISTIC producer-vs-flush race on the REAL hook ---
# Throwaway repo. Staging holds ONE section (tools/a) at flush time; the PRODUCER
# appends a SECOND (tools/b) inside the EOF->truncate window.
td=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
mkdir -p "$td/.agent/memory"
printf '## tools/a\nbody-a\n' > "$td/.agent/memory/_staging.md"

# Barrier FIFOs: mv_in — the hook's mv shim signals it has reached the final flush
# (read loop already at EOF, truncate not yet run); prod_done — we signal the shim
# that the producer's append has fully landed.
barrier=$(mktemp -d) || { echo "FAIL — mktemp -d (barrier) failed"; rm -rf "$td"; exit 1; }
mkfifo "$barrier/mv_in" "$barrier/prod_done" 2>/dev/null \
  || { echo "FAIL — mkfifo failed"; rm -rf "$td" "$barrier"; exit 1; }

# An `mv` shim, on a per-run PATH, that ONLY the hook sees. For single-section
# staging this fires from the FINAL flush (line 88->52): read loop DONE, line-92
# truncate PENDING. It announces it reached the window, blocks until the producer
# has appended tools/b, then execs the REAL mv so tools/a is persisted faithfully.
shimdir="$barrier/shim"
mkdir -p "$shimdir"
cat > "$shimdir/mv" <<SHIM
#!/bin/sh
# release the harness (hook is in the EOF -> truncate window)...
: > "$barrier/mv_in"
# ...block until the producer's append to _staging.md has fully landed...
cat "$barrier/prod_done" >/dev/null
# ...then behave as the real mv so tools/a is persisted (faithful flush).
exec /bin/mv "\$@"
SHIM
chmod +x "$shimdir/mv"

# Launch the hook with the shimmed `mv` first on PATH.
( cd "$td" && echo '{}' | PATH="$shimdir:$PATH" sh "$HOOK" >/dev/null 2>&1 ) &
hpid=$!

# Wait for the hook to enter the EOF->truncate window (its mv shim opened mv_in).
cat "$barrier/mv_in" >/dev/null

# The PRODUCER: an INDEPENDENT writer appending a NEW learning to the SAME staging,
# exactly as the agent/user would mid-session. This lands AFTER the read loop's EOF
# but BEFORE the line-92 truncate.
printf '## tools/b\nbody-b\n' >> "$td/.agent/memory/_staging.md"

# Release the hook so it finishes the real mv and runs its line-92 truncate.
: > "$barrier/prod_done"
wait "$hpid"
rcH=$?

echo "  ..   hook exited $rcH"

# THE assertion: body-b must be recoverable (persisted OR still in staging). With
# the bug it is in NEITHER — read by nobody, then wiped by line 92, rc=0 (silent).
if body_b_recoverable "$td"; then
  echo "  ok   producer's appended learning survived (persisted or left in staging)"
else
  echo "  FAIL producer's appended learning (body-b) was LOST: tools/b.md absent AND _staging.md does not contain it"
  echo "       --- .agent/memory tree ---"
  ( cd "$td/.agent/memory" && find . -type f | sed 's/^/         /' )
  echo "       --- _staging.md (bytes: $(wc -c < "$td/.agent/memory/_staging.md" 2>/dev/null)) ---"
  sed 's/^/         /' "$td/.agent/memory/_staging.md" 2>/dev/null
  fail=1
fi

rm -rf "$td" "$barrier"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — capture-learnings does not lose a learning a producer appends during a flush."
else
  echo "FAIL — .agent/hooks/capture-learnings.sh tests staging non-empty (line 36), reads it line-by-line (lines 54-87), then UNCONDITIONALLY truncates on success (line 92 ': > \"\$STAGING\"') with NO lock against the producer. A section appended in the EOF->truncate window is read by nobody and then wiped — a silent, permanent lost write (rc=0)."
fi
exit "$fail"
