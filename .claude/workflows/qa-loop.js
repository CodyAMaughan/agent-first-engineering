// qa-loop.js — LEAN, SAFE, HIGH-SIGNAL adversarial QA (v2).
//
// One grounded review pass → verify each finding (reproduce-or-DROP) → rank by severity → write a
// report → STOP. Report-only by default (no branch, no code change). `--autofix <critical|high>` is
// the ONLY path that writes code, and only for those tiers. Every run is HARD-CAPPED by total agents
// and a token ceiling (always on, no budget directive required) — it cannot run away.
//
// Design (grounded in code-review research): single pass beats a parallel swarm (parallel near-identical
// agents duplicate work + burn ~15x tokens); precision is the bottleneck, so we GROUND-OR-DROP every
// finding (cite file:line + reproduce) and ABSTAIN when unsure; severity = critical/high/low/nitpick
// with nitpick collapsed; cap CUMULATIVE cost (agents+tokens), not rounds.
//
// SELF-CONTAINED: the Workflow runtime wraps this body in an async function where `import`/`import()`
// are unavailable, so ALL logic is inline. No `new Date()`/`Math.random()` (determinism).

export const meta = {
  name: 'qa-loop',
  description: 'Lean, safe, report-first adversarial QA. ONE grounded review pass finds the few sharpest issues (citing file:line + a repro, abstaining when unsure); each is verified by reproduce-or-drop and classified critical/high/low/nitpick; a ranked report is written and the run STOPS — no branch, no code change. `--autofix critical|high` opt-in scoped-fixes only those tiers. Hard-capped by total agents + a token ceiling (always on) so it cannot run away. Config in .agent/qa.conf.',
  phases: [
    { title: 'Config',  detail: 'read .agent/qa.conf + lifecycle.conf; resolve mode, targets, bar, caps, autofix levels' },
    { title: 'Review',  detail: 'ONE grounded reviewer: the few sharpest issues, each cited + reproduced, or abstain' },
    { title: 'Verify',  detail: 'reproduce-or-DROP each finding in a sandbox; classify severity critical/high/low/nitpick' },
    { title: 'Fix',     detail: '(only with --autofix) RED-first scoped fix of the named tiers on one branch; full TEST_CMD once' },
    { title: 'Report',  detail: 'rank, write qa-<date>.md + .json, STOP' },
  ],
}

// ================================================================================================
// Pure helpers (no agent/budget calls)
// ================================================================================================
const SEV_ORDER = { critical: 4, high: 3, low: 2, nitpick: 1 }
function severityRank(s) { return SEV_ORDER[s] || 0 }

// tierFor — a confirmed finding is 'fix' if its severity is at/above the bar AND not a nitpick;
// nitpick is always collapsed to 'backlog'.
function tierFor(severity, minSeverity) {
  if (severity === 'nitpick') return 'backlog'
  return severityRank(severity) >= severityRank(minSeverity) ? 'fix' : 'backlog'
}

function rankFindings(findings) {
  const confRank = (c) => (c === 'high' ? 1 : 0)
  return [...(findings || [])].sort((a, b) => {
    const d = severityRank(b.severity) - severityRank(a.severity)
    if (d !== 0) return d
    return confRank(b.confidence) - confRank(a.confidence)
  })
}

function buildSidecar(m, findings) {
  const ranked = rankFindings(findings)
  const counts = {
    fix: ranked.filter((f) => f.tier === 'fix').length,
    backlog: ranked.filter((f) => f.tier === 'backlog').length,
    autoFixed: ranked.filter((f) => f.tier === 'auto-fixed').length,
    rejected: m.rejectedCount || 0,
  }
  return { meta: { date: m.date, mode: m.mode, targets: m.targets || [], minSeverity: m.minSeverity, stop: m.stop, agentsUsed: m.agentsUsed, spend: m.spend ?? null, counts }, findings: ranked }
}

function renderFinding(f) {
  return (
    `- \`${f.id}\` — **${f.severity}** (confidence: ${f.confidence}) at \`${f.target}:${f.line}\`\n` +
    `  - what: ${f.claim}\n` +
    `  - repro: ${f.repro}\n` +
    `  - fix: ${f.recommendation || ''}`
  )
}

function renderMarkdown(sidecar, rejected = []) {
  const { meta: m, findings } = sidecar
  const fix = findings.filter((f) => f.tier === 'fix')
  const autoFixed = findings.filter((f) => f.tier === 'auto-fixed')
  const backlog = findings.filter((f) => f.tier === 'backlog')
  const nitpicks = backlog.filter((f) => f.severity === 'nitpick')
  const c = m.counts
  const L = []
  L.push(`# QA Report — ${m.date}`)
  L.push('')
  L.push('## Summary')
  const partial = ['agent-cap', 'token-ceiling', 'budget', 'aborted'].includes(m.stop)
  L.push(
    `Mode \`${m.mode}\`; bar \`${m.minSeverity}\`; ${m.agentsUsed} agents; stop: \`${m.stop}\`. ` +
    `Fix: ${c.fix}, backlog: ${c.backlog}, auto-fixed: ${c.autoFixed}, rejected/dropped: ${c.rejected}.` +
    (m.spend ? ` Spend: ${JSON.stringify(m.spend)}.` : '') +
    (partial ? `  **Ceiling hit (\`${m.stop}\`) — PARTIAL report.**` : '') +
    (!fix.length && !autoFixed.length ? '  No actionable findings — clean (abstained).' : ''),
  )
  L.push('')
  L.push(`## Findings to fix (≥ ${m.minSeverity})`)
  if (!fix.length) L.push(`None at/above the \`${m.minSeverity}\` bar.`)
  else for (const f of fix) L.push(renderFinding(f))
  L.push('')
  if (autoFixed.length) {
    L.push('## Auto-fixed')
    for (const f of autoFixed) L.push(`- \`${f.id}\` — ${f.severity} on \`${f.fixBranch || '(branch)'}\`; ${f.recommendation || ''}`)
    L.push('')
  }
  if (nitpicks.length) {
    L.push(`<details><summary>Nitpicks (${nitpicks.length}) — collapsed</summary>`)
    L.push('')
    for (const f of nitpicks) L.push(`- \`${f.id}\` — ${f.target}:${f.line}: ${f.claim}`)
    L.push('')
    L.push('</details>')
    L.push('')
  }
  if (rejected.length) {
    L.push('## Dropped (not reproduced / out of scope)')
    for (const r of rejected) L.push(`- \`${r.id}\` — ${r.verdict}: ${r.why || ''}`)
    L.push('')
  }
  return L.join('\n')
}

function num(v, d) { const n = Number(v); return Number.isFinite(n) ? n : d }

// parse "critical" | "critical,high" | [] -> a Set of severities the autofix lane may touch.
function parseAutofix(raw) {
  if (!raw) return new Set()
  const list = Array.isArray(raw) ? raw : String(raw).split(',')
  return new Set(list.map((s) => s.trim().toLowerCase()).filter(Boolean))
}

// args > conf > safe defaults. Defaults are always report-first + bounded.
function resolveConfig(conf, A) {
  const c = conf || {}
  return {
    mode: (A.mode || c.QA_MODE || 'report'),
    minSeverity: (A.minSeverity || c.QA_MIN_SEVERITY || 'low'),
    autofix: parseAutofix(A.autofix != null ? A.autofix : c.QA_AUTOFIX),
    maxAgents: num(A.maxAgents != null ? A.maxAgents : c.QA_MAX_AGENTS, 10),
    tokenCeiling: num(A.tokenCeiling != null ? A.tokenCeiling : c.QA_TOKEN_CEILING, 150000),
    maxFindings: num(A.maxFindings != null ? A.maxFindings : c.QA_MAX_FINDINGS, 5),
    maxFixes: num(A.maxFixes != null ? A.maxFixes : c.QA_MAX_FIXES, 3),
    targets: Array.isArray(A.targets) ? A.targets : (c.targets || []),
    threatModel: c.QA_THREAT_MODEL || 'Guards protect against an honest agent\'s mistakes + untrusted content, NOT a determined attacker; file-write==RCE is out of scope.',
    testCmd: c.testCmd || '',
    affectedMap: c.affectedMap || {},
  }
}

// ================================================================================================
// Bounding — ALWAYS ON. budget.spent() returns tokens even when budget.total is unset, so the token
// ceiling and the agent cap bound the run with no user budget directive. This is the real runaway fix.
// ================================================================================================
const BUDGET = (typeof budget !== 'undefined' && budget) ? budget : null
function spentTokens() { if (!BUDGET) return 0; try { const s = Number(BUDGET.spent()); return Number.isFinite(s) ? s : 0 } catch (e) { return 0 } }
function budgetLow() {
  if (!(BUDGET && BUDGET.total != null)) return false
  try { const t = Number(BUDGET.total), r = Number(BUDGET.remaining()); return Number.isFinite(t) && t > 0 && Number.isFinite(r) && r <= t * 0.1 } catch (e) { return false }
}
function budgetSpend() {
  if (!(BUDGET && BUDGET.total != null)) return null
  try { return { spentUsd: Number(BUDGET.spent()), totalUsd: Number(BUDGET.total) } } catch (e) { return null }
}

let agentsUsed = 0
let CAPS = { maxAgents: 10, tokenCeiling: 150000 }   // tightened after Config
function capReason() {
  if (agentsUsed >= CAPS.maxAgents) return 'agent-cap'
  if (spentTokens() >= CAPS.tokenCeiling) return 'token-ceiling'
  if (budgetLow()) return 'budget'
  return null
}
async function callAgent(prompt, opts) { agentsUsed++; return agent(prompt, opts) }

// ---- args ---------------------------------------------------------------------------------------
const A = (args && typeof args === 'object') ? args : {}
const dateStamp = A.dateStamp || 'latest'

// ---- schemas ------------------------------------------------------------------------------------
const CONF = {
  type: 'object',
  properties: {
    QA_MODE: { type: 'string' }, QA_MIN_SEVERITY: { type: 'string' }, QA_AUTOFIX: { type: 'string' },
    QA_MAX_AGENTS: { type: 'number' }, QA_TOKEN_CEILING: { type: 'number' }, QA_MAX_FINDINGS: { type: 'number' },
    QA_MAX_FIXES: { type: 'number' }, QA_THREAT_MODEL: { type: 'string' },
    targets: { type: 'array', items: { type: 'string' } }, testCmd: { type: 'string' },
  },
  required: ['targets', 'testCmd'],
}
const FINDINGS = {
  type: 'object',
  properties: {
    abstained: { type: 'boolean' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          target: { type: 'string' }, line: { type: 'number' }, claim: { type: 'string' },
          repro: { type: 'string' }, proposedSeverity: { type: 'string' },
        },
        required: ['target', 'line', 'claim', 'repro', 'proposedSeverity'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: {
    verdict: { type: 'string' },         // CONFIRMED | NOT-REPRODUCED | WORKS-AS-INTENDED | OUT-OF-SCOPE
    reproduced: { type: 'boolean' },
    severity: { type: 'string' },        // critical | high | low | nitpick
    confidence: { type: 'string' },      // high | low
    evidence: { type: 'string' },        // the command run + captured output, or why it's dropped
    recommendation: { type: 'string' },
  },
  required: ['verdict', 'reproduced', 'severity', 'confidence', 'evidence'],
}
const GATE = { type: 'object', properties: { pass: { type: 'boolean' }, summary: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } } }, required: ['pass', 'summary', 'issues'] }

// ================================================================================================
// Orchestration
// ================================================================================================
phase('Config')
const raw = await callAgent(
  `Read .agent/qa.conf and .agent/lifecycle.conf. Return the QA_* keys as a structured object plus ` +
  `targets = ${Array.isArray(A.targets) ? JSON.stringify(A.targets) : 'the QA_TARGETS list (full manifest)'} ` +
  `and testCmd = the TEST_CMD from .agent/lifecycle.conf. Do not edit anything.`,
  { label: 'qa:config', phase: 'Config', schema: CONF })
const cfg = resolveConfig(raw, A)
CAPS = { maxAgents: cfg.maxAgents, tokenCeiling: cfg.tokenCeiling }
log(`Mode ${cfg.mode} · bar ${cfg.minSeverity} · ${cfg.targets.length} target(s) · caps: ≤${cfg.maxAgents} agents, ≤${cfg.tokenCeiling} tok · autofix: ${[...cfg.autofix].join(',') || 'off'}`)

// ---- Review: ONE grounded reviewer ----------------------------------------------------------------
phase('Review')
let candidates = []
let stop = 'done'
if (capReason()) { stop = capReason() }
else {
  const review = await callAgent(
    `First read .claude/agents/qa-adversary.md and ADOPT that role (a precision-first grounded reviewer). ` +
    `Targets: ${JSON.stringify(cfg.targets)}. Threat model: ${cfg.threatModel} ` +
    `Return at MOST ${cfg.maxFindings} of the SHARPEST, real issues — each MUST cite an exact file:line and a ` +
    `literal, safe reproduction. If you are not confident an issue is real and reproducible, DO NOT include it. ` +
    `Returning an EMPTY findings list (abstaining) is the correct, expected answer for clean code.`,
    { label: 'review', phase: 'Review', schema: FINDINGS })
  candidates = (review.findings || []).slice(0, cfg.maxFindings)
  log(`Review: ${candidates.length} candidate(s)${candidates.length === 0 ? ' — abstained (clean)' : ''}.`)
}

// ---- Verify: reproduce-or-DROP + classify severity ------------------------------------------------
phase('Verify')
const confirmed = []
const rejected = []
for (const f of candidates) {
  if (capReason()) { stop = capReason(); break }
  const v = await callAgent(
    `First read .claude/agents/qa-verifier.md and ADOPT that role (a hostile skeptic). Candidate: ${JSON.stringify(f)}. ` +
    `REPRODUCE it against the real code in a temp sandbox (mktemp -d; never run a genuinely destructive command — ` +
    `demonstrate via echo/expansion/dry-run instead), or DROP it. Classify severity as critical|high|low|nitpick ` +
    `under the threat model: ${cfg.threatModel} Edit nothing tracked.`,
    { label: `verify:${f.target}:${f.line}`, phase: 'Verify', schema: VERDICT })
  const id = `${(f.target || '').split('/').pop()}:${f.line}`
  if (v.verdict === 'CONFIRMED' && v.reproduced === true) {
    confirmed.push({ id, target: f.target, line: f.line, claim: f.claim, repro: f.repro, severity: v.severity, confidence: v.confidence, evidence: v.evidence, recommendation: v.recommendation, tier: tierFor(v.severity, cfg.minSeverity) })
  } else {
    rejected.push({ id, verdict: v.verdict, why: v.evidence })
  }
}
log(`Verify: ${confirmed.length} confirmed, ${rejected.length} dropped.`)

// ---- Fix: ONLY with --autofix, scoped to the named severities -------------------------------------
phase('Fix')
let branch = null
if (cfg.autofix.size && !capReason()) {
  const toFix = confirmed.filter((c) => c.tier === 'fix' && cfg.autofix.has(c.severity)).slice(0, cfg.maxFixes)
  if (toFix.length) {
    const b = await callAgent(`Create+switch to git branch "qa/fix-${dateStamp}" off main (git checkout -b). Report ONLY the branch name.`, { label: 'fix:branch', phase: 'Fix' })
    branch = (b || '').trim().split(/\s+/).pop() || `qa/fix-${dateStamp}`
    for (const rf of toFix) {
      if (capReason()) { stop = capReason(); break }
      await callAgent(
        `On branch ${branch}, fix ONLY this confirmed ${rf.severity} finding TEST-FIRST: ${rf.claim} (${rf.target}:${rf.line}). ` +
        `Repro: ${rf.repro}. Add a regression test, confirm it FAILS, then the minimal fix to GREEN; do NOT weaken tests. Commit.`,
        { label: `fix:${rf.id}`, phase: 'Fix' })
      rf.tier = 'auto-fixed'; rf.fixBranch = branch
    }
    if (cfg.testCmd && !capReason()) {
      await callAgent(`Run \`${cfg.testCmd}\` from the repo root once and report pass/fail. Do not edit files.`, { label: 'fix:full-suite', phase: 'Fix', schema: GATE })
    }
  }
}

// ---- Report: rank, write, STOP --------------------------------------------------------------------
phase('Report')
const sidecar = buildSidecar({ date: dateStamp, mode: cfg.mode, targets: cfg.targets, minSeverity: cfg.minSeverity, stop, agentsUsed, spend: budgetSpend(), rejectedCount: rejected.length }, confirmed)
const md = renderMarkdown(sidecar, rejected)
await callAgent(
  `Write a QA report to qa/reports/qa-${dateStamp}.md (create dirs; if dateStamp is "latest", run \`date +%F\` and use that ` +
  `date in the filename + title). Write EXACTLY this Markdown:\n\n${md}\n\nAlso write the JSON sidecar to ` +
  `qa/reports/qa-${dateStamp}.json with: ${JSON.stringify(sidecar).slice(0, 12000)} . Report the path. Do not change any other file.`,
  { label: 'report:write', phase: 'Report' })

return {
  mode: cfg.mode,
  targets: cfg.targets.length,
  agentsUsed,
  stop,
  findings: { fix: sidecar.meta.counts.fix, backlog: sidecar.meta.counts.backlog, autoFixed: sidecar.meta.counts.autoFixed, dropped: rejected.length },
  branch,
  abstained: confirmed.length === 0,
  next: branch ? `Review branch ${branch} + qa/reports/, then merge/PR.` : `Report-only run — see qa/reports/qa-${dateStamp}.md.`,
}
