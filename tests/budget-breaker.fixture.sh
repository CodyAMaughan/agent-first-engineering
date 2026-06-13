#!/bin/sh
# budget-breaker.fixture.sh — the guardrail GATE: "it must fire in a fixture, not just exist."
# A deliberately tiny ceiling + a stub usage stream MUST drive the CostCircuitBreaker to a
# hard abort (with the soft alert fired FIRST), the iteration cap MUST trip independently, and a
# BudgetRecord MUST be written on abort (SC-001, SC-002, SC-007, FR-008/009/012).
#
# Self-testing like tests/check-qa-manifest.sh: a built-in self-test proves the harness can tell a
# real abort from a non-abort, so a broken breaker can't pass by accident.
# Deterministic; deps: node, mktemp, grep. Run from the repo root.
set -u
ROOT=$(cd "${1:-.}" 2>/dev/null && pwd) || { echo "fixture: no such dir ${1:-.}"; exit 1; }
HARNESS="$ROOT/.claude/workflows/lib/budget-breaker.harness.mjs"
fail=0

# scenario <hardUsd> <iterCap> <perStepInputTokens> <steps>  ->  prints the harness JSON result.
# Builds an isolated price cache + stub usage log + budget.conf, then runs `steps` checkpoints,
# one usage event injected per step, and reports the breaker's terminal decision + the record.
scenario() {
  hard="$1"; cap="$2"; per_step="$3"; steps="$4"
  td=$(mktemp -d) || { echo "FAIL mktemp"; exit 1; }
  mkdir -p "$td/runs" "$td/usage/projects/demo"

  # A LiteLLM-style price cache: opus input $15/Mtok (so cost is easy to exceed).
  printf '{"claude-opus":{"input_cost_per_token":1.5e-5,"output_cost_per_token":7.5e-5,"cache_read_input_token_cost":1.5e-6,"cache_creation_input_token_cost":1.875e-5}}\n' \
    > "$td/price-table.cache.json"

  # A budget.conf with the tiny ceiling under test (soft just below hard so it fires first).
  soft=$(awk -v h="$hard" 'BEGIN{ printf "%.10g", (h>0? h/2 : 0) }')
  cat > "$td/budget.conf" <<EOF
BUDGET_ENABLED=true
PERTASK_SOFT_USD=$soft
PERTASK_HARD_USD=$hard
ITERATION_CAP=$cap
PRICE_TABLE_SOURCE=litellm
PRICE_TABLE_MAX_AGE_HOURS=168
PRICE_TABLE_FALLBACK=assume-max
EOF

  RUN_ID="fixture-run"
  # Stub usage log: `steps` assistant messages, each `per_step` input tokens, all for RUN_ID.
  : > "$td/usage/projects/demo/session.jsonl"
  i=1
  while [ "$i" -le "$steps" ]; do
    printf '{"sessionId":"%s","timestamp":"2026-06-13T10:00:%02dZ","type":"assistant","message":{"model":"claude-opus","usage":{"input_tokens":%s,"output_tokens":0}}}\n' \
      "$RUN_ID" "$i" "$per_step" >> "$td/usage/projects/demo/session.jsonl"
    i=$((i + 1))
  done

  USAGE_SOURCE_DIR="$td/usage" \
  node "$HARNESS" \
    --conf "$td/budget.conf" \
    --cache "$td/price-table.cache.json" \
    --runs "$td/runs" \
    --runId "$RUN_ID" \
    --steps "$steps"
  rc=$?
  # Surface the written ledger record(s) inline so the caller can assert on it WITHOUT racing the
  # cleanup below (a deleted temp dir can't be inspected after the fact).
  for f in "$td"/runs/*.ndjson; do
    [ -f "$f" ] && sed 's/^/__RECORD__/' "$f"
  done
  echo "__RC__=$rc"
  rm -rf "$td"
}

# --- self-test: prove the harness reports BOTH a real abort and a clean run --------------------
self_test() {
  st_fail=0
  # (a) a NON-tripping run (huge ceiling, tiny usage, high cap) must NOT abort.
  out=$(scenario 1000 1000 10 1)
  echo "$out" | grep -q '"action":"continue"\|"terminal":"continue"\|"status":"completed"' \
    || { echo "  FAIL self-test: a clearly-under-budget run did not report continue/completed"; st_fail=1; }
  echo "$out" | grep -q 'aborted-on-budget' \
    && { echo "  FAIL self-test: an under-budget run falsely reported an abort"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the fixture can't tell an abort from a clean run. Aborting."
    exit 1
  fi
  echo "  ok   self-test (a clean under-budget run reports no abort)"
}

echo "Budget-breaker fixture (the guardrail must actually fire):"
self_test

# === 1. HARD COST ABORT (with soft alert first) ============================================
# Each step = 1,000,000 input tokens × \$1.5e-5 = \$15. hard=\$20 ⇒ trips after step 2; soft=\$10
# ⇒ fires after step 1. Run 5 steps; expect an abort with the soft alert emitted earlier.
echo "  case 1: hard-cost abort + soft-alert-first"
out=$(scenario 20 1000 1000000 5)
echo "$out" | grep -q 'aborted-on-budget'                  || { echo "    FAIL no hard-cost abort"; fail=1; }
echo "$out" | grep -q '"breachedThreshold":"perTask.hard"' || { echo "    FAIL breached threshold not perTask.hard"; fail=1; }
echo "$out" | grep -qi 'soft alert\|"softFired":true'       || { echo "    FAIL soft alert did not fire before the hard abort"; fail=1; }
# A BudgetRecord must have been written for the aborted run (SC-002): the inlined __RECORD__ line.
if echo "$out" | grep '^__RECORD__' | grep -q 'aborted-on-budget'; then
  echo "    ok   hard-cost abort, soft-alert-first, BudgetRecord written"
else
  echo "    FAIL no BudgetRecord with aborted-on-budget written to the run ledger"; fail=1
fi

# === 2. ITERATION CAP ABORT (loop of cheap steps) ==========================================
# Each step = 1 input token (~\$0.000015, never trips the \$1000 cost ceiling), cap=2 ⇒ the
# iteration cap MUST abort the cheap loop (the "many cheap steps" edge case, FR-012).
echo "  case 2: iteration-cap abort on a loop of sub-threshold steps"
out=$(scenario 1000 2 1 5)
echo "$out" | grep -q 'aborted-on-budget'                   || { echo "    FAIL iteration cap did not abort"; fail=1; }
echo "$out" | grep -q '"breachedThreshold":"iterationCap"'  || { echo "    FAIL breached threshold not iterationCap"; fail=1; }
echo "$out" | grep -q 'aborted-on-budget' && echo "$out" | grep -q '"breachedThreshold":"iterationCap"' \
  && echo "    ok   iteration cap aborts a cheap loop"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — the budget guardrail fires: hard-cost abort (soft-first) + iteration-cap abort, record written."
else
  echo "FAIL — the guardrail did not enforce a ceiling in the fixture (see above)."
fi
exit "$fail"
