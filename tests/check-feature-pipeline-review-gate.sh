#!/bin/sh
# check-feature-pipeline-review-gate.sh — assert the feature-pipeline's adversarial
# Review gate is BLOCKING, at parity with the Spec / Plan / Implement gates.
#
# The bug (false gate verdict, in the QA threat model): Spec/Plan/Implement each end with
#   `if (!gate.pass) return { stoppedAt: <Stage>, ... }`
# so an unmet gate caps the pipeline with a stop verdict. The Review loop (feature-pipeline.js
# lines 103-115) `break`s only on `revGate.pass`; when maxReviewRounds is exhausted with
# `revGate.pass === false` (e.g. an unresolved SQLi finding) there is NO trailing
# `if (!revGate.pass) return { stoppedAt: 'Review', ... }`. Execution falls through to
# `phase('Ready')` and returns the normal SUCCESS-shaped completion object (no `stoppedAt`),
# laundering the failure into the plain string field `review: 'has-unresolved-findings ...'`.
# An unresolved security/correctness review thus reports a terminal "ready for human PR" result
# indistinguishable in SHAPE from a clean pass.
#
# Why a Node harness, not `sh feature-pipeline.js`: the target is NOT a shell script. It is a
# harness-injected ES-module BODY that uses top-level `return`/`await` and runtime-injected
# globals (args, agent, phase, log). Proof the naive recipe is invalid:
#   $ node --input-type=module --check < .claude/workflows/feature-pipeline.js
#   SyntaxError: Illegal return statement   (the top-level `return` at line 60)
# So we embed the file's EXACT body — only the leading `export ` stripped so top-level
# return/await are legal inside an async function — into the same async-function harness the
# workflow runtime provides, stubbing agent/phase/log/args. This tracks the REAL file: the body
# is read verbatim at run time, never re-typed here.
#
# Like check-qa-manifest.sh / check-test-gate-json.sh, a built-in self-test runs first to prove
# the oracle isn't trivially always-pass: with the SAME harness it confirms (a) a forced Plan-gate
# failure yields stoppedAt:'Plan' (the parity property is real and detectable), and (b) an all-pass
# run reaches Ready with no stoppedAt. Only then does the real check force ONLY the Review gate.
#
# Deterministic, POSIX sh, deps: mktemp, node. Run from the repo root.

set -u
ROOT="${1:-.}"
TARGET="$ROOT/.claude/workflows/feature-pipeline.js"
# Absolute path: the harness cd's into a temp dir, so a relative TARGET would vanish.
case "$TARGET" in /*) ;; *) TARGET="$(pwd)/$TARGET" ;; esac
fail=0

[ -f "$TARGET" ] || { echo "FAIL — target not found: $TARGET"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL — node not on PATH (required to drive the ES-module body)"; exit 1; }

echo "Checking feature-pipeline Review gate is blocking: $TARGET"

# run_pipeline <fail_stage>: drive the VERBATIM target body in a stub harness, forcing exactly
# one gate to fail. <fail_stage> is one of: spec | plan | implement | review | none.
# Echoes the JSON the pipeline returned (its completion / stop verdict). The agent() stub:
#   - returns the Setup config (so the pipeline can proceed),
#   - returns {pass:false, issues:[...]} ONLY for the *review* label of the targeted stage,
#   - returns {pass:true, ...} for every other gate,
#   - is a no-op for non-gate (draft / branch / fix) calls.
run_pipeline() {
  fail_stage="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; return 1; }
  # Strip ONLY the leading `export ` from `export const meta`/etc. so top-level return/await are
  # legal inside the async wrapper. The rest of the body is byte-for-byte the real file.
  sed 's/^export //' "$TARGET" > "$td/body.mjs.txt"

  # Quoted heredoc: the SHELL expands NOTHING here. The body text and the fail-stage are read at
  # runtime from a file / env var, so the JS variable ${BODY} below is never shell-expanded.
  cat > "$td/run.mjs" <<'EOF'
import { readFileSync } from 'node:fs'
const BODY = readFileSync(process.env.PIPELINE_BODY, 'utf8')
const FAIL_STAGE = process.env.FAIL_STAGE

const phases = []
const phase = (t) => phases.push(t)
const log = () => {}
const args = { feature: 'add login endpoint' }

// agent(prompt, opts) — opts.label is e.g. "spec:review#1", "plan:review#1",
// "implement:test-gate#1", "review#1". opts.schema present => a structured (gate/config) return.
const PASS = { pass: true, summary: 'ok', issues: [] }
function gateFor(label) {
  const stageOf = (l) =>
    l.startsWith('spec:review')          ? 'spec'      :
    l.startsWith('plan:review')          ? 'plan'      :
    l.startsWith('implement:test-gate')  ? 'implement' :
    l.startsWith('review#')              ? 'review'    : null
  const stage = stageOf(label)
  if (stage && stage === FAIL_STAGE) {
    return { pass: false, summary: stage + ' gate forced-fail', issues: ['SQLi: unsanitized input concatenated into query'] }
  }
  return PASS
}
async function agent(prompt, opts = {}) {
  const label = (opts && opts.label) || ''
  // Setup config call: identified by its schema's required keys (has 'slug').
  if (opts.schema && Array.isArray(opts.schema.required) && opts.schema.required.includes('slug')) {
    return {
      slug: 'demo', baseBranch: 'main', branchPrefix: 'feat/',
      maxSpecRounds: 2, maxPlanRounds: 2, maxImplementRounds: 6, maxReviewRounds: 2,
      reviewSubagent: 'code-reviewer',
    }
  }
  // Any other schema'd call is a GATE.
  if (opts.schema) return gateFor(label)
  // Non-gate calls (draft / branch / fix) are no-ops.
  return { note: 'noop:' + label }
}

// Compile the VERBATIM body as an async function whose params are the runtime-injected globals
// the workflow harness provides (args, agent, phase, log). The body uses top-level return/await,
// which are legal inside an async function — exactly the contract the real harness relies on.
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const run = new AsyncFunction('args', 'agent', 'phase', 'log', BODY)
const RESULT = await run(args, agent, phase, log)

process.stdout.write(JSON.stringify({ phases, result: RESULT }))
EOF

  out=$(PIPELINE_BODY="$td/body.mjs.txt" FAIL_STAGE="$fail_stage" node "$td/run.mjs" 2>"$td/err.txt"); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "NODE-FAIL rc=$rc"
    sed 's/^/  node-stderr: /' "$td/err.txt" >&2
  fi
  printf '%s' "$out"
  rm -rf "$td"
  return "$rc"
}

# JSON field probes (python3 if present, else grep — the shapes are simple & flat).
has_stopped_at() { # <json> <stage>  -> 0 if result.stoppedAt === <stage>
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d.get("result",{}).get("stoppedAt")=="'"$2"'" else 1)' 2>/dev/null
  else
    printf '%s' "$1" | grep -q "\"stoppedAt\"[[:space:]]*:[[:space:]]*\"$2\""
  fi
}
reached_ready() { # <json> -> 0 if "Ready" is in phases AND result has no stoppedAt
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;d=json.load(sys.stdin);ph=d.get("phases",[]);r=d.get("result",{});sys.exit(0 if ("Ready" in ph and "stoppedAt" not in r) else 1)' 2>/dev/null
  else
    printf '%s' "$1" | grep -q '"Ready"' && ! printf '%s' "$1" | grep -q '"stoppedAt"'
  fi
}

# --- self-test (proves the harness drives the REAL body and the oracle isn't always-pass) ---
self_test() {
  st_fail=0
  # (a) Force the PLAN gate to fail: the real body's line-77 guard MUST stop at 'Plan'.
  #     This proves the harness genuinely executes the gate guards (oracle is not vacuous).
  out=$(run_pipeline plan); rc=$?
  [ "$rc" -eq 0 ] || { echo "  FAIL self-test: harness errored driving the body (plan case, rc=$rc)"; st_fail=1; }
  if has_stopped_at "$out" "Plan"; then
    :
  else
    echo "  FAIL self-test: forced Plan-gate failure did NOT yield stoppedAt:'Plan' — harness/oracle broken"
    echo "        got: $out"
    st_fail=1
  fi
  # (b) All gates pass: the pipeline MUST reach Ready with no stoppedAt (no false positive).
  out=$(run_pipeline none); rc=$?
  [ "$rc" -eq 0 ] || { echo "  FAIL self-test: harness errored driving the body (none case, rc=$rc)"; st_fail=1; }
  if reached_ready "$out"; then
    :
  else
    echo "  FAIL self-test: an all-pass run did not reach Ready cleanly (oracle too strict)"
    echo "        got: $out"
    st_fail=1
  fi
  if [ "$st_fail" -ne 0 ]; then
    echo "FAIL — self-test failed; the harness/oracle cannot tell a stop verdict from a clean pass. Aborting."
    exit 1
  fi
  echo "  ok   self-test (forced Plan-gate failure stops at 'Plan'; all-pass reaches Ready cleanly)"
}

self_test

# --- real check: force ONLY the Review gate to fail (unresolved SQLi finding) ---------------
# By parity with Spec/Plan/Implement, this MUST cap the pipeline with stoppedAt:'Review'.
# The buggy code instead falls through to phase('Ready') and returns the success-shaped object.
out=$(run_pipeline review); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "  FAIL harness errored driving the body (review case, rc=$rc)"
  fail=1
elif has_stopped_at "$out" "Review"; then
  echo "  ok   unresolved Review gate caps the pipeline with stoppedAt:'Review'"
else
  echo "  FAIL Review gate is NON-BLOCKING: an unresolved review reached a terminal completion"
  echo "       (no stoppedAt:'Review'; failure laundered into the 'review' string field):"
  printf '%s\n' "$out" | sed 's/^/         /'
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — feature-pipeline's Review gate is blocking, at parity with Spec/Plan/Implement."
else
  echo "FAIL — feature-pipeline's adversarial Review gate is non-blocking: after maxReviewRounds with"
  echo "       unresolved must-fix findings it falls through to phase('Ready') and returns a"
  echo "       success-shaped completion (no stoppedAt:'Review'), unlike the other three gates."
fi
exit "$fail"
