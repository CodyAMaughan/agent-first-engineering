// qa-classify.test.js — unit tests for the QA-loop's pure classification/decision logic (node --test).
// Strict TDD: written BEFORE .claude/workflows/lib/qa-classify.js exists (RED first).
// Covers: impact ordering, the severity bar / tiering, the top-tier auto-fix gate, the
// default-resolution contract (qa-conf.md), and the approved-subset resolver (data-model §8).
import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  IMPACT_ORDER,
  impactRank,
  tierFor,
  isTopTierAutoFixable,
  resolveConfig,
  resolveFixSubset,
} from '../.claude/workflows/lib/qa-classify.js'

// =============================================================================================
// Impact ordering (data-model §3): data-loss > security > correctness > robustness > theoretical-edge
// =============================================================================================
test('IMPACT_ORDER ranks the five classes highest→lowest', () => {
  assert.deepEqual(IMPACT_ORDER, ['data-loss', 'security', 'correctness', 'robustness', 'theoretical-edge'])
  assert.ok(impactRank('data-loss') > impactRank('security'))
  assert.ok(impactRank('security') > impactRank('correctness'))
  assert.ok(impactRank('correctness') > impactRank('robustness'))
  assert.ok(impactRank('robustness') > impactRank('theoretical-edge'))
})

// =============================================================================================
// Tiering / the severity bar (data-model §3): fix iff impactRank(impact) >= impactRank(minSeverity-class)
// =============================================================================================
test('tierFor: the moderate bar admits correctness+robustness, excludes theoretical-edge', () => {
  assert.equal(tierFor('correctness', 'moderate'), 'fix')
  assert.equal(tierFor('robustness', 'moderate'), 'fix')
  assert.equal(tierFor('data-loss', 'moderate'), 'fix')
  assert.equal(tierFor('security', 'moderate'), 'fix')
  assert.equal(tierFor('theoretical-edge', 'moderate'), 'backlog')
})

test('tierFor: the critical bar admits only data-loss+security', () => {
  assert.equal(tierFor('data-loss', 'critical'), 'fix')
  assert.equal(tierFor('security', 'critical'), 'fix')
  assert.equal(tierFor('correctness', 'critical'), 'backlog')
  assert.equal(tierFor('robustness', 'critical'), 'backlog')
  assert.equal(tierFor('theoretical-edge', 'critical'), 'backlog')
})

test('tierFor: the high bar admits data-loss+security+correctness', () => {
  assert.equal(tierFor('correctness', 'high'), 'fix')
  assert.equal(tierFor('robustness', 'high'), 'backlog')
})

test('tierFor: the low bar admits all five', () => {
  for (const c of IMPACT_ORDER) assert.equal(tierFor(c, 'low'), 'fix')
})

// =============================================================================================
// Top-tier auto-fix lane (data-model §5, FR-A3): data-loss|security AND impactConfidence==='high'
// =============================================================================================
test('isTopTierAutoFixable: only unambiguous (high-confidence) data-loss/security', () => {
  assert.equal(isTopTierAutoFixable({ impact: 'data-loss', impactConfidence: 'high' }), true)
  assert.equal(isTopTierAutoFixable({ impact: 'security', impactConfidence: 'high' }), true)
  // ambiguous top-tier (low confidence) is routed to the report, NOT auto-fixed
  assert.equal(isTopTierAutoFixable({ impact: 'data-loss', impactConfidence: 'low' }), false)
  assert.equal(isTopTierAutoFixable({ impact: 'security', impactConfidence: 'low' }), false)
  // non-top-tier never auto-fixes regardless of confidence
  assert.equal(isTopTierAutoFixable({ impact: 'correctness', impactConfidence: 'high' }), false)
  assert.equal(isTopTierAutoFixable({ impact: 'robustness', impactConfidence: 'high' }), false)
})

// =============================================================================================
// Default-resolution contract (contracts/qa-conf.md) — absent config never yields unbounded auto-fix
// =============================================================================================
test('resolveConfig: empty conf + empty args yields the safe report-first defaults', () => {
  const r = resolveConfig({}, {})
  assert.equal(r.mode, 'report')
  assert.equal(r.minSeverity, 'moderate')
  assert.equal(r.maxFixes, 5)
  assert.equal(r.maxRounds, 4)
  assert.equal(r.dryStreak, 2)
})

test('resolveConfig: args override conf override defaults', () => {
  const conf = { QA_MODE: 'autofix', QA_MIN_SEVERITY: 'high', QA_MAX_FIXES: '9', QA_MAX_ROUNDS: '7', QA_DRY_STREAK: '3' }
  const r = resolveConfig(conf, { mode: 'fix', minSeverity: 'critical' })
  assert.equal(r.mode, 'fix')           // args win
  assert.equal(r.minSeverity, 'critical') // args win
  assert.equal(r.maxFixes, 9)           // conf (no arg)
  assert.equal(r.maxRounds, 7)
  assert.equal(r.dryStreak, 3)
})

test('resolveConfig: conf alone (no args) is honored', () => {
  const r = resolveConfig({ QA_MODE: 'report', QA_MIN_SEVERITY: 'low' }, {})
  assert.equal(r.mode, 'report')
  assert.equal(r.minSeverity, 'low')
})

test('resolveConfig: targets scope — args.targets overrides QA_TARGETS', () => {
  const conf = { QA_TARGETS: 'a.sh b.sh c.sh' }
  assert.deepEqual(resolveConfig(conf, {}).targets, ['a.sh', 'b.sh', 'c.sh'])
  assert.deepEqual(resolveConfig(conf, { targets: ['a.sh'] }).targets, ['a.sh'])
})

test('resolveConfig: fixIds pass through from args.fix', () => {
  const r = resolveConfig({}, { mode: 'fix', fix: ['x:1:boundary', 'y:2:race'] })
  assert.deepEqual(r.fixIds, ['x:1:boundary', 'y:2:race'])
})

// =============================================================================================
// Approved-subset resolver (data-model §8) — only approved ids; unknown skipped; nothing fabricated
// =============================================================================================
test('resolveFixSubset: partitions approved / unknown against a report sidecar', () => {
  const sidecar = { findings: [
    { id: 'a:1:boundary', tier: 'fix' },
    { id: 'b:2:race', tier: 'backlog' },
  ] }
  const r = resolveFixSubset(sidecar, ['a:1:boundary', 'zzz:9:dos'])
  assert.deepEqual(r.approved.map((f) => f.id), ['a:1:boundary'])
  assert.deepEqual(r.unknown, ['zzz:9:dos'])
})

test('resolveFixSubset: empty/absent fixIds ⇒ no-op (nothing approved)', () => {
  const sidecar = { findings: [{ id: 'a:1:boundary', tier: 'fix' }] }
  assert.deepEqual(resolveFixSubset(sidecar, []).approved, [])
  assert.deepEqual(resolveFixSubset(sidecar, null).approved, [])
})
