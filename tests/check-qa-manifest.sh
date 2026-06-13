#!/bin/sh
# check-qa-manifest.sh — assert the adversarial QA loop's manifest is well-formed:
# every path in QA_TARGETS (.agent/qa.conf) must exist. If the QA loop points an
# adversary at a file that has moved or been deleted, the run silently skips a real
# system-under-test — so this is the QA loop's OWN oracle, and (like check-footnotes.sh)
# it runs a built-in self-test first to prove it isn't trivially always-pass.
# Deterministic, POSIX sh, deps: mktemp. Run from the repo root.

set -u
ROOT="${1:-.}"
CONF="$ROOT/.agent/qa.conf"
fail=0

# check_manifest <conf> <root>: prints "MISSING <path>" for each QA_TARGETS entry that
# does not exist under <root>, and returns non-zero if any are missing. Sourced in a
# subshell so QA_TARGETS never leaks into the caller. This single function is the only
# place the manifest grammar lives, so the self-test exercises the REAL check.
check_manifest() {
  conf="$1"; root="$2"
  [ -f "$conf" ] || { echo "MISSING-CONF $conf"; return 1; }
  ( . "$conf" 2>/dev/null
    : "${QA_TARGETS:?QA_TARGETS not set in $conf}"
    bad=0
    for t in $QA_TARGETS; do
      [ -e "$root/$t" ] || { echo "MISSING $t"; bad=1; }
    done
    exit $bad
  )
}

# --- self-test (proves the detector catches a known break) ---------------------------------
self_test() {
  td=$(mktemp -d) || { echo "FAIL self-test (mktemp failed)"; exit 1; }
  st_fail=0
  # (a) a manifest with a bogus target must be caught and named.
  printf 'QA_TARGETS="tests/check-qa-manifest.sh does/not/exist.xyz"\n' > "$td/bad.conf"
  out=$(check_manifest "$td/bad.conf" "$ROOT"); rc=$?
  [ "$rc" -ne 0 ]                              || { echo "  FAIL self-test: clean exit on a manifest with a missing target"; st_fail=1; }
  echo "$out" | grep -q '^MISSING does/not/exist.xyz$' || { echo "  FAIL self-test: missing target not reported"; st_fail=1; }
  # (b) a fully-valid manifest must pass (no false positive).
  printf 'QA_TARGETS="tests/check-qa-manifest.sh"\n' > "$td/ok.conf"
  check_manifest "$td/ok.conf" "$ROOT" >/dev/null 2>&1 || { echo "  FAIL self-test: false-positive on a valid manifest"; st_fail=1; }
  # (c) a missing conf file must be caught.
  check_manifest "$td/nope.conf" "$ROOT" >/dev/null 2>&1 && { echo "  FAIL self-test: missing conf not caught"; st_fail=1; }
  rm -rf "$td"
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the manifest checker cannot catch a known break. Aborting."
    exit 1
  fi
  echo "  ok   self-test (missing target + missing conf caught; valid manifest passes)"
}

echo "Checking QA manifest: $CONF"
self_test

# --- real check ----------------------------------------------------------------------------
miss=$(check_manifest "$CONF" "$ROOT") || fail=1
if [ "$fail" -eq 0 ]; then
  echo "  ok   all QA_TARGETS exist"
else
  echo "$miss" | sed 's/^/         /'
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — QA manifest is well-formed (every system-under-test exists)."
else
  echo "FAIL — fix .agent/qa.conf: a QA_TARGETS path is missing (moved/deleted/typo)."
fi
exit "$fail"
