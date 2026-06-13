// qa-convergence.test.js — unit tests for the QA-loop's convergence + ceiling/stop + fast-gate logic.
// Strict TDD: written BEFORE .claude/workflows/lib/qa-convergence.js exists (RED first).
// Covers: bar-keyed "qualifying" findings, the dry-streak advancing on below-bar-only rounds,
// the stop/ceiling evaluation (max-rounds, dry-streak, max-fixes), and affected-check selection.
import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  qualifies,
  qualifyingCount,
  bumpDryStreak,
  evaluateStop,
  affectedChecks,
} from '../.claude/workflows/lib/qa-convergence.js'

// =============================================================================================
// qualifies — a finding is "qualifying" iff its impact is at/above the bar (FR-B4 keys on this)
// =============================================================================================
test('qualifies: at/above the moderate bar only', () => {
  assert.equal(qualifies({ impact: 'correctness' }, 'moderate'), true)
  assert.equal(qualifies({ impact: 'robustness' }, 'moderate'), true)
  assert.equal(qualifies({ impact: 'data-loss' }, 'moderate'), true)
  // theoretical-edge is below the moderate bar → does not qualify (can't extend the run)
  assert.equal(qualifies({ impact: 'theoretical-edge' }, 'moderate'), false)
})

test('qualifyingCount: counts only at/above-bar findings in a round', () => {
  const round = [
    { impact: 'theoretical-edge' },
    { impact: 'theoretical-edge' },
    { impact: 'correctness' },
  ]
  assert.equal(qualifyingCount(round, 'moderate'), 1)
  // a round of pure below-bar noise contributes ZERO qualifying findings
  assert.equal(qualifyingCount([{ impact: 'theoretical-edge' }], 'moderate'), 0)
})

// =============================================================================================
// bumpDryStreak (FR-B4 / data-model §5) — a below-bar-only round advances the streak like an empty round
// =============================================================================================
test('bumpDryStreak: a round with zero qualifying findings increments the streak', () => {
  assert.equal(bumpDryStreak(0, 0), 1) // streak 0, 0 qualifying → 1
  assert.equal(bumpDryStreak(1, 0), 2) // advances again
})

test('bumpDryStreak: a qualifying finding RESETS the streak to 0', () => {
  assert.equal(bumpDryStreak(2, 1), 0)
  assert.equal(bumpDryStreak(5, 3), 0)
})

// =============================================================================================
// evaluateStop — which ceiling (if any) has tripped; precedence: budget > max-fixes > max-rounds > dry-streak
// =============================================================================================
test('evaluateStop: no ceiling reached ⇒ null (keep looping)', () => {
  assert.equal(evaluateStop({ round: 1, dryStreak: 0, fixCount: 0 }, { maxRounds: 4, dryStreakStop: 2, maxFixes: 5 }), null)
})

test('evaluateStop: dry-streak reached', () => {
  assert.equal(evaluateStop({ round: 3, dryStreak: 2, fixCount: 0 }, { maxRounds: 4, dryStreakStop: 2, maxFixes: 5 }), 'dry-streak')
})

test('evaluateStop: max-rounds reached', () => {
  assert.equal(evaluateStop({ round: 4, dryStreak: 0, fixCount: 0 }, { maxRounds: 4, dryStreakStop: 2, maxFixes: 5 }), 'max-rounds')
})

test('evaluateStop: max-fixes reached stops accruing fixes', () => {
  assert.equal(evaluateStop({ round: 1, dryStreak: 0, fixCount: 5 }, { maxRounds: 4, dryStreakStop: 2, maxFixes: 5 }), 'max-fixes')
})

test('evaluateStop: a budget breach takes precedence over everything', () => {
  assert.equal(
    evaluateStop({ round: 1, dryStreak: 0, fixCount: 0, budgetBreached: true }, { maxRounds: 4, dryStreakStop: 2, maxFixes: 5 }),
    'budget',
  )
})

// =============================================================================================
// affectedChecks (data-model §6, FR-D1) — declared map → self-test fallback, NOT the full TEST_CMD
// =============================================================================================
test('affectedChecks: declared map wins', () => {
  const map = { 'tests/validate.sh': ['tests/check-qa-manifest.sh', 'tests/check-budget.sh'] }
  assert.deepEqual(affectedChecks('tests/validate.sh', map), ['tests/check-qa-manifest.sh', 'tests/check-budget.sh'])
})

test('affectedChecks: falls back to the target itself when unmapped (self-test), never the full suite', () => {
  const r = affectedChecks('.agent/hooks/git-safety.sh', {})
  // fallback is the target's own self-test surface — here, the target path itself — never empty,
  // and never the whole TEST_CMD.
  assert.ok(Array.isArray(r) && r.length >= 1)
  assert.ok(r.includes('.agent/hooks/git-safety.sh'))
})
