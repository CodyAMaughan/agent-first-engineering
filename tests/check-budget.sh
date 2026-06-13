#!/bin/sh
# check-budget.sh — the cost-guardrail suite oracle. Runs, in order:
#   1. node --check on every cost-core .js/.mjs (syntax can't silently rot)
#   2. node --test on the cost-engine + notional-accuracy unit tests (pricing accuracy, fail-safe)
#   3. the budget-breaker fixture (the guardrail must actually FIRE: abort + iteration cap)
# Self-testing like tests/check-qa-manifest.sh: a built-in self-test proves this script's own
# pass/fail logic catches a known break, so it can't be a trivially-always-pass gate.
# Deterministic; deps: node, mktemp. Run from the repo root.
set -u
ROOT=$(cd "${1:-.}" 2>/dev/null && pwd) || { echo "check-budget: no such dir ${1:-.}"; exit 1; }
LIB="$ROOT/.claude/workflows/lib"
fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

# run_node_check <file>: returns node's exit status. The single place we invoke `node --check`,
# so the self-test exercises the REAL command.
run_node_check() { node --check "$1" 2>&1; }

# --- self-test: prove node --check distinguishes valid from broken JS -----------------------
self_test() {
  command -v node >/dev/null 2>&1 || { echo "FAIL — node not found; cannot run the cost suite."; exit 1; }
  td=$(mktemp -d) || { echo "FAIL self-test (mktemp)"; exit 1; }
  st_fail=0
  printf 'export const ok = 1\n' > "$td/good.mjs"
  printf 'export const bad = (\n' > "$td/broken.mjs"   # unbalanced paren = syntax error
  run_node_check "$td/good.mjs"   >/dev/null 2>&1 || { echo "  FAIL self-test: valid JS rejected"; st_fail=1; }
  run_node_check "$td/broken.mjs" >/dev/null 2>&1 && { echo "  FAIL self-test: broken JS passed --check"; st_fail=1; }
  rm -rf "$td"
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the cost-suite checker can't catch a known break. Aborting."
    exit 1
  fi
  echo "  ok   self-test (node --check catches a syntax error; passes valid JS)"
}

echo "Checking the budget guardrail / cost core:"
self_test

# 1. Syntax-check every cost-core module.
for f in "$LIB"/budget-config.js "$LIB"/price-table.js "$LIB"/cost-engine.js \
         "$LIB"/usage-source.js "$LIB"/budget-breaker.js "$LIB"/budget-record.js \
         "$LIB"/budget-breaker.harness.mjs; do
  if [ -f "$f" ]; then
    if run_node_check "$f" >/dev/null 2>&1; then ok "node --check $(basename "$f")"; else bad "node --check $(basename "$f")"; fi
  else
    bad "missing cost-core file: $f"
  fi
done

# 2. Unit tests (pricing accuracy, cache-read/write own rates, fail-safe, record shape).
if ( cd "$ROOT" && node --test tests/cost-engine.test.js tests/notional-accuracy.test.js >/dev/null 2>&1 ); then
  ok "node --test (cost-engine + notional-accuracy)"
else
  bad "node --test failed (run: node --test tests/cost-engine.test.js tests/notional-accuracy.test.js)"
fi

# 3. The guardrail must FIRE in a fixture (abort + iteration cap + record written).
if ( cd "$ROOT" && sh tests/budget-breaker.fixture.sh >/dev/null 2>&1 ); then
  ok "budget-breaker fixture (guardrail aborts; iteration cap trips)"
else
  bad "budget-breaker fixture failed (run: sh tests/budget-breaker.fixture.sh)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — cost core syntactically sound, priced correctly, and the guardrail fires."
else
  echo "FAIL — see above."
fi
exit "$fail"
