// qa-classify.js — the QA-loop's PURE classification/decision logic, extracted out of qa-loop.js so it
// is unit-testable with `node --test` (the workflow runtime's agent()/parallel() can't run under node).
// This module knows nothing about agent() — it operates on plain objects (findings, verdicts, config).
//
// Responsibilities (spec 004 / data-model.md):
//   - the impact total order + the severity bar / tiering (§3),
//   - the narrow top-tier auto-fix gate (§5, FR-A3),
//   - the default-resolution contract for qa.conf + args (contracts/qa-conf.md),
//   - resolving a human-approved fix subset against a report sidecar (§8).
// Agent-neutral; no Claude paths.

// Total order, highest → lowest impact (data-model §3).
export const IMPACT_ORDER = ['data-loss', 'security', 'correctness', 'robustness', 'theoretical-edge']

// QA_MIN_SEVERITY names a *bar* (critical|high|moderate|low). Each bar maps to the lowest IMPACT
// class still in the fix tier (data-model §3).
const BAR_TO_LOWEST_IMPACT = {
  critical: 'security',         // data-loss, security
  high: 'correctness',          // + correctness
  moderate: 'robustness',       // + robustness  (DEFAULT)
  low: 'theoretical-edge',      // all five
}

// impactRank — higher number = higher impact. Unknown classes rank below everything (-1) so they
// are conservative (treated as below the bar) rather than silently passing.
export function impactRank(impact) {
  const i = IMPACT_ORDER.indexOf(impact)
  return i < 0 ? -1 : IMPACT_ORDER.length - 1 - i
}

// tierFor(impact, minSeverity) -> 'fix' | 'backlog'. A finding is fix-tier iff its impact is at/above
// the bar named by minSeverity (data-model §3 tiering rule).
export function tierFor(impact, minSeverity) {
  const lowest = BAR_TO_LOWEST_IMPACT[minSeverity] || BAR_TO_LOWEST_IMPACT.moderate
  return impactRank(impact) >= impactRank(lowest) ? 'fix' : 'backlog'
}

// isTopTierAutoFixable(verdict) — the narrow autonomous lane (FR-A3): auto-fix ONLY unambiguous
// (high-confidence) data-loss/security. Ambiguous (low-confidence) top-tier ⇒ report, not fix.
export function isTopTierAutoFixable(verdict) {
  if (!verdict) return false
  const top = verdict.impact === 'data-loss' || verdict.impact === 'security'
  return top && verdict.impactConfidence === 'high'
}

// --- default-resolution contract (contracts/qa-conf.md) -----------------------------------------
// resolveConfig(conf, args): conf = parsed qa.conf KEY=value object; args = the workflow args object.
// Precedence: args ?? conf ?? safe-default. Invariant: absent config never yields unbounded auto-fix —
// the resolved default is always report-first with ceilings on (FR-CFG2).
const num = (v, def) => {
  const n = Number(v)
  return Number.isFinite(n) ? n : def
}

export function resolveConfig(conf = {}, args = {}) {
  const a = args && typeof args === 'object' ? args : {}
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
  const wallclock = c.QA_WALLCLOCK !== undefined ? num(c.QA_WALLCLOCK, undefined) : undefined
  const affectedMap = parseAffectedMap(c.QA_AFFECTED_MAP)

  return { mode, minSeverity, maxFixes, maxRounds, dryStreak, targets, fixIds, wallclock, affectedMap }
}

// QA_AFFECTED_MAP grammar: "target:check[,check] target2:check ..." → { target: [check,...] }.
function parseAffectedMap(raw) {
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

// --- approved-subset resolver (data-model §8) ---------------------------------------------------
// resolveFixSubset(reportJson, fixIds) -> { approved: Finding[], unknown: string[] }.
// Only ids present in the sidecar's findings are approved; ids not found are reported skipped (never
// fabricated). Empty/absent fixIds ⇒ no-op (nothing approved → no code change, US3-#3).
export function resolveFixSubset(reportJson, fixIds) {
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

export default { IMPACT_ORDER, impactRank, tierFor, isTopTierAutoFixable, resolveConfig, resolveFixSubset }
