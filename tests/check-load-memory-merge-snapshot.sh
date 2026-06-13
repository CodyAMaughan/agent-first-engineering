#!/bin/sh
# check-load-memory-merge-snapshot.sh — assert .agent/hooks/load-memory.sh re-injects a
# CONSISTENT snapshot of the memory wiki: it must NOT read memory files mid-merge while
# capture-learnings.sh is partway through its per-section flush, emitting a TORN wiki that
# mixes pre-merge (stale) and post-merge (new) sections.
#
# Bug under test (load-memory.sh:26-44 vs capture-learnings.sh:76-116):
#   capture-learnings persists each staged section with its OWN `mv "$tmp" "$target"`
#   (flush(), lines 76-81, driven by the merge loop 82-116) and guards capture-vs-capture
#   with $MEM_DIR/.capture.lock (mkdir, line 33). load-memory takes NO lock: it snapshots
#   the directory (`find ... | sort`, line 26) and then reads each file (`head -c`, line 41).
#   If a session starts (load-memory fires) while a capture flush is partway through that
#   per-section mv loop, load-memory's snapshot+read straddles the loop: a section whose
#   mv has ALREADY run is read as the NEW merged content, while a section whose mv has NOT
#   yet run is read in its OLD (stale) state. The re-injected wiki is internally
#   inconsistent — a mix of pre- and post-merge memory.
#
# Contract: the re-injected wiki must be a CONSISTENT single snapshot of memory — either
# all-pre-merge (capture not yet flipping sections) or all-post-merge (capture done), but
# never a straddled mix. Severity med: it degrades re-injected context fidelity (no crash).
#
# Like check-capture-learnings-staging-race.sh, this drives BOTH real hooks and makes the
# race DETERMINISTIC with a barrier (no sleeps, no flakiness) — WITHOUT editing either hook.
# We shim `mv` on a per-run PATH that ONLY the capture run sees. Staging holds 50 sections
# (tools/m1..tools/m50, each v2-body-N); the memory dir is pre-seeded with tools/m1..m50.md
# holding v1-body-N. capture's ONLY external `mv` is the per-section flush (the staging
# snapshot uses ln/rm, not mv), so every mv the shim sees persists exactly one section in
# input order. On the mv that persists tools/m5.md, the shim: (a) execs the REAL mv first
# (so tools/m5.md is now v2 on disk while m1-m4,m6-m50 are still v1 — a half-applied merge),
# (b) signals the harness to run load-memory NOW against that half-merged directory, (c)
# blocks until load-memory has fully finished reading, then returns so capture continues.
# load-memory therefore snapshots a directory where exactly ONE section is post-merge and
# the rest are pre-merge. A correct loader (same .capture.lock, or capture staging an atomic
# flip) emits a consistent snapshot: all-50-v1 OR all-50-v2. The buggy loader emits a torn
# wiki: e.g. 49 v1 sections + 1 v2 (tools/m5) — reachable ONLY by reading a half-applied merge.
# Deterministic, POSIX sh, deps: mktemp, mkfifo. Run from the repo root.

set -u
ROOT="${1:-.}"
LOADER="$ROOT/.agent/hooks/load-memory.sh"
CAPTURE="$ROOT/.agent/hooks/capture-learnings.sh"
# Absolute paths: runners cd into a temp dir, so relative hook paths would vanish.
case "$LOADER"  in /*) ;; *) LOADER="$(pwd)/$LOADER" ;; esac
case "$CAPTURE" in /*) ;; *) CAPTURE="$(pwd)/$CAPTURE" ;; esac
fail=0

N=50          # number of pre-seeded / staged sections
PIVOT=5       # the section (tools/m5) on whose mv we snapshot — must be in 1..N

# torn_count <wiki-text>: prints "<v1> <v2>" — the number of stale (v1-body) and merged
# (v2-body) section bodies present in the emitted wiki. The single oracle: a consistent
# snapshot has one of them at 0 (all-v1 or all-v2); a torn snapshot has BOTH > 0.
torn_count() {
  _w="$1"
  # grep -c exits 1 when the count is 0; capture the number unconditionally (the
  # `|| true` keeps the count, and grep -c always prints exactly one integer line).
  _v1=$(printf '%s\n' "$_w" | grep -c 'v1-body-' || true)
  _v2=$(printf '%s\n' "$_w" | grep -c 'v2-body-' || true)
  printf '%s %s' "$_v1" "$_v2"
}

# --- self-test (proves the torn oracle isn't trivially always-pass) -------------------------
self_test() {
  st_fail=0
  # (a) an all-v1 wiki is consistent (v2==0) -> NOT torn.
  w="# Project memory
<!-- a -->
v1-body-1
<!-- b -->
v1-body-2"
  set -- $(torn_count "$w")
  { [ "$1" -gt 0 ] && [ "$2" -eq 0 ]; } || { echo "  FAIL self-test: all-v1 wiki not seen as consistent (got v1=$1 v2=$2)"; st_fail=1; }
  # (b) an all-v2 wiki is consistent (v1==0) -> NOT torn.
  w="# Project memory
<!-- a -->
v2-body-1
<!-- b -->
v2-body-2"
  set -- $(torn_count "$w")
  { [ "$1" -eq 0 ] && [ "$2" -gt 0 ]; } || { echo "  FAIL self-test: all-v2 wiki not seen as consistent (got v1=$1 v2=$2)"; st_fail=1; }
  # (c) a mixed wiki is TORN (both > 0) -> the bug state.
  w="# Project memory
<!-- a -->
v1-body-1
<!-- e -->
v2-body-5"
  set -- $(torn_count "$w")
  { [ "$1" -gt 0 ] && [ "$2" -gt 0 ]; } || { echo "  FAIL self-test: mixed v1+v2 wiki not seen as torn (got v1=$1 v2=$2)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the torn-snapshot oracle is broken. Aborting."
    exit 1
  fi
  echo "  ok   self-test (all-v1 consistent; all-v2 consistent; mixed v1+v2 == torn)"
}

echo "Checking load-memory re-injects a consistent (non-torn) memory snapshot: $LOADER"
[ -f "$LOADER" ]  || { echo "FAIL — loader not found: $LOADER"; exit 1; }
[ -f "$CAPTURE" ] || { echo "FAIL — capture hook not found: $CAPTURE"; exit 1; }
command -v mkfifo >/dev/null 2>&1 || { echo "FAIL — mkfifo required for the deterministic race"; exit 1; }
self_test

# --- real check: drive a DETERMINISTIC load-vs-capture-flush race on the REAL hooks ---------
# Throwaway repo. Pre-seed tools/m1..mN.md with v1-body-N; stage tools/m1..mN (v2-body-N).
td=$(mktemp -d) || { echo "FAIL — mktemp -d failed"; exit 1; }
mkdir -p "$td/.agent/memory/tools"
n=1
while [ "$n" -le "$N" ]; do
  printf '# tools/m%s\nv1-body-%s\n' "$n" "$n" > "$td/.agent/memory/tools/m$n.md"
  n=$((n + 1))
done
{
  n=1
  while [ "$n" -le "$N" ]; do
    printf '## tools/m%s\nv2-body-%s\n' "$n" "$n"
    n=$((n + 1))
  done
} > "$td/.agent/memory/_staging.md"

# Barrier FIFOs: load_go — the capture mv shim (on the PIVOT section) signals the harness to
# run load-memory NOW (the merge is half-applied); load_done — the harness signals the shim
# that load-memory has fully finished reading, so capture may continue.
barrier=$(mktemp -d) || { echo "FAIL — mktemp -d (barrier) failed"; rm -rf "$td"; exit 1; }
mkfifo "$barrier/load_go" "$barrier/load_done" 2>/dev/null \
  || { echo "FAIL — mkfifo failed"; rm -rf "$td" "$barrier"; exit 1; }

# An `mv` shim, on a per-run PATH, that ONLY the capture run sees. capture's only external
# `mv` is the per-section flush, so each invocation persists one section. On the mv whose
# TARGET is tools/m<PIVOT>.md it first execs the real mv (m<PIVOT> becomes v2 on disk), then
# releases the harness to run load-memory against the half-merged dir and blocks until that
# read completes; every other mv just execs the real mv straight through.
shimdir="$barrier/shim"
mkdir -p "$shimdir"
cat > "$shimdir/mv" <<SHIM
#!/bin/sh
# Last arg is the destination path (flush(): mv "\$tmp" "\$target").
for _a in "\$@"; do _dst="\$_a"; done
case "\$_dst" in
  */tools/m$PIVOT.md)
    # Apply THIS section first so tools/m$PIVOT.md is v2 on disk (half-applied merge)...
    /bin/mv "\$@"
    _rc=\$?
    # ...release the harness to run load-memory NOW against the half-merged directory...
    : > "$barrier/load_go"
    # ...block until load-memory has fully finished reading the snapshot...
    cat "$barrier/load_done" >/dev/null
    exit \$_rc
    ;;
  *)
    exec /bin/mv "\$@"
    ;;
esac
SHIM
chmod +x "$shimdir/mv"

# Launch capture with the shimmed `mv` first on PATH. It will flush m1..m(PIVOT-1) (real mv),
# then PAUSE on the PIVOT section's mv until load-memory has run.
( cd "$td" && echo '{}' | PATH="$shimdir:$PATH" sh "$CAPTURE" >/dev/null 2>&1 ) &
cpid=$!

# Wait for capture to reach the half-applied point (PIVOT section just merged).
cat "$barrier/load_go" >/dev/null

# Run load-memory NOW (no shim) against the half-merged directory and capture its stdout —
# exactly a session.start re-injection firing mid-flush.
wiki=$( cd "$td" && echo '{}' | sh "$LOADER" 2>/dev/null )

# Release capture so it finishes the remaining sections.
: > "$barrier/load_done"
wait "$cpid"
rcC=$?

set -- $(torn_count "$wiki")
v1="$1"; v2="$2"
echo "  ..   capture exited $rcC; emitted wiki has v1=$v1 stale + v2=$v2 merged sections"

# THE assertion: a consistent snapshot has v1==0 (all merged) OR v2==0 (none merged yet).
# A torn snapshot has BOTH > 0 — load-memory read across capture's per-section mv loop.
if { [ "$v1" -eq 0 ] || [ "$v2" -eq 0 ]; }; then
  echo "  ok   re-injected wiki is a consistent snapshot (all-v1 or all-v2)"
else
  echo "  FAIL re-injected wiki is TORN: $v1 stale (v1-body) + $v2 merged (v2-body) sections — load-memory read a half-applied merge"
  echo "       --- merged (v2) sections in the emitted wiki ---"
  printf '%s\n' "$wiki" | grep -n 'v2-body-' | sed 's/^/         /'
  fail=1
fi

rm -rf "$td" "$barrier"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — load-memory re-injects a consistent memory snapshot (never a half-applied merge)."
else
  echo "FAIL — .agent/hooks/load-memory.sh takes NO lock (snapshots with find|sort line 26, reads with head -c line 41), while capture-learnings.sh persists each section with its own mv (flush(), lines 76-81) under only the capture-vs-capture .capture.lock (line 33). A session.start re-injection that fires mid-flush straddles the per-section mv loop and emits a torn wiki mixing pre- and post-merge memory."
fi
exit "$fail"
