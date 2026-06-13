// qa-loop.js — the STEERABLE, BOUNDED, REPORT-FIRST adversarial QA-loop (spec 004).
//
// Default `mode: report`: generate → dedup → verify(+impact) → rank → write a ranked triage report →
// STOP. No branch, no code change, EXCEPT a narrow autonomous lane that may auto-fix only unambiguous
// top-tier (data-loss/security, high-confidence) findings. `mode: fix` fixes only a human-approved id
// subset (resolved against the qa-<date>.json sidecar) on one branch with a fast fix-gate; `mode:
// autofix` is the opt-in full-auto path. Every mode is bounded by the inline ceilings (QA_MAX_FIXES +
// QA_MAX_ROUNDS + QA_DRY_STREAK) ALWAYS, plus the runtime's native `budget` global when it is set; any
// ceiling → break→Triage → a PARTIAL ranked report.
//
// SELF-CONTAINED: Workflow scripts are wrapped in an async function body where `import`/`import()` are
// unavailable, so ALL decision logic (impact ordering + tiering, the top-tier auto-fix gate, bar-keyed
// convergence/dry-streak, ranked report rendering) is inlined below as plain functions. Bounding uses
// the runtime's native `budget` primitive (budget.total / budget.spent() / budget.remaining()) — no
// import of 003's budget-breaker. `new Date()`/`Math.random()` are forbidden here: the date is threaded
// in via the dateStamp arg.
export const meta = {
  name: 'qa-loop',
  description: 'Steerable, bounded, REPORT-FIRST adversarial QA. Default mode generates → verifies (classifying each finding by real-world impact under the threat model) → ranks → writes a triage report → STOPS (no branch, no code change) except a narrow auto-fix lane for unambiguous data-loss/security findings. mode=fix fixes only a human-approved id subset on one branch with a fast fix-gate (regression + affected checks per fix; full TEST_CMD once at end). Every run is bounded by the inline ceilings (QA_MAX_ROUNDS + QA_DRY_STREAK + QA_MAX_FIXES) plus the runtime budget when set; any ceiling → graceful partial report. Config in .agent/qa.conf; the full oracle is TEST_CMD from .agent/lifecycle.conf.',
  phases: [
    { title: 'Target-select', detail: 'read .agent/qa.conf + lifecycle.conf; resolve mode, scope, bar, ceilings' },
    { title: 'Generate',      detail: 'one qa-adversary per lens fans out candidate findings (+proposedImpact) with repro recipes' },
    { title: 'Verify',        detail: 'qa-verifier REPRODUCES each deduped candidate AND classifies its impact under the threat model' },
    { title: 'Rank',          detail: 'tier each confirmed finding (fix vs backlog) by impact vs QA_MIN_SEVERITY; pick the auto-fix lane' },
    { title: 'Fix',           detail: 'mode=fix/autofix or the auto-fix lane: RED-first, fast gate (regression + affected), full TEST_CMD once at end' },
    { title: 'Triage',        detail: 'write the ranked report (.md + .json sidecar) on EVERY terminating path, naming any breached ceiling' },
  ],
}

// ================================================================================================
// Inlined PURE decision logic (was lib/qa-classify.js + lib/qa-convergence.js + lib/qa-report.js).
// These touch no agent()/budget — plain object math, kept as functions for clarity.
// ================================================================================================

// --- impact order + tiering (data-model §3) ----------------------------------------------------
// Total order, highest → lowest impact.
const IMPACT_ORDER = ['data-loss', 'security', 'correctness', 'robustness', 'theoretical-edge']

// QA_MIN_SEVERITY names a *bar* (critical|high|moderate|low). Each bar maps to the lowest IMPACT
// class still in the fix tier.
const BAR_TO_LOWEST_IMPACT = {
  critical: 'security',         // data-loss, security
  high: 'correctness',          // + correctness
  moderate: 'robustness',       // + robustness  (DEFAULT)
  low: 'theoretical-edge',      // all five
}

// impactRank — higher number = higher impact. Unknown classes rank below everything (-1) so they are
// conservative (treated as below the bar) rather than silently passing.
function impactRank(impact) {
  const i = IMPACT_ORDER.indexOf(impact)
  return i < 0 ? -1 : IMPACT_ORDER.length - 1 - i
}

// tierFor(impact, minSeverity) -> 'fix' | 'backlog'. fix-tier iff impact is at/above the bar.
function tierFor(impact, minSeverity) {
  const lowest = BAR_TO_LOWEST_IMPACT[minSeverity] || BAR_TO_LOWEST_IMPACT.moderate
  return impactRank(impact) >= impactRank(lowest) ? 'fix' : 'backlog'
}

// isTopTierAutoFixable(verdict) — the narrow autonomous lane (FR-A3): auto-fix ONLY unambiguous
// (high-confidence) data-loss/security. Ambiguous (low-confidence) top-tier ⇒ report, not fix.
function isTopTierAutoFixable(rf) {
  if (!rf) return false
  const top = rf.impact === 'data-loss' || rf.impact === 'security'
  return top && rf.impactConfidence === 'high'
}

// --- config default-resolution (contracts/qa-conf.md) ------------------------------------------
// Precedence: args ?? conf ?? safe-default. Invariant: absent config never yields unbounded auto-fix
// — the resolved default is always report-first with ceilings on (FR-CFG2).
function num(v, def) {
  const n = Number(v)
  return Number.isFinite(n) ? n : def
}

function parseAffectedMap(raw) {
  // grammar: "target:check[,check] target2:check ..." → { target: [check,...] }
  const map = {}
  if (typeof raw !== 'string' || !raw.trim()) return map
  for (const pair of raw.split(/\s+/).filter(Boolean)) {
    const idx = pair.indexOf(':')
    if (idx < 0) continue
    const target = pair.slice(0, idx)
    const checks = pair.slice(idx + 1).split(',').map((s) => s.trim()).filter(Boolean)
    if (target && checks.length) map[target] = checks
  }
  return map
}

function resolveConfig(conf = {}, theArgs = {}) {
  const a = theArgs && typeof theArgs === 'object' ? theArgs : {}
  const c = conf && typeof conf === 'object' ? conf : {}

  const mode = a.mode ?? c.QA_MODE ?? 'report'
  const minSeverity = a.minSeverity ?? c.QA_MIN_SEVERITY ?? 'moderate'
  const maxFixes = num(c.QA_MAX_FIXES, 5)
  const maxRounds = num(c.QA_MAX_ROUNDS, 4)
  const dryStreak = num(c.QA_DRY_STREAK, 2)

  // targets: args.targets (array or named group) overrides QA_TARGETS (whitespace-separated).
  let targets
  if (Array.isArray(a.targets)) targets = a.targets
  else if (typeof c.QA_TARGETS === 'string') targets = c.QA_TARGETS.split(/\s+/).filter(Boolean)
  else targets = []

  const fixIds = Array.isArray(a.fix) ? a.fix : []
  const affectedMap = parseAffectedMap(c.QA_AFFECTED_MAP)

  return { mode, minSeverity, maxFixes, maxRounds, dryStreak, targets, fixIds, affectedMap }
}

// resolveFixSubset(reportJson, fixIds) -> { approved: Finding[], unknown: string[] } (data-model §8).
// Only ids present in the sidecar's findings are approved; unknown ids are reported skipped, never
// fabricated. Empty/absent fixIds ⇒ no-op (no code change, US3-#3).
function resolveFixSubset(reportJson, fixIds) {
  const findings = (reportJson && Array.isArray(reportJson.findings)) ? reportJson.findings : []
  const ids = Array.isArray(fixIds) ? fixIds : []
  const byId = new Map(findings.map((f) => [f.id, f]))
  const approved = []
  const unknown = []
  for (const id of ids) {
    if (byId.has(id)) approved.push(byId.get(id))
    else unknown.push(id)
  }
  return { approved, unknown }
}

// --- convergence + ceilings (data-model §5/§6) -------------------------------------------------
// qualifies(finding) — true iff the finding's impact reaches the fix tier (at/above the bar). The
// marginal below-bar tail can never extend the run (FR-B4).
function qualifies(finding, minSeverity) {
  return tierFor(finding && finding.impact, minSeverity) === 'fix'
}

function qualifyingCount(findings, minSeverity) {
  if (!Array.isArray(findings)) return 0
  return findings.reduce((n, f) => n + (qualifies(f, minSeverity) ? 1 : 0), 0)
}

// bumpDryStreak — a round with zero qualifying findings increments; any qualifying finding resets to 0.
function bumpDryStreak(streak, qualifyingThisRound) {
  return qualifyingThisRound === 0 ? streak + 1 : 0
}

// evaluateStop(state, ceilings) -> stop-reason string | null. Precedence (research R4): budget breach,
// then max-fixes, then max-rounds, then dry-streak. null ⇒ keep looping.
function evaluateStop(state = {}, ceilings = {}) {
  if (state.budgetBreached) return 'budget'
  if (ceilings.maxFixes !== undefined && state.fixCount >= ceilings.maxFixes) return 'max-fixes'
  if (ceilings.maxRounds !== undefined && state.round >= ceilings.maxRounds) return 'max-rounds'
  if (ceilings.dryStreakStop !== undefined && state.dryStreak >= ceilings.dryStreakStop) return 'dry-streak'
  return null
}

// affectedChecks(target, affectedMap) -> string[] (FR-D1). The declared map wins; else fall back to the
// target's own self-test surface. NEVER returns the full TEST_CMD and never empty.
function affectedChecks(target, affectedMap = {}) {
  if (affectedMap && Array.isArray(affectedMap[target]) && affectedMap[target].length) {
    return affectedMap[target]
  }
  return [target]
}

// --- report rendering (contracts/report-schema.md) ---------------------------------------------
// rankFindings — order by impact rank (highest first), then confidence (high before low).
function rankFindings(findings) {
  const confRank = (c) => (c === 'high' ? 1 : 0)
  return [...(findings || [])].sort((a, b) => {
    const d = impactRank(b.impact) - impactRank(a.impact)
    if (d !== 0) return d
    return confRank(b.impactConfidence) - confRank(a.impactConfidence)
  })
}

// buildSidecar(meta, findings) -> the machine-readable object persisted as qa-<date>.json.
function buildSidecar(m, findings) {
  const ranked = rankFindings(findings)
  const counts = {
    fix: ranked.filter((f) => f.tier === 'fix').length,
    backlog: ranked.filter((f) => f.tier === 'backlog').length,
    autoFixed: ranked.filter((f) => f.tier === 'auto-fixed').length,
    rejected: m.rejectedCount || 0,
    unverifiedAtAbort: ranked.filter((f) => f.tier === 'unverified-at-abort').length,
  }
  return {
    meta: {
      date: m.date,
      mode: m.mode,
      targets: m.targets || [],
      minSeverity: m.minSeverity,
      rounds: m.rounds,
      stop: m.stop,
      spend: m.spend ?? null,
      counts,
    },
    findings: ranked,
  }
}

function renderFinding(f) {
  return (
    `- \`${f.id}\` — **${f.impact}** (confidence: ${f.impactConfidence}) at \`${f.target}:${f.line}\`\n` +
    `  - repro: ${f.repro}\n` +
    `  - recommendation: ${f.recommendation || ''}`
  )
}

// renderMarkdown(sidecar, rejected) -> the qa-<date>.md text (report-schema §"Markdown layout").
function renderMarkdown(sidecar, rejected = []) {
  const { meta: m, findings } = sidecar
  const fix = findings.filter((f) => f.tier === 'fix')
  const autoFixed = findings.filter((f) => f.tier === 'auto-fixed')
  const backlog = findings.filter((f) => f.tier === 'backlog')
  const unverified = findings.filter((f) => f.tier === 'unverified-at-abort')
  const c = m.counts
  const L = []

  L.push(`# QA Triage Report — ${m.date}`)
  L.push('')
  // 1. Summary
  L.push('## Summary')
  L.push(
    `Mode \`${m.mode}\`; ${m.rounds} round(s); stop: \`${m.stop}\`. ` +
    `Fix: ${c.fix}, backlog: ${c.backlog}, auto-fixed: ${c.autoFixed}, rejected: ${c.rejected}, ` +
    `unverified-at-abort: ${c.unverifiedAtAbort}.` +
    (m.spend ? ` Spend: ${JSON.stringify(m.spend)}.` : '') +
    (['budget', 'max-fixes', 'max-rounds', 'wall-clock', 'aborted'].includes(m.stop)
      ? `  **Ceiling breached: \`${m.stop}\` — this is a PARTIAL report of findings so far.**`
      : ''),
  )
  L.push('')
  // 2. Fix tier
  L.push(`## Fix tier (≥ ${m.minSeverity})`)
  if (!fix.length) L.push(`No fix-tier findings at/above the \`${m.minSeverity}\` bar.`)
  else for (const f of fix) L.push(renderFinding(f))
  L.push('')
  // 3. Auto-fixed (top-tier) — only if the lane acted
  if (autoFixed.length) {
    L.push('## Auto-fixed (top-tier)')
    for (const f of autoFixed) L.push(`- \`${f.id}\` — ${f.impact} on \`${f.fixBranch || '(branch)'}\`; ${f.recommendation || ''}`)
    L.push('')
  }
  // 4. Backlog / won't-fix
  L.push('## Backlog / won\'t-fix')
  if (!backlog.length) L.push('None.')
  else for (const f of backlog) L.push(`- \`${f.id}\` — ${f.impact} (below the \`${m.minSeverity}\` bar): ${f.impactRationale || f.recommendation || 'below bar'}`)
  L.push('')
  // 5. Rejected
  L.push('## Rejected')
  if (!rejected.length) L.push('None.')
  else for (const r of rejected) L.push(`- \`${r.id}\` — ${r.verdict}: ${r.why || ''}`)
  L.push('')
  // 6. Unverified-at-abort — only if a ceiling tripped mid-verify
  if (unverified.length) {
    L.push('## Unverified-at-abort')
    for (const f of unverified) L.push(`- \`${f.id}\` — not resolved to a tier before the \`${m.stop}\` ceiling tripped.`)
    L.push('')
  }
  return L.join('\n')
}

// ================================================================================================
// Bounding helpers over the runtime's native `budget` global (budget.total / .spent() / .remaining()).
// When budget.total is unset (null/undefined), the budget ceiling is inert and the run is bounded by
// QA_MAX_ROUNDS + QA_DRY_STREAK + QA_MAX_FIXES alone (degrade gracefully — research R7).
// ================================================================================================
const BUDGET = (typeof budget !== 'undefined' && budget) ? budget : null
const budgetEnabled = !!(BUDGET && BUDGET.total != null)

// budgetLow() — true once the run should abort: remaining is below a small fraction (10%) of the
// total ceiling, so we stop BEFORE the next costly step rather than overshooting.
function budgetLow() {
  if (!budgetEnabled) return false
  const total = Number(BUDGET.total)
  if (!Number.isFinite(total) || total <= 0) return false
  let remaining = Infinity
  try { remaining = Number(BUDGET.remaining()) } catch (e) { return false }
  if (!Number.isFinite(remaining)) return false
  return remaining <= total * 0.1
}

function budgetSpend() {
  if (!budgetEnabled) return null
  try {
    const total = Number(BUDGET.total)
    const spent = Number(BUDGET.spent())
    return { spentUsd: Number.isFinite(spent) ? spent : null, totalUsd: Number.isFinite(total) ? total : null }
  } catch (e) { return null }
}

// ---- args (contracts/workflow-args.md) ----------------------------------------------------------
// { mode?, targets?: string[]|group, minSeverity?, fix?: string[], dateStamp?: 'YYYY-MM-DD' }
const A = (args && typeof args === 'object') ? args : {}
const dateStamp = A.dateStamp || 'latest'   // never new Date() inline (determinism)

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

// ---- Target-select: resolve config from qa.conf + args via the pure resolver ---------------------
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

// Re-resolve through the PURE resolver so absent config can never yield unbounded auto-fix (FR-CFG2):
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

if (!budgetEnabled) log('[qa] budget ceiling inert (budget.total unset) — running on QA_MAX_FIXES + QA_MAX_ROUNDS + QA_DRY_STREAK ceilings only.')
log(`Mode: ${cfg.mode} | bar: ${cfg.minSeverity} | targets (${cfg.targets.length}): ${cfg.targets.join(', ')}\n` +
    `Ceilings: maxRounds=${cfg.maxRounds}, dryStreak=${cfg.dryStreak}, maxFixes=${cfg.maxFixes}, budget=${budgetEnabled ? 'on' : 'off'}.`)

// ================================================================================================
// mode: fix — scoped fix-run over a human-approved id subset (US3). No discovery; resolve ids
// against the latest sidecar, fix ONLY approved ids on one branch, fast gate per fix, full suite once.
// ================================================================================================
if (cfg.mode === 'fix') {
  return await runScopedFix(cfg)
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
  // ---- ceiling check at the TOP of each round (native budget, plus the QA-local caps) ----------
  stop = evaluateStop(
    { round, dryStreak, fixCount, budgetBreached: budgetLow() },
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
    if (budgetLow()) {
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
    if (budgetLow()) { stop = 'budget'; break }
    branch = await ensureBranch(branch)
    const ok = await applyScopedFix(rf, branch, cfg)
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

return await writeTriage(cfg, ranked, rejected, { rounds: round, stop, branch, spend: budgetSpend() })

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
async function applyScopedFix(rf, fixBranch, cfg) {
  const affected = affectedChecks(rf.target, cfg.affectedMap)
  let gate = { pass: false, summary: '', issues: [] }
  let redProven = false
  for (let i = 1; i <= 4; i++) {
    if (i === 1) {
      await agent(
        `CONFIRMED ${rf.impact} defect on branch ${fixBranch} in ${rf.target}: ${rf.claim}\nRepro: ${rf.repro}\nEvidence: ${rf.evidence}\n` +
        `STEP 1 (RED): add a regression case encoding this repro — extend the target's own self_test() if it has one, ` +
        `else add a case to tests/validate.sh, else a new tests/check-*.sh. Run ONLY that new case and CONFIRM IT FAILS ` +
        `(prove RED). Do NOT touch ${rf.target} yet. Commit the RED test. Report the failing output.`,
        { label: `fix:red#${rf.id}`, phase: 'Fix' })
    } else {
      await agent(
        `STEP 2 (GREEN) on branch ${fixBranch}: fix ${rf.target} so the regression case passes — minimal change, do NOT ` +
        `weaken any existing assertion, do NOT edit the regression test to pass. Previous gate: ${gate.summary}. Commit. Report the diff.`,
        { label: `fix:green#${rf.id}@${i}`, phase: 'Fix' })
    }
    // FAST gate: only the new regression case + the directly-affected checks (NOT the full suite).
    gate = await agent(
      `FAST fix-gate on branch ${fixBranch}: run ONLY (a) the new regression case for ${rf.id} and (b) these directly-affected ` +
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
async function runScopedFix(cfg) {
  phase('Rank')
  const json = await agent(
    `Read the latest QA report sidecar at qa/reports/qa-${dateStamp}.json (if dateStamp is "latest", read the most recent ` +
    `qa/reports/qa-*.json). Return its parsed JSON exactly (meta + findings). If none exists, return {"findings":[]}.`,
    { label: 'fix:load-sidecar', phase: 'Rank', schema: { type: 'object', properties: { meta: { type: 'object' }, findings: { type: 'array', items: { type: 'object' } } }, required: ['findings'] } })

  const { approved, unknown } = resolveFixSubset(json, cfg.fixIds)
  log(`Scoped fix: ${approved.length} approved, ${unknown.length} unknown id(s) skipped: ${JSON.stringify(unknown)}.`)
  if (!approved.length) {
    // Empty/absent approved subset ⇒ no code change (US3-#3).
    return await writeTriage(cfg, [], [], { rounds: 0, stop: 'dry-streak', branch: null, spend: budgetSpend(), scopedFixNote: 'nothing approved — no code changed' })
  }

  let fixBranch = null
  let fixCount = 0
  for (const rf of approved) {
    if (fixCount >= cfg.maxFixes) break
    if (budgetLow()) break
    fixBranch = await ensureBranch(fixBranch)
    const ok = await applyScopedFix({ ...rf, evidence: rf.evidence || rf.repro }, fixBranch, cfg)
    rf.tier = ok ? 'fix' : rf.tier
    rf.fixBranch = ok ? fixBranch : null
    if (ok) fixCount++
  }
  // Full integration suite ONCE at the end of the fix-run (FR-D2).
  phase('Fix')
  await agent(
    `End-of-fix-run gate on branch ${fixBranch}: run the FULL TEST_CMD from .agent/lifecycle.conf once. Do NOT edit; report pass/fail + tail.`,
    { label: 'fix:full-suite', phase: 'Fix', schema: GATE })

  return await writeTriage(cfg, approved, [], { rounds: 0, stop: 'dry-streak', branch: fixBranch, spend: budgetSpend() })
}

// writeTriage — render the ranked report (.md + .json sidecar) and write both. Runs on EVERY
// terminating path (FR-C4, SC-005). Pure rendering inline; the agent only writes the files.
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
