// qa-convergence.js — the QA-loop's PURE convergence + ceiling/stop + fast-gate selection logic,
// extracted out of qa-loop.js for `node --test` (the runtime's agent()/budget() can't run under node).
// Agent-neutral; operates on plain loop-state objects.
//
// Responsibilities (spec 004 / data-model §5, §6; research R3/R4/R6):
//   - "qualifying" = a finding at/above the bar; convergence keys on this, not on CONFIRMED (FR-B4),
//   - the dry-streak advances on a below-bar-only round exactly like an empty one,
//   - evaluateStop maps loop state + ceilings to a `stop` reason (graceful break→Triage),
//   - affectedChecks selects the fast fix-gate's directly-affected checks (FR-D1), never the full suite.
import { tierFor } from './qa-classify.js'

// qualifies(finding, minSeverity) — true iff the finding's impact reaches the fix tier (== at/above
// the bar). The marginal below-bar tail returns false, so it can never extend the run (FR-B4).
export function qualifies(finding, minSeverity) {
  return tierFor(finding && finding.impact, minSeverity) === 'fix'
}

// qualifyingCount(findings, minSeverity) — how many at/above-bar findings a round produced.
export function qualifyingCount(findings, minSeverity) {
  if (!Array.isArray(findings)) return 0
  return findings.reduce((n, f) => n + (qualifies(f, minSeverity) ? 1 : 0), 0)
}

// bumpDryStreak(streak, qualifyingThisRound) — a round with zero qualifying findings increments the
// streak; any qualifying finding resets it to 0 (data-model §5, research R3).
export function bumpDryStreak(streak, qualifyingThisRound) {
  return qualifyingThisRound === 0 ? streak + 1 : 0
}

// evaluateStop(state, ceilings) -> stop-reason string | null.
// Precedence (research R4 / data-model §5): a budget breach (003) takes precedence, then max-fixes,
// then max-rounds, then the dry-streak, then optional wall-clock. null ⇒ keep looping.
export function evaluateStop(state = {}, ceilings = {}) {
  if (state.budgetBreached) return 'budget'
  if (ceilings.maxFixes !== undefined && state.fixCount >= ceilings.maxFixes) return 'max-fixes'
  if (ceilings.wallclockHit) return 'wall-clock'
  if (ceilings.maxRounds !== undefined && state.round >= ceilings.maxRounds) return 'max-rounds'
  if (ceilings.dryStreakStop !== undefined && state.dryStreak >= ceilings.dryStreakStop) return 'dry-streak'
  return null
}

// affectedChecks(target, affectedMap) -> string[] (FR-D1, data-model §6).
// The declared map wins; otherwise fall back to the target's own self-test surface (the target path
// itself — its own check script / self_test()). NEVER returns the full TEST_CMD and never empty.
export function affectedChecks(target, affectedMap = {}) {
  if (affectedMap && Array.isArray(affectedMap[target]) && affectedMap[target].length) {
    return affectedMap[target]
  }
  return [target]
}

export default { qualifies, qualifyingCount, bumpDryStreak, evaluateStop, affectedChecks }
