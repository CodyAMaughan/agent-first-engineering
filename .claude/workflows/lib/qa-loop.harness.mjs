// qa-loop.harness.mjs — a thin CLI the check-qa-loop.sh fixture drives. It replays the QA-loop's
// DECISION LOGIC (the seam modules qa-classify + qa-convergence + qa-report, plus the REAL 003
// BudgetBreaker) over STUBBED findings/verdicts — no agent() runtime needed. Each --case prints a
// JSON summary of the terminal decision the shell asserts on. NOT shipped to scaffolded repos; it
// exists so the deterministic shell fixture can exercise the REAL redesign without the LLM runtime.
//
// This is the executable model of the same loop qa-loop.js runs at agent() scale: same seam calls,
// same break→Triage path, same budget checkpoint — so a green fixture means the real workflow's
// pure decisions are correct.
//
// Usage: node qa-loop.harness.mjs --case <name>
import { resolveConfig, tierFor, isTopTierAutoFixable, resolveFixSubset } from './qa-classify.js'
import { qualifyingCount, bumpDryStreak, evaluateStop } from './qa-convergence.js'
import { buildSidecar, renderMarkdown } from './qa-report.js'
import { BudgetBreaker } from './budget-breaker.js'

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`)
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def
}
const out = (o) => { process.stdout.write(JSON.stringify(o) + '\n') }

// --- stubbed findings/verdicts (the post-mortem set) -------------------------------------------
// One genuine correctness defect + many reproducible-but-theoretical edge cases (the 28-bug shape).
function postmortemFindings() {
  const edge = (n) => ({
    id: `hook.sh:${n}:encoding`, target: '.agent/hooks/x.sh', line: n, class: 'encoding',
    claim: 'exotic-encoding evasion', repro: `echo … | sh x.sh # case ${n}`,
    impact: 'theoretical-edge', impactConfidence: 'high', impactRationale: 'implausible under threat model',
    recommendation: 'won\'t fix — below bar',
  })
  return [
    {
      id: 'git-safety.sh:19:threat-evasion', target: '.agent/hooks/git-safety.sh', line: 19, class: 'threat-evasion',
      claim: 'force-push variant slips the guard', repro: 'git push origin +main', impact: 'correctness',
      impactConfidence: 'high', impactRationale: 'an honest run can cross this boundary',
      recommendation: 'fix the refspec match',
    },
    ...Array.from({ length: 8 }, (_, i) => edge(100 + i)),
  ]
}

// tierAndAutofix(findings, cfg): assign tiers + decide the narrow auto-fix lane, exactly as qa-loop.js's
// rank step does (using the REAL seam functions).
function tierAndAutofix(findings, cfg) {
  const ranked = findings.map((f) => {
    const tier = tierFor(f.impact, cfg.minSeverity)
    return { ...f, tier }
  })
  // In mode=report the ONLY code-touching action is the narrow top-tier auto-fix lane.
  let autoFixed = 0
  if (cfg.mode === 'report') {
    for (const f of ranked) {
      if (isTopTierAutoFixable(f)) { f.tier = 'auto-fixed'; autoFixed++ }
    }
  }
  return { ranked, autoFixed }
}

function summarize(cfg, ranked, meta) {
  const sidecar = buildSidecar({ ...meta, mode: cfg.mode, minSeverity: cfg.minSeverity }, ranked)
  const md = renderMarkdown(sidecar)
  return { sidecar, md, reportRanked: md.includes('## Fix tier') && md.includes('## Backlog') }
}

const which = arg('case', 'default')

// --- self-test cases: prove the harness can report a known-good and a known-bad differently -------
if (which === 'selftest-pass') { out({ selftest: 'pass' }); process.exit(0) }
if (which === 'selftest-fail') { out({ selftest: 'fail' }); process.exit(0) }

// --- case: default — report-first, no code touched ------------------------------------------------
if (which === 'default') {
  const cfg = resolveConfig({}, {})
  const findings = postmortemFindings()
  const { ranked, autoFixed } = tierAndAutofix(findings, cfg)
  // No top-tier in this stub ⇒ no branch, no edits.
  const r = summarize(cfg, ranked, { date: '2026-06-13', targets: cfg.targets, rounds: 1, stop: 'dry-streak' })
  out({
    mode: cfg.mode,
    branch: autoFixed > 0 ? 'qa/loop-fixes' : null,
    codeChanged: autoFixed > 0,
    reportRanked: r.reportRanked,
    autoFixed,
  })
  process.exit(0)
}

// --- case: postmortem — small fix tier, theoretical-edge in backlog, nothing below top-tier fixed --
if (which === 'postmortem') {
  const cfg = resolveConfig({}, {})
  const findings = postmortemFindings()
  const { ranked, autoFixed } = tierAndAutofix(findings, cfg)
  const fix = ranked.filter((f) => f.tier === 'fix')
  const backlog = ranked.filter((f) => f.tier === 'backlog')
  const theoretical = ranked.filter((f) => f.impact === 'theoretical-edge')
  out({
    autoFixed,
    theoreticalInBacklog: theoretical.length > 0 && theoretical.every((f) => f.tier === 'backlog'),
    theoreticalInFix: theoretical.some((f) => f.tier === 'fix'),
    fixTierSmall: fix.length < backlog.length,
    fixCount: fix.length,
    backlogCount: backlog.length,
  })
  process.exit(0)
}

// --- case: moderate-bar — admits correctness+robustness, excludes theoretical ---------------------
if (which === 'moderate-bar') {
  const cfg = resolveConfig({}, {}) // moderate default
  out({
    correctnessFix: tierFor('correctness', cfg.minSeverity) === 'fix',
    robustnessFix: tierFor('robustness', cfg.minSeverity) === 'fix',
    theoreticalFix: tierFor('theoretical-edge', cfg.minSeverity) === 'fix',
  })
  process.exit(0)
}

// --- case: convergence — below-bar-only later rounds must NOT extend the run ----------------------
if (which === 'convergence') {
  const cfg = resolveConfig({}, {})
  // Round 1 finds a qualifying defect; rounds 2+ find ONLY theoretical-edge noise.
  const rounds = [
    [{ impact: 'correctness' }],
    [{ impact: 'theoretical-edge' }, { impact: 'theoretical-edge' }],
    [{ impact: 'theoretical-edge' }],
  ]
  let dryStreak = 0
  let round = 0
  let stop = null
  let lastQualifying = 0
  for (const findings of rounds) {
    round++
    const q = qualifyingCount(findings, cfg.minSeverity)
    lastQualifying = q
    dryStreak = bumpDryStreak(dryStreak, q)
    stop = evaluateStop({ round, dryStreak, fixCount: 0 }, { maxRounds: cfg.maxRounds, dryStreakStop: cfg.dryStreak, maxFixes: cfg.maxFixes })
    if (stop) break
  }
  out({ stop, rounds: round, tailExtendedRun: stop === 'dry-streak' ? false : lastQualifying > 0 })
  process.exit(0)
}

// --- case: budget-abort — wire the REAL 003 BudgetBreaker with a tiny ceiling ----------------------
// This proves the budget is WIRED IN (not just feature-detected): a tiny per-task ceiling + a stub
// usage stream drives breaker.checkpoint() to an abort, and the loop breaks→Triage to a PARTIAL report.
if (which === 'budget-abort') {
  const cfg = resolveConfig({}, {})
  // A tiny per-task ceiling; each checkpoint injects one $15 usage event so step 1 already breaches.
  const config = {
    enabled: true,
    perTask: { softUsd: 5, hardUsd: 10, hardTokens: undefined },
    perWorkflow: { hardUsd: undefined },
    iterationCap: 100,
    priceTable: { source: 'litellm', maxAgeHours: 168, fallback: 'assume-max' },
  }
  const table = { 'claude-opus': { input_cost_per_token: 1.5e-5, output_cost_per_token: 7.5e-5, cache_read_input_token_cost: 1.5e-6, cache_creation_input_token_cost: 1.875e-5 } }
  let dispensed = 0
  const oneBigEvent = () => {
    dispensed++
    return [{ agentId: `gen#${dispensed}`, model: 'claude-opus', inputTokens: 1_000_000, outputTokens: 0, timestamp: `2026-06-13T10:00:0${dispensed}Z` }]
  }
  const breaker = new BudgetBreaker(config, table, null, { runId: 'qa-fixture', readUsage: oneBigEvent, runsDir: '/tmp/qa-fixture-runs', startedAt: '2026-06-13T10:00:00Z', log: () => {} })

  const findings = postmortemFindings()
  const { ranked } = tierAndAutofix(findings, cfg)
  let round = 0
  let stop = null
  let aborted = false
  let dryStreak = 0
  // Round loop: checkpoint the budget at the top of each round; on abort → break → Triage.
  while (round < cfg.maxRounds && dryStreak < cfg.dryStreak) {
    round++
    const r = breaker.checkpoint('qa-fixture')
    if (r.action === 'abort') { stop = 'budget'; aborted = true; break }
    // (no new qualifying findings in this stub after round 1)
    dryStreak = bumpDryStreak(dryStreak, round === 1 ? 1 : 0)
  }
  breaker.onRunEnd(null, { workflowType: 'qa-loop' })
  // break→Triage: a partial ranked report is still produced.
  const r = summarize(cfg, ranked, { date: '2026-06-13', targets: cfg.targets, rounds: round, stop: stop || 'dry-streak' })
  out({ aborted, stop, partialReport: r.reportRanked && r.md.includes('PARTIAL'), rounds: round, breakerStatus: breaker.state.status })
  process.exit(0)
}

// --- case: fixcap-abort — the QA_MAX_FIXES cap stops the run with a partial report ----------------
if (which === 'fixcap-abort') {
  const cfg = resolveConfig({ QA_MAX_FIXES: '1' }, {})
  // Two qualifying fix-tier findings; the cap (1) stops accruing after the first.
  let fixCount = 0
  let stop = null
  let round = 0
  for (const _ of [1, 2, 3]) {
    round++
    fixCount++ // each round confirms one more fix-tier finding
    stop = evaluateStop({ round, dryStreak: 0, fixCount }, { maxRounds: cfg.maxRounds, dryStreakStop: cfg.dryStreak, maxFixes: cfg.maxFixes })
    if (stop) break
  }
  const r = summarize(cfg, [{ id: 'a:1:x', target: 'a', line: 1, impact: 'correctness', impactConfidence: 'high', tier: 'fix', repro: 'r', recommendation: 'fix' }],
    { date: '2026-06-13', targets: cfg.targets, rounds: round, stop })
  out({ stop, partialReport: r.reportRanked && r.md.includes('PARTIAL'), rounds: round })
  process.exit(0)
}

// --- case: fix-empty — mode=fix with no approved ids is a no-op (no branch, no edits) --------------
if (which === 'fix-empty') {
  const cfg = resolveConfig({}, { mode: 'fix', fix: [] })
  const sidecar = { findings: [{ id: 'a:1:boundary', tier: 'fix' }] }
  const { approved } = resolveFixSubset(sidecar, cfg.fixIds)
  out({ mode: cfg.mode, approved: approved.length, branch: approved.length ? 'qa/loop-fixes' : null, codeChanged: approved.length > 0 })
  process.exit(0)
}

// --- case: fix-subset — only approved ids resolved; unknown ids reported skipped -------------------
if (which === 'fix-subset') {
  const cfg = resolveConfig({}, { mode: 'fix', fix: ['a:1:boundary', 'zzz:9:dos'] })
  const sidecar = { findings: [{ id: 'a:1:boundary', tier: 'fix' }, { id: 'b:2:race', tier: 'backlog' }] }
  const { approved, unknown } = resolveFixSubset(sidecar, cfg.fixIds)
  out({ mode: cfg.mode, approved: approved.length, unknown: unknown.length, branch: approved.length ? 'qa/loop-fixes' : null })
  process.exit(0)
}

out({ error: `unknown case: ${which}` })
process.exit(2)
