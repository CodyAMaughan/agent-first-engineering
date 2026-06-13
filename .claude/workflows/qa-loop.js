// qa-loop.js — the STEERABLE, BOUNDED, REPORT-FIRST adversarial QA-loop (spec 004).
//
// Default `mode: report`: generate → dedup → verify(+impact) → rank → write a ranked triage report →
// STOP. No branch, no code change, EXCEPT a narrow autonomous lane that may auto-fix only unambiguous
// top-tier (data-loss/security, high-confidence) findings. `mode: fix` fixes only a human-approved id
// subset (resolved against the qa-<date>.json sidecar) on one branch with a fast fix-gate; `mode:
// autofix` is the opt-in full-auto path. Every mode is bounded by 003's budget primitive + QA_MAX_FIXES
// + a rounds cap + optional wall-clock; any ceiling → break→Triage → a PARTIAL ranked report.
//
// The PURE decision logic lives in lib/qa-classify.js + lib/qa-convergence.js + lib/qa-report.js and is
// unit-tested under `node --test` (the runtime's agent()/parallel()/budget() can't run there). This
// file is the agent()-bound glue; tests/check-qa-loop.sh replays the post-mortem against the same seams.
//
// The Workflow runtime wraps this file's body in an async function (so top-level `await`/`return` work),
// which means static `import` is unavailable — the budget core + decision seams are pulled in via
// dynamic import() at the top of the body. The module URL is resolved relative to this file.
export const meta = {
  name: 'qa-loop',
  description: 'Steerable, bounded, REPORT-FIRST adversarial QA. Default mode generates → verifies (classifying each finding by real-world impact under the threat model) → ranks → writes a triage report → STOPS (no branch, no code change) except a narrow auto-fix lane for unambiguous data-loss/security findings. mode=fix fixes only a human-approved id subset on one branch with a fast fix-gate (regression + affected checks per fix; full TEST_CMD once at end). Every run is bounded by spec 003\'s budget + QA_MAX_FIXES + a rounds cap; any ceiling → graceful partial report. Config in .agent/qa.conf; the full oracle is TEST_CMD from .agent/lifecycle.conf.',
  phases: [
    { title: 'Target-select', detail: 'read .agent/qa.conf + lifecycle.conf + budget.conf; resolve mode, scope, bar, ceilings' },
    { title: 'Generate',      detail: 'one qa-adversary per lens fans out candidate findings (+proposedImpact) with repro recipes' },
    { title: 'Verify',        detail: 'qa-verifier REPRODUCES each deduped candidate AND classifies its impact under the threat model' },
    { title: 'Rank',          detail: 'tier each confirmed finding (fix vs backlog) by impact vs QA_MIN_SEVERITY; pick the auto-fix lane' },
    { title: 'Fix',           detail: 'mode=fix/autofix or the auto-fix lane: RED-first, fast gate (regression + affected), full TEST_CMD once at end' },
    { title: 'Triage',        detail: 'write the ranked report (.md + .json sidecar) on EVERY terminating path, naming any breached ceiling' },
  ],
}

// ---- args (contracts/workflow-args.md) ----------------------------------------------------------
// { mode?, targets?: string[]|group, minSeverity?, fix?: string[], dateStamp?: 'YYYY-MM-DD' }
const A = (args && typeof args === 'object') ? args : {}
const dateStamp = A.dateStamp || 'latest'   // never new Date() inline (determinism)

// ---- pull in the pure decision seams + 003's budget core (dynamic import — see header note) -----
const { resolveConfig, tierFor, isTopTierAutoFixable, resolveFixSubset } = await import('./lib/qa-classify.js')
const { qualifyingCount, bumpDryStreak, evaluateStop, affectedChecks } = await import('./lib/qa-convergence.js')
const { buildSidecar, renderMarkdown } = await import('./lib/qa-report.js')
const { readBudgetConfig } = await import('./lib/budget-config.js')
const { BudgetBreaker } = await import('./lib/budget-breaker.js')

// ---- schemas ------------------------------------------------------------------------------------
const CONF = {
  type: 'object',
  properties: {
    lenses:        { type: 'array', items: { type: 'string' } },
    targets:       { type: 'array', items: { type: 'string' } },
    maxRounds:     { type: 'number' },
    dryStreakStop: { type: 'number' },
    maxFixes:      { type: 'number' },
    minSeverity:   { type: 'string' },
    mode:          { type: 'string' },
    affectedMap:   { type: 'object' },
    testCmd:       { type: 'string' },
    threatModel:   { type: 'string' },
  },
  required: ['lenses', 'targets', 'maxRounds', 'dryStreakStop', 'maxFixes', 'minSeverity', 'mode', 'testCmd', 'threatModel'],
}
const FINDING = {
  type: 'object',
  properties: {
    target:         { type: 'string' },
    line:           { type: 'number' },
    class:          { type: 'string' },   // boundary|threat-evasion|race|encoding|gate-false-verdict|dos
    claim:          { type: 'string' },
    repro:          { type: 'string' },    // literal input + exact command + expected-vs-actual
    proposedSeverity: { type: 'string' },  // high|med|low (advisory)
    proposedImpact: { type: 'string' },    // advisory impact hint; the verifier decides authoritatively
  },
  required: ['target', 'line', 'class', 'claim', 'repro'],
}
const FINDINGS = { type: 'object', properties: { findings: { type: 'array', items: FINDING } }, required: ['findings'] }
const VERDICT = {  // contracts/verdict-schema.md — EXTENDED with impact classification
  type: 'object',
  properties: {
    verdict:          { type: 'string' },  // CONFIRMED|WORKS-AS-INTENDED|WRONG-THREAT-MODEL|LOW-SEV-DEFER
    reproduced:       { type: 'boolean' },
    evidence:         { type: 'string' },  // literal command + captured exit/output, or the reject reason
    impact:           { type: 'string' },  // data-loss|security|correctness|robustness|theoretical-edge
    impactConfidence: { type: 'string' },  // high|low — low on a top-tier class blocks the auto-fix lane
    impactRationale:  { type: 'string' },  // ties the class to the threat model; recorded in the report
  },
  required: ['verdict', 'reproduced', 'evidence', 'impact', 'impactConfidence', 'impactRationale'],
}
const GATE = {
  type: 'object',
  properties: { pass: { type: 'boolean' }, summary: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } } },
  required: ['pass', 'summary', 'issues'],
}

// ---- Target-select: resolve config from qa.conf + args via the pure seam -------------------------
phase('Target-select')
const raw = await agent(
  `Read .agent/qa.conf and .agent/lifecycle.conf and return its KEY=value config plus the TEST_CMD. ` +
  `Return: lenses=QA_LENSES; targets=${Array.isArray(A.targets) ? JSON.stringify(A.targets) : 'the QA_TARGETS list (the full manifest)'}; ` +
  `maxRounds=QA_MAX_ROUNDS (default 4); dryStreakStop=QA_DRY_STREAK (default 2); maxFixes=QA_MAX_FIXES (default 5); ` +
  `minSeverity=${A.minSeverity ? JSON.stringify(A.minSeverity) : 'QA_MIN_SEVERITY (default moderate)'}; ` +
  `mode=${A.mode ? JSON.stringify(A.mode) : 'QA_MODE (default report)'}; ` +
  `affectedMap = QA_AFFECTED_MAP parsed into {target:[checks]} (default {}); ` +
  `threatModel=QA_THREAT_MODEL; testCmd = TEST_CMD from .agent/lifecycle.conf (the FULL oracle). Do not edit anything.`,
  { label: 'qa:config', phase: 'Target-select', schema: CONF })

// Re-resolve through the PURE seam so absent config can never yield unbounded auto-fix (FR-CFG2):
// the agent reads the files, but resolveConfig() owns the defaults + the args>conf>default precedence.
const cfg = resolveConfig(
  {
    QA_MODE: raw.mode, QA_MIN_SEVERITY: raw.minSeverity, QA_MAX_FIXES: String(raw.maxFixes),
    QA_MAX_ROUNDS: String(raw.maxRounds), QA_DRY_STREAK: String(raw.dryStreakStop),
    QA_TARGETS: (raw.targets || []).join(' '),
  },
  A,
)
cfg.lenses = raw.lenses || []
cfg.testCmd = raw.testCmd
cfg.threatModel = raw.threatModel
cfg.affectedMap = raw.affectedMap || cfg.affectedMap || {}

// ---- Bounded execution: WIRE IN 003's budget primitive (FR-C1; the live integration 003 deferred) --
// Feature-detect + degrade gracefully (research R7): an absent/disabled budget.conf ⇒ a no-op breaker;
// the non-budget ceilings (QA_MAX_FIXES, QA_MAX_ROUNDS, wall-clock) still bound the run.
let budgetConfig = { enabled: false }
try { budgetConfig = readBudgetConfig('.agent/budget.conf') } catch (e) { log(`[qa] budget.conf unreadable, degrading: ${e.message}`) }
const breaker = new BudgetBreaker(budgetConfig, null, (typeof budget !== 'undefined' ? budget : null), {
  runId: meta.name,
  log: (m) => log(m),
})
if (!budgetConfig.enabled) log('[qa] budget guardrail disabled/absent — running on QA_MAX_FIXES + QA_MAX_ROUNDS ceilings only.')

log(`Mode: ${cfg.mode} | bar: ${cfg.minSeverity} | targets (${cfg.targets.length}): ${cfg.targets.join(', ')}\n` +
    `Ceilings: maxRounds=${cfg.maxRounds}, dryStreak=${cfg.dryStreak}, maxFixes=${cfg.maxFixes}, budget=${budgetConfig.enabled ? 'on' : 'off'}.`)

// ================================================================================================
// mode: fix — scoped fix-run over a human-approved id subset (US3). No discovery; resolve ids
// against the latest sidecar, fix ONLY approved ids on one branch, fast gate per fix, full suite once.
// ================================================================================================
if (cfg.mode === 'fix') {
  const result = await runScopedFix(cfg, breaker)
  breaker.onRunEnd(null, { workflowType: 'qa-loop' })
  return result
}

// ================================================================================================
// mode: report (default) / autofix — discovery round loop, then rank + (auto-fix lane | full auto).
// ================================================================================================
const seen = new Set()                       // dedup keys across all rounds (anti re-litigation)
const ranked = []                            // confirmed findings, each tiered
const rejected = []                          // {id, verdict, why}
let dryStreak = 0
let round = 0
let fixCount = 0
let branch = null
let stop = null

const keyOf = (f) => `${(f.target || '').split('/').pop()}:${f.line}:${f.class}`

while (true) {
  // ---- ceiling check at the TOP of each round (budget via 003, plus the QA-local caps) ----------
  const bp = breaker.checkpoint(meta.name)
  const budgetBreached = bp.action === 'abort'
  stop = evaluateStop(
    { round, dryStreak, fixCount, budgetBreached },
    { maxRounds: cfg.maxRounds, dryStreakStop: cfg.dryStreak, maxFixes: cfg.maxFixes },
  )
  if (stop) break
  round++

  // ---- Generate (fan-out, one agent per lens) --------------------------------------------------
  phase('Generate')
  const batches = await parallel(cfg.lenses.map((lens) => () => agent(
    `First read .claude/agents/qa-adversary.md and ADOPT that role fully. Then: lens = "${lens}". ` +
    `Targets: ${JSON.stringify(cfg.targets)}. Round ${round}. Read the real code and produce candidate ` +
    `FAILURE findings for THIS lens only, each with file:line, a one-line claim, a concrete repro recipe ` +
    `(literal input + exact command + expected-vs-actual), and a PROPOSED impact hint ` +
    `(data-loss|security|correctness|robustness|theoretical-edge). THREAT MODEL: ${cfg.threatModel} ` +
    `Do NOT report findings that presuppose file-write/RCE. ` +
    `Do NOT re-report these already-seen ids: ${JSON.stringify([...seen])}. Read-only; edit nothing.`,
    { label: `gen:${lens}#${round}`, phase: 'Generate', schema: FINDINGS }
  )))

  // ---- Dedup (plain JS) ------------------------------------------------------------------------
  const fresh = []
  for (const b of batches) {
    if (!b || !Array.isArray(b.findings)) continue
    for (const f of b.findings) {
      const id = keyOf(f)
      if (seen.has(id)) continue
      seen.add(id); fresh.push({ ...f, id })
    }
  }
  log(`Round ${round}: ${fresh.length} new candidate(s) after dedup (seen=${seen.size}).`)

  // ---- Verify (reproduce-or-reject) + classify impact ------------------------------------------
  phase('Verify')
  const confirmedThisRound = []
  for (const f of fresh) {
    // Re-check the budget after each verify so a long round still aborts promptly (break→Triage).
    const vp = breaker.checkpoint(meta.name)
    if (vp.action === 'abort') {
      // mid-verify abort: record the pending finding as unverified-at-abort, never silently dropped.
      ranked.push({ ...f, impact: f.proposedImpact || 'theoretical-edge', impactConfidence: 'low', impactRationale: 'ceiling tripped before verification', tier: 'unverified-at-abort', recommendation: 're-run to verify', fixBranch: null })
      stop = 'budget'
      break
    }
    const v = await agent(
      `First read .claude/agents/qa-verifier.md and ADOPT that role fully (hostile skeptic). ` +
      `Candidate: ${JSON.stringify(f)}. REPRODUCE it against the real code or REJECT it: (1) mktemp -d; ` +
      `(2) write the minimal failing input there and run the real target, capturing exit code + output; ` +
      `(3) rm -rf the temp dir. CONFIRMED requires reproduced=true AND the literal command + captured ` +
      `output in evidence. DEFAULT TO REJECTING. THEN CLASSIFY IMPACT under the threat model ` +
      `(data-loss|security|correctness|robustness|theoretical-edge): a reproducible-but-implausible ` +
      `finding (exotic encoding, race on a never-concurrent hook) is theoretical-edge. Ambiguous ⇒ assign ` +
      `the HIGHER class and name both in impactRationale. State impactConfidence (high|low). ` +
      `Threat model: ${cfg.threatModel} Edit nothing tracked.`,
      { label: `verify:${f.id}`, phase: 'Verify', schema: VERDICT })

    const confirmed = v.verdict === 'CONFIRMED' && v.reproduced === true && !!v.impact
    if (!confirmed) { rejected.push({ id: f.id, verdict: v.verdict, why: v.evidence }); continue }

    const tier = tierFor(v.impact, cfg.minSeverity)
    const rf = {
      id: f.id, target: f.target, line: f.line, class: f.class, claim: f.claim, repro: f.repro,
      evidence: v.evidence, impact: v.impact, impactConfidence: v.impactConfidence,
      impactRationale: v.impactRationale, tier,
      recommendation: tier === 'fix' ? 'fix' : `won't-fix — ${v.impactRationale}`,
      fixBranch: null,
    }
    ranked.push(rf)
    if (qualifyingCount([rf], cfg.minSeverity) > 0) confirmedThisRound.push(rf)
  }
  if (stop) break

  // ---- the narrow top-tier AUTO-FIX lane (mode=report) / full auto (mode=autofix) ---------------
  const lane = ranked.filter((rf) => rf.tier === 'fix' && (cfg.mode === 'autofix' || isTopTierAutoFixable(rf)) && rf.fixBranch === null && rf.tier !== 'auto-fixed')
  for (const rf of lane) {
    if (fixCount >= cfg.maxFixes) { stop = 'max-fixes'; break }
    if (breaker.checkpoint(meta.name).action === 'abort') { stop = 'budget'; break }
    branch = await ensureBranch(branch)
    const ok = await applyScopedFix(rf, branch, cfg, /* full suite at end */ false)
    if (ok) { rf.tier = 'auto-fixed'; rf.fixBranch = branch; fixCount++ }
  }
  if (stop) break

  // ---- convergence: keyed on at/above-bar findings (FR-B4) -------------------------------------
  dryStreak = bumpDryStreak(dryStreak, qualifyingCount(confirmedThisRound, cfg.minSeverity))
  log(`Round ${round}: qualifying=${confirmedThisRound.length}, dryStreak=${dryStreak}/${cfg.dryStreak}, fixes=${fixCount}/${cfg.maxFixes}.`)
}

if (!stop) stop = evaluateStop({ round, dryStreak, fixCount }, { maxRounds: cfg.maxRounds, dryStreakStop: cfg.dryStreak, maxFixes: cfg.maxFixes }) || 'dry-streak'

// If anything was auto-fixed, run the full TEST_CMD ONCE at the end (FR-D2).
if (branch) {
  phase('Fix')
  await agent(
    `Run the FULL oracle (TEST_CMD from .agent/lifecycle.conf) from the repo root on branch ${branch} ` +
    `as the single end-of-run integration gate. Do NOT edit files; report pass/fail + the failing tail.`,
    { label: 'fix:full-suite', phase: 'Fix', schema: GATE })
}

const result = await writeTriage(cfg, ranked, rejected, { rounds: round, stop, branch, spend: budgetConfig.enabled ? { usd: breaker.state.spentUsd, tokens: breaker.state.spentTokens } : null })
breaker.onRunEnd(null, { workflowType: 'qa-loop' })
return result

// ================================================================================================
// helpers
// ================================================================================================
async function ensureBranch(current) {
  if (current) return current
  const b = await agent(
    `Create and switch to a new git branch for QA fixes: name it "qa/loop-fixes-${dateStamp === 'latest' ? '$(date +%Y%m%d)' : dateStamp}" ` +
    `(git checkout -b if it doesn't exist; else switch to it). Report ONLY the exact current branch name.`,
    { label: 'fix:branch', phase: 'Fix' })
  return (b || '').trim().split(/\s+/).pop() || 'qa/loop-fixes'
}

// applyScopedFix — RED-first fix of one finding with the FAST fix-gate (FR-D1): the new regression
// case + the directly-affected checks only, NOT the full TEST_CMD (which runs once at end of run).
async function applyScopedFix(rf, branch, cfg, runFullSuiteNow) {
  const affected = affectedChecks(rf.target, cfg.affectedMap)
  let gate = { pass: false, summary: '', issues: [] }
  let redProven = false
  for (let i = 1; i <= 4; i++) {
    if (i === 1) {
      await agent(
        `CONFIRMED ${rf.impact} defect on branch ${branch} in ${rf.target}: ${rf.claim}\nRepro: ${rf.repro}\nEvidence: ${rf.evidence}\n` +
        `STEP 1 (RED): add a regression case encoding this repro — extend the target's own self_test() if it has one, ` +
        `else add a case to tests/validate.sh, else a new tests/check-*.sh. Run ONLY that new case and CONFIRM IT FAILS ` +
        `(prove RED). Do NOT touch ${rf.target} yet. Commit the RED test. Report the failing output.`,
        { label: `fix:red#${rf.id}`, phase: 'Fix' })
    } else {
      await agent(
        `STEP 2 (GREEN) on branch ${branch}: fix ${rf.target} so the regression case passes — minimal change, do NOT ` +
        `weaken any existing assertion, do NOT edit the regression test to pass. Previous gate: ${gate.summary}. Commit. Report the diff.`,
        { label: `fix:green#${rf.id}@${i}`, phase: 'Fix' })
    }
    // FAST gate: only the new regression case + the directly-affected checks (NOT the full suite).
    gate = await agent(
      `FAST fix-gate on branch ${branch}: run ONLY (a) the new regression case for ${rf.id} and (b) these directly-affected ` +
      `checks: ${JSON.stringify(affected)}. Do NOT run the full TEST_CMD here (it runs once at end-of-run). pass=true ONLY if ` +
      `every one of those exits 0 AND the new case exists and asserts. Do NOT edit files; report (failing tail in summary).`,
      { label: `fix:gate#${rf.id}@${i}`, phase: 'Fix', schema: GATE })
    if (i === 1) { redProven = (gate.pass === false); gate.pass = false; continue } // round 1 is RED-proof only
    if (gate.pass) break
  }
  return gate.pass && redProven
}

// runScopedFix — mode=fix: resolve the approved subset against the latest sidecar, fix only those ids
// on one branch with the fast gate, then the full TEST_CMD once at end (US3 / FR-D2).
async function runScopedFix(cfg, breaker) {
  phase('Rank')
  const json = await agent(
    `Read the latest QA report sidecar at qa/reports/qa-${dateStamp}.json (if dateStamp is "latest", read the most recent ` +
    `qa/reports/qa-*.json). Return its parsed JSON exactly (meta + findings). If none exists, return {"findings":[]}.`,
    { label: 'fix:load-sidecar', phase: 'Rank', schema: { type: 'object', properties: { meta: { type: 'object' }, findings: { type: 'array', items: { type: 'object' } } }, required: ['findings'] } })

  const { approved, unknown } = resolveFixSubset(json, cfg.fixIds)
  log(`Scoped fix: ${approved.length} approved, ${unknown.length} unknown id(s) skipped: ${JSON.stringify(unknown)}.`)
  if (!approved.length) {
    // Empty/absent approved subset ⇒ no code change (US3-#3).
    return await writeTriage(cfg, [], [], { rounds: 0, stop: 'dry-streak', branch: null, spend: null, scopedFixNote: 'nothing approved — no code changed' })
  }

  let branch = null
  let fixCount = 0
  for (const rf of approved) {
    if (fixCount >= cfg.maxFixes) break
    if (breaker.checkpoint(meta.name).action === 'abort') break
    branch = await ensureBranch(branch)
    const ok = await applyScopedFix({ ...rf, evidence: rf.evidence || rf.repro }, branch, cfg, false)
    rf.tier = ok ? 'fix' : rf.tier
    rf.fixBranch = ok ? branch : null
    if (ok) fixCount++
  }
  // Full integration suite ONCE at the end of the fix-run (FR-D2).
  phase('Fix')
  await agent(
    `End-of-fix-run gate on branch ${branch}: run the FULL TEST_CMD from .agent/lifecycle.conf once. Do NOT edit; report pass/fail + tail.`,
    { label: 'fix:full-suite', phase: 'Fix', schema: GATE })

  return await writeTriage(cfg, approved, [], { rounds: 0, stop: 'dry-streak', branch, spend: null })
}

// writeTriage — render the ranked report (.md + .json sidecar) and write both atomically. Runs on
// EVERY terminating path (FR-C4, SC-005). Pure rendering via lib/qa-report.js; the agent only writes.
async function writeTriage(cfg, rankedFindings, rejectedFindings, run) {
  phase('Triage')
  const sidecar = buildSidecar(
    { date: dateStamp, mode: cfg.mode, targets: cfg.targets, minSeverity: cfg.minSeverity, rounds: run.rounds, stop: run.stop, spend: run.spend, rejectedCount: rejectedFindings.length },
    rankedFindings,
  )
  const md = renderMarkdown(sidecar, rejectedFindings)

  await agent(
    `Write the QA triage report to qa/reports/qa-${dateStamp}.md and the sidecar to qa/reports/qa-${dateStamp}.json ` +
    `(create dirs; if dateStamp is "latest", run \`date +%F\` and use that date in BOTH filenames instead). ` +
    `Write these EXACT contents — do not regenerate them:\n` +
    `--- qa-<date>.md ---\n${md.slice(0, 14000)}\n--- qa-<date>.json ---\n${JSON.stringify(sidecar).slice(0, 14000)}\n` +
    `Do NOT commit; leave staged for human review. Report the two report paths.`,
    { label: 'triage:report', phase: 'Triage' })

  return {
    mode: cfg.mode,
    targets: cfg.targets.length,
    rounds: run.rounds,
    stop: run.stop,
    counts: sidecar.meta.counts,
    reportMd: `qa/reports/qa-${dateStamp}.md`,
    reportJson: `qa/reports/qa-${dateStamp}.json`,
    branch: run.branch || null,
    next: run.branch
      ? `Human gate: review branch ${run.branch} + qa/reports/, then merge/PR.`
      : `Review the report; run mode=fix with the ids you approve.`,
  }
}
