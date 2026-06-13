export const meta = {
  name: 'qa-loop',
  description: 'Adversarially QA the repo\'s own tooling (hooks, test scripts, the orchestrator). Generate candidate failures -> REPRODUCE each against the real code -> fix CONFIRMED ones test-first (RED before green) -> loop until K dry rounds. A finding counts only when a skeptic reproduces it. Stops before the PR. Config in .agent/qa.conf; the fix oracle is TEST_CMD from .agent/lifecycle.conf.',
  phases: [
    { title: 'Target-select', detail: 'read .agent/qa.conf + lifecycle.conf; resolve the SUT manifest' },
    { title: 'Generate',      detail: 'one qa-adversary per lens fans out candidate findings with repro recipes' },
    { title: 'Verify',        detail: 'qa-verifier REPRODUCES each deduped candidate in a temp dir; default REJECT' },
    { title: 'Fix',           detail: 'per CONFIRMED: regression test first (prove RED) -> fix -> full TEST_CMD green' },
    { title: 'Triage',        detail: 'report confirmed-fixed / confirmed-deferred / rejected-with-reason' },
  ],
}

// ---- args ---------------------------------------------------------------------------------
// { targets?: string[], minSeverity?: 'high', dateStamp?: 'YYYY-MM-DD' }
const argTargets   = (args && typeof args === 'object' && Array.isArray(args.targets)) ? args.targets : null
const minSeverity  = (args && typeof args === 'object' && args.minSeverity) || null
const dateStamp    = (args && typeof args === 'object' && args.dateStamp) || null   // avoid new Date() in-script

// ---- schemas ------------------------------------------------------------------------------
const CONF = {
  type: 'object',
  properties: {
    lenses:        { type: 'array', items: { type: 'string' } },
    targets:       { type: 'array', items: { type: 'string' } },
    maxRounds:     { type: 'number' },
    dryStreakStop: { type: 'number' },
    testCmd:       { type: 'string' },
    threatModel:   { type: 'string' },
  },
  required: ['lenses', 'targets', 'maxRounds', 'dryStreakStop', 'testCmd', 'threatModel'],
}
const FINDING = {
  type: 'object',
  properties: {
    target:   { type: 'string' },
    line:     { type: 'number' },
    class:    { type: 'string' },   // boundary|threat-evasion|race|encoding|gate-false-verdict|dos
    claim:    { type: 'string' },
    repro:    { type: 'string' },   // literal input + exact command + expected-vs-actual
    severity: { type: 'string' },   // high|med|low
  },
  required: ['target', 'line', 'class', 'claim', 'repro', 'severity'],
}
const FINDINGS = { type: 'object', properties: { findings: { type: 'array', items: FINDING } }, required: ['findings'] }
const VERDICT = {
  type: 'object',
  properties: {
    verdict:    { type: 'string' },  // CONFIRMED|WORKS-AS-INTENDED|WRONG-THREAT-MODEL|LOW-SEV-DEFER
    reproduced: { type: 'boolean' },
    evidence:   { type: 'string' },  // literal command run + captured exit/output, or why it's a reject
  },
  required: ['verdict', 'reproduced', 'evidence'],
}
const GATE = {  // identical shape to feature-pipeline.js
  type: 'object',
  properties: { pass: { type: 'boolean' }, summary: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } } },
  required: ['pass', 'summary', 'issues'],
}

// ---- Target-select ------------------------------------------------------------------------
phase('Target-select')
const conf = await agent(
  `Read .agent/qa.conf and .agent/lifecycle.conf and return structured config. ` +
  `targets = ${argTargets ? JSON.stringify(argTargets) : 'the QA_TARGETS list from .agent/qa.conf'}. ` +
  `lenses = QA_LENSES; maxRounds = QA_MAX_ROUNDS (default 4); dryStreakStop = QA_DRY_STREAK (default 2); ` +
  `threatModel = QA_THREAT_MODEL; testCmd = the TEST_CMD from .agent/lifecycle.conf (the FULL oracle). ` +
  `Do not edit anything.`,
  { label: 'qa:config', phase: 'Target-select', schema: CONF })

log(`QA targets (${conf.targets.length}): ${conf.targets.join(', ')}\nLenses: ${conf.lenses.join(', ')}`)

const seen = new Set()                       // dedup keys across all rounds (anti re-litigation)
const triage = { fixed: [], deferred: [], rejected: [] }
let dryStreak = 0
let round = 0
let branch = null                            // created lazily on the first CONFIRMED fix

const keyOf = (f) => `${(f.target || '').split('/').pop()}:${f.line}:${f.class}`

while (round < conf.maxRounds && dryStreak < conf.dryStreakStop) {
  round++

  // ---- Generate (fan-out, one agent per lens) --------------------------------------------
  phase('Generate')
  const batches = await parallel(conf.lenses.map((lens) => () => agent(
    `You are the qa-adversary. Lens: "${lens}". Targets: ${JSON.stringify(conf.targets)}. Round ${round}. ` +
    `Read the real code and produce candidate FAILURE findings for THIS lens only, each with file:line, a ` +
    `one-line claim, and a concrete repro recipe (literal input + exact command + expected-vs-actual). ` +
    `THREAT MODEL: ${conf.threatModel} Do NOT report findings that presuppose file-write/RCE. ` +
    `Do NOT re-report these already-seen ids: ${JSON.stringify([...seen])}. Read-only; edit nothing.`,
    { label: `gen:${lens}#${round}`, phase: 'Generate', schema: FINDINGS, agentType: 'qa-adversary' }
  )))

  // ---- Dedup (plain JS) ------------------------------------------------------------------
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

  // ---- Verify (the linchpin: reproduce-or-reject) ----------------------------------------
  phase('Verify')
  let confirmedThisRound = 0
  for (const f of fresh) {
    const v = await agent(
      `You are the qa-verifier — a hostile skeptic. Candidate: ${JSON.stringify(f)}. ` +
      `REPRODUCE it against the real code or REJECT it: (1) mktemp -d; (2) write the minimal failing input ` +
      `there and run the real target (e.g. \`echo '<json>' | sh ${f.target}\` or \`sh ${f.target} <tmp>\`), ` +
      `capturing exit code + output; (3) rm -rf the temp dir. CONFIRMED requires reproduced=true AND the ` +
      `literal command + captured output in evidence. DEFAULT TO REJECTING — a claim you cannot reproduce ` +
      `is WORKS-AS-INTENDED, never CONFIRMED. Threat model: ${conf.threatModel} Edit nothing tracked.`,
      { label: `verify:${f.id}`, phase: 'Verify', schema: VERDICT, agentType: 'qa-verifier' })

    const confirmed = v.verdict === 'CONFIRMED' && v.reproduced === true
    if (!confirmed) { triage.rejected.push({ id: f.id, severity: f.severity, verdict: v.verdict, why: v.evidence }); continue }
    if (minSeverity === 'high' && f.severity !== 'high') { triage.deferred.push({ id: f.id, reason: 'below minSeverity', f, v }); continue }

    confirmedThisRound++

    // ---- branch lazily (only once we actually have a fix to make) -------------------------
    if (!branch) {
      const b = await agent(
        `Create and switch to a new git branch for QA fixes off main: ` +
        `name it "qa/loop-fixes-$(date +%Y%m%d)" (use git checkout -b if it doesn't exist; if it exists, switch to it). ` +
        `Report ONLY the exact current branch name.`,
        { label: 'fix:branch', phase: 'Fix' })
      branch = (b || '').trim().split(/\s+/).pop() || 'qa/loop-fixes'
      log(`Fixing on branch: ${branch}`)
    }

    // ---- Fix (RED-first; full-oracle gate) -----------------------------------------------
    phase('Fix')
    let fixGate = { pass: false, summary: '', issues: [] }
    let redProven = false
    for (let i = 1; i <= 4; i++) {
      if (i === 1) {
        await agent(
          `CONFIRMED defect on branch ${branch} in ${f.target}: ${f.claim}\nRepro: ${f.repro}\nEvidence: ${v.evidence}\n` +
          `STEP 1 (RED): add a regression case that encodes this repro — extend the target script's own self_test() ` +
          `if it has one (e.g. tests/check-qa-manifest.sh / tests/check-skill-mirror.sh patterns), else add a case to ` +
          `tests/validate.sh, else a new tests/check-*.sh. Run ONLY that new case and CONFIRM IT FAILS (prove RED) — ` +
          `a regression test that passes before the fix is invalid. Do NOT touch ${f.target} yet. Commit the RED test. ` +
          `Report the failing output.`,
          { label: `fix:red#${f.id}`, phase: 'Fix' })
      } else {
        await agent(
          `STEP 2 (GREEN) on branch ${branch}: now fix ${f.target} so the regression case passes — minimal change, ` +
          `do NOT weaken or delete any existing assertion, do NOT edit the regression test to pass. ` +
          `Previous gate output: ${fixGate.summary}. Commit the fix. Report the diff.`,
          { label: `fix:green#${f.id}@${i}`, phase: 'Fix' })
      }
      fixGate = await agent(
        `Run the FULL oracle (TEST_CMD from .agent/lifecycle.conf) from the repo root, AND grep that the new ` +
        `regression case is present and asserting. pass=true ONLY if every command exits 0 AND the new case exists. ` +
        `Do NOT edit files; only run and report (put the failing tail in summary).`,
        { label: `fix:gate#${f.id}@${i}`, phase: 'Fix', schema: GATE })
      if (i === 1) { redProven = (fixGate.pass === false); fixGate.pass = false; continue }  // round 1 is RED-proof only
      if (fixGate.pass) break
    }
    if (fixGate.pass) triage.fixed.push({ id: f.id, severity: f.severity, redProven, claim: f.claim })
    else triage.deferred.push({ id: f.id, reason: 'fix did not reach green within cap', issues: fixGate.issues })
  }

  if (confirmedThisRound === 0) dryStreak++; else dryStreak = 0
  log(`Round ${round}: confirmed=${confirmedThisRound}, dryStreak=${dryStreak}/${conf.dryStreakStop}.`)
}

// ---- Triage report ------------------------------------------------------------------------
phase('Triage')
const stamp = dateStamp || 'latest'
await agent(
  `Write a QA triage report at qa/reports/qa-${stamp}.md (create dirs; if the stamp is "latest", first run ` +
  `\`date +%F\` and use that date in the filename and title instead). Three sections: ` +
  `1) CONFIRMED & FIXED — id, severity, whether RED was proven first, the regression test path. ` +
  `2) CONFIRMED & DEFERRED — id + why. ` +
  `3) REJECTED — id + verdict + the one-line reason it is NOT a bug (so it is never re-investigated). ` +
  `Lead with a one-paragraph summary (rounds run, stop reason, counts). Data: ${JSON.stringify(triage).slice(0, 14000)}. ` +
  `Do NOT commit; leave it staged for human review. Report the report path.`,
  { label: 'triage:report', phase: 'Triage' })

return {
  targets: conf.targets.length,
  rounds: round,
  stop: dryStreak >= conf.dryStreakStop ? `dry-streak (${conf.dryStreakStop} rounds, no new CONFIRMED)` : `max rounds (${conf.maxRounds})`,
  branch,
  confirmedFixed: triage.fixed.map((x) => x.id),
  confirmedDeferred: triage.deferred.map((x) => x.id),
  rejected: triage.rejected.length,
  seen: seen.size,
  next: branch
    ? `Human gate: review branch ${branch} + qa/reports/, then merge/PR.`
    : `No fixes needed — review qa/reports/ for the rejected-candidate reasoning.`,
}
