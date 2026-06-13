// qa-report.js — the PURE triage-report renderer for the QA-loop (contracts/report-schema.md).
// Given run metadata + ranked findings it produces (a) the JSON sidecar object and (b) the
// human-readable Markdown, both written by qa-loop.js's Triage phase. Pure + node-testable; no
// agent(), no fs, no new Date() (the date is threaded in via meta.date).
import { impactRank } from './qa-classify.js'

// rankFindings(findings) — order by impact rank (highest first), then by confidence (high before low),
// the ranked order the Markdown renders (report-schema: "ordered by impact rank, then by confidence").
export function rankFindings(findings) {
  const confRank = (c) => (c === 'high' ? 1 : 0)
  return [...(findings || [])].sort((a, b) => {
    const d = impactRank(b.impact) - impactRank(a.impact)
    if (d !== 0) return d
    return confRank(b.impactConfidence) - confRank(a.impactConfidence)
  })
}

// buildSidecar(meta, findings) -> the machine-readable object persisted as qa-<date>.json.
export function buildSidecar(meta, findings) {
  const ranked = rankFindings(findings)
  const counts = {
    fix: ranked.filter((f) => f.tier === 'fix').length,
    backlog: ranked.filter((f) => f.tier === 'backlog').length,
    autoFixed: ranked.filter((f) => f.tier === 'auto-fixed').length,
    rejected: meta.rejectedCount || 0,
    unverifiedAtAbort: ranked.filter((f) => f.tier === 'unverified-at-abort').length,
  }
  return {
    meta: {
      date: meta.date,
      mode: meta.mode,
      targets: meta.targets || [],
      minSeverity: meta.minSeverity,
      rounds: meta.rounds,
      stop: meta.stop,
      spend: meta.spend ?? null,
      counts,
    },
    findings: ranked,
  }
}

// renderMarkdown(sidecar) -> the qa-<date>.md text (report-schema §"Markdown layout").
export function renderMarkdown(sidecar, rejected = []) {
  const { meta, findings } = sidecar
  const fix = findings.filter((f) => f.tier === 'fix')
  const autoFixed = findings.filter((f) => f.tier === 'auto-fixed')
  const backlog = findings.filter((f) => f.tier === 'backlog')
  const unverified = findings.filter((f) => f.tier === 'unverified-at-abort')
  const c = meta.counts
  const L = []

  L.push(`# QA Triage Report — ${meta.date}`)
  L.push('')
  // 1. Summary
  L.push('## Summary')
  L.push(
    `Mode \`${meta.mode}\`; ${meta.rounds} round(s); stop: \`${meta.stop}\`. ` +
    `Fix: ${c.fix}, backlog: ${c.backlog}, auto-fixed: ${c.autoFixed}, rejected: ${c.rejected}, ` +
    `unverified-at-abort: ${c.unverifiedAtAbort}.` +
    (meta.spend ? ` Spend: ${JSON.stringify(meta.spend)}.` : '') +
    (['budget', 'max-fixes', 'max-rounds', 'wall-clock', 'aborted'].includes(meta.stop)
      ? `  **Ceiling breached: \`${meta.stop}\` — this is a PARTIAL report of findings so far.**`
      : ''),
  )
  L.push('')
  // 2. Fix tier
  L.push(`## Fix tier (≥ ${meta.minSeverity})`)
  if (!fix.length) L.push(`No fix-tier findings at/above the \`${meta.minSeverity}\` bar.`)
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
  else for (const f of backlog) L.push(`- \`${f.id}\` — ${f.impact} (below the \`${meta.minSeverity}\` bar): ${f.impactRationale || f.recommendation || 'below bar'}`)
  L.push('')
  // 5. Rejected
  L.push('## Rejected')
  if (!rejected.length) L.push('None.')
  else for (const r of rejected) L.push(`- \`${r.id}\` — ${r.verdict}: ${r.why || ''}`)
  L.push('')
  // 6. Unverified-at-abort — only if a ceiling tripped mid-verify
  if (unverified.length) {
    L.push('## Unverified-at-abort')
    for (const f of unverified) L.push(`- \`${f.id}\` — not resolved to a tier before the \`${meta.stop}\` ceiling tripped.`)
    L.push('')
  }
  return L.join('\n')
}

function renderFinding(f) {
  return (
    `- \`${f.id}\` — **${f.impact}** (confidence: ${f.impactConfidence}) at \`${f.target}:${f.line}\`\n` +
    `  - repro: ${f.repro}\n` +
    `  - recommendation: ${f.recommendation || ''}`
  )
}

export default { rankFindings, buildSidecar, renderMarkdown }
