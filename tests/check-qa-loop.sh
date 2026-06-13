#!/bin/sh
# check-qa-loop.sh — the steerable/bounded QA-loop GATE: replay the 4-hour post-mortem against the
# REAL decision-logic seams (lib/qa-classify.js + lib/qa-convergence.js) and the REAL report renderer
# (lib/qa-report.js), with stubbed findings/verdicts, and assert the redesign's invariants actually
# hold — not merely exist. Driven through a thin node harness (qa-loop.harness.mjs) the way
# tests/budget-breaker.fixture.sh drives budget-breaker.harness.mjs.
#
# Asserts (spec 004):
#   1. a DEFAULT run produces a ranked report and changes NO code (no branch, no edits) — SC-002.
#   2. nothing below top-tier is auto-fixed; theoretical-edge lands in BACKLOG, not fix — SC-004.
#   3. the MODERATE bar admits correctness+robustness, excludes theoretical-edge.
#   4. CONVERGENCE stops when no new at/above-bar finding appears (the marginal tail can't extend).
#   5. a BUDGET / fix-cap hit ABORTS with a partial report naming the breach — SC-005.
#   6. mode=fix scope: empty subset ⇒ no-op; only approved ids resolved against the sidecar.
#
# Self-testing like tests/check-qa-manifest.sh: a built-in self-test proves the harness can tell a
# pass from a fail, so a broken redesign can't pass by accident.
# Deterministic; deps: node, mktemp, grep. Run from the repo root.
set -u
ROOT=$(cd "${1:-.}" 2>/dev/null && pwd) || { echo "check-qa-loop: no such dir ${1:-.}"; exit 1; }
HARNESS="$ROOT/.claude/workflows/lib/qa-loop.harness.mjs"
fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

command -v node >/dev/null 2>&1 || { echo "FAIL — node not found; cannot run the QA-loop replay."; exit 1; }
[ -f "$HARNESS" ] || { echo "FAIL — missing harness: $HARNESS"; exit 1; }

# scenario <case> [extra-args...] -> prints the harness JSON for the named replay case.
scenario() { ( cd "$ROOT" && node "$HARNESS" --case "$1" ); }

# --- self-test: prove the harness reports a known-good and a known-bad differently -----------------
self_test() {
  st_fail=0
  # The 'selftest-pass' case must report ok; 'selftest-fail' must report not-ok. If the harness can't
  # distinguish them, every later assertion below is meaningless.
  scenario selftest-pass | grep -q '"selftest":"pass"' || { echo "  FAIL self-test: known-good case not reported pass"; st_fail=1; }
  scenario selftest-fail | grep -q '"selftest":"fail"' || { echo "  FAIL self-test: known-bad case not reported fail"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the QA-loop replay harness can't tell pass from fail. Aborting."
    exit 1
  fi
  echo "  ok   self-test (harness distinguishes a known-good from a known-bad replay)"
}

echo "QA-loop replay (the redesign's invariants must actually hold):"
self_test

# === 1. DEFAULT run → ranked report, NO code touched (SC-002) ==============================
echo "  case 1: default report-first run changes no code"
out=$(scenario default)
echo "$out" | grep -q '"mode":"report"'        || bad "default mode is not report-first"
echo "$out" | grep -q '"branch":null'          || bad "default run created a branch (must be null without a top-tier auto-fix)"
echo "$out" | grep -q '"codeChanged":false'    || bad "default run changed code (must be false)"
echo "$out" | grep -q '"reportRanked":true'    || bad "default run did not produce a ranked report"
echo "$out" | grep -q '"mode":"report"' && echo "$out" | grep -q '"branch":null' && echo "$out" | grep -q '"codeChanged":false' \
  && ok "default run: ranked report, no branch, no edits (SC-002)"

# === 2. Nothing below top-tier auto-fixed; theoretical-edge → BACKLOG (SC-004) =============
echo "  case 2: post-mortem replay — small fix tier, theoretical-edge in backlog"
out=$(scenario postmortem)
# The post-mortem stub: 1 genuine correctness defect + many theoretical-edge edge cases.
echo "$out" | grep -q '"autoFixed":0'             || bad "something below top-tier was auto-fixed (must be 0)"
echo "$out" | grep -q '"theoreticalInBacklog":true' || bad "theoretical-edge finding did not land in backlog"
echo "$out" | grep -q '"theoreticalInFix":false'    || bad "a theoretical-edge finding leaked into the fix tier"
# replay must yield a SMALL fix tier and a LARGER backlog (not 28 auto-fixes).
echo "$out" | grep -q '"fixTierSmall":true'         || bad "fix tier is not smaller than the backlog (post-mortem regression)"
echo "$out" | grep -q '"autoFixed":0' && echo "$out" | grep -q '"theoreticalInBacklog":true' \
  && ok "post-mortem replay: theoretical-edge → backlog, nothing below top-tier auto-fixed (SC-004)"

# === 3. The MODERATE bar admits correctness+robustness, excludes theoretical ===============
echo "  case 3: the moderate bar"
out=$(scenario moderate-bar)
echo "$out" | grep -q '"correctnessFix":true'   || bad "moderate bar did not admit correctness to the fix tier"
echo "$out" | grep -q '"robustnessFix":true'    || bad "moderate bar did not admit robustness to the fix tier"
echo "$out" | grep -q '"theoreticalFix":false'  || bad "moderate bar admitted theoretical-edge to the fix tier"
echo "$out" | grep -q '"correctnessFix":true' && echo "$out" | grep -q '"theoreticalFix":false' \
  && ok "moderate bar admits correctness+robustness, excludes theoretical-edge"

# === 4. CONVERGENCE — a below-bar-only round can't extend the run ==========================
echo "  case 4: convergence keys on at/above-bar findings"
out=$(scenario convergence)
# A run whose later rounds produce ONLY below-bar findings must stop on the dry-streak, not keep going.
echo "$out" | grep -q '"stop":"dry-streak"'      || bad "below-bar-only rounds did not converge on dry-streak"
echo "$out" | grep -q '"tailExtendedRun":false'  || bad "the marginal tail extended the run (must not)"
echo "$out" | grep -q '"stop":"dry-streak"' && echo "$out" | grep -q '"tailExtendedRun":false' \
  && ok "convergence: the below-bar marginal tail cannot extend the run (FR-B4)"

# === 5. BUDGET / fix-cap hit → graceful partial report naming the breach (SC-005) ==========
echo "  case 5: a ceiling hit aborts with a partial report"
out=$(scenario budget-abort)
echo "$out" | grep -q '"aborted":true'           || bad "a tiny budget ceiling did not abort the run"
echo "$out" | grep -q '"stop":"budget"'          || bad "the abort did not name the budget ceiling"
echo "$out" | grep -q '"partialReport":true'     || bad "the budget abort did not emit a partial ranked report"
echo "$out" | grep -q '"aborted":true' && echo "$out" | grep -q '"stop":"budget"' && echo "$out" | grep -q '"partialReport":true' \
  && ok "budget abort: graceful, partial report names the breach (SC-005)"

echo "  case 5b: a fix-cap hit also aborts with a partial report"
out=$(scenario fixcap-abort)
echo "$out" | grep -q '"stop":"max-fixes"'        || bad "the fix-cap did not stop the run"
echo "$out" | grep -q '"partialReport":true'      || bad "the fix-cap abort did not emit a partial report"
echo "$out" | grep -q '"stop":"max-fixes"' && echo "$out" | grep -q '"partialReport":true' \
  && ok "fix-cap abort: graceful, partial report (FR-C2/C4)"

# === 6. mode=fix scope: empty subset = no-op; only approved ids resolved ====================
echo "  case 6: scoped fix-run resolves only approved ids"
out=$(scenario fix-empty)
echo "$out" | grep -q '"codeChanged":false'       || bad "empty fix subset changed code (must be a no-op)"
echo "$out" | grep -q '"branch":null'             || bad "empty fix subset created a branch"
ok_empty=0; echo "$out" | grep -q '"codeChanged":false' && ok_empty=1
out=$(scenario fix-subset)
echo "$out" | grep -q '"approved":1'              || bad "fix-subset did not resolve exactly the 1 approved id"
echo "$out" | grep -q '"unknown":1'               || bad "an unknown id was not reported skipped"
[ "$ok_empty" -eq 1 ] && echo "$out" | grep -q '"approved":1' \
  && ok "scoped fix: empty subset is a no-op; only approved ids resolved, unknowns skipped (US3)"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — the QA-loop is report-first, bar-gated, convergent, bounded, and scoped."
else
  echo "FAIL — a QA-loop invariant did not hold (see above)."
fi
exit "$fail"
