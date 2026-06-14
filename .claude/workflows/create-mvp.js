export const meta = {
  name: 'create-mvp',
  description: 'Drive a GREENFIELD project from an idea/spec to its first FULLY-FUNCTIONAL MVP. Refine the MVP spec (scope-cut + definition-of-done + a test oracle) -> scaffold (or confirm) the agent-first layer + a green test harness -> decompose the MVP into small, always-functional slices -> build each slice TEST-FIRST on one stacking branch, gated by the oracle -> integrate + a definition-of-done gate. Stops before the PR. Config in .agent/lifecycle.conf.',
  phases: [
    { title: 'Spec',      detail: 'refine the idea/SPEC into a tight MVP: scope-cut, definition-of-done, and the test oracle' },
    { title: 'Scaffold',  detail: 'stand up (or confirm) the agent-first layer + a green test harness so the oracle is live' },
    { title: 'Decompose', detail: 'break the MVP into ordered, independently-testable, always-functional slices' },
    { title: 'Build',     detail: 'build each slice test-first on one stacking branch, looping on the oracle' },
    { title: 'Integrate', detail: 'run the full definition-of-done + a final review; report' },
  ],
}

// ---- args: an idea string, or a path to an existing spec ---------------------------------
// { idea?: string, specPath?: string, stack?: string, maxSlices?: number }
const idea      = (args && typeof args === 'object' && args.idea) || (typeof args === 'string' ? args : '')
const specPath0 = (args && typeof args === 'object' && args.specPath) || ''
const stackHint = (args && typeof args === 'object' && args.stack) || ''
const maxSlices = (args && typeof args === 'object' && args.maxSlices) || 8
if (!idea && !specPath0) throw new Error('Pass {idea: "..."} or {specPath: "docs/SPEC.md"} (or a plain idea string).')

const GATE = {
  type: 'object',
  properties: { pass: { type: 'boolean' }, summary: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } } },
  required: ['pass', 'summary', 'issues'],
}
const SPECOUT = {
  type: 'object',
  properties: {
    specPath: { type: 'string' },
    testCmd:  { type: 'string' },                      // the oracle that proves the MVP works
    slug:     { type: 'string' },                      // kebab id for the branch
    dod:      { type: 'array', items: { type: 'string' } },  // definition-of-done bullets
  },
  required: ['specPath', 'testCmd', 'slug', 'dod'],
}
const SLICES = {
  type: 'object',
  properties: {
    slices: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, title: { type: 'string' }, goal: { type: 'string' }, acceptance: { type: 'string' } },
        required: ['id', 'title', 'goal', 'acceptance'],
      },
    },
  },
  required: ['slices'],
}

// ---- Spec: refine -> review loop --------------------------------------------------------
phase('Spec')
let spec = null
let specGate = { pass: false, summary: '', issues: [] }
for (let i = 1; i <= 2; i++) {
  spec = await agent(
    `${i === 1 ? 'Produce' : 'Revise'} a TIGHT MVP spec for this greenfield project. ` +
    `${specPath0
      ? `A spec already exists at ${specPath0} — READ and refine it in place; do not regenerate from scratch.`
      : `Idea: "${idea}".`} ` +
    `${stackHint ? `Intended stack: ${stackHint}. ` : ''}` +
    `The spec MUST contain: the smallest VERTICAL SLICE that is genuinely fully-functional; an explicit list of what is ` +
    `OUT of the MVP; a concrete **Definition of Done** as checkable bullets; and the **test oracle** — the exact command ` +
    `that proves the MVP works (prefer a deterministic/headless test; reuse TEST_CMD from .agent/lifecycle.conf if present). ` +
    `Write it to ${specPath0 || 'docs/SPEC.md'}. ${i > 1 ? 'Address the reviewer issues: ' + JSON.stringify(specGate.issues) : ''} ` +
    `Return specPath, testCmd, a kebab-case slug, and the DoD bullets.`,
    { label: `spec:draft#${i}`, phase: 'Spec', schema: SPECOUT })
  specGate = await agent(
    `Review the MVP spec at ${spec.specPath} as a skeptical senior engineer. Is the slice truly minimal yet fully-functional, ` +
    `is scope explicitly cut, is the Definition of Done concretely checkable, and can the oracle (\`${spec.testCmd}\`) actually ` +
    `verify it? pass=true only if all yes; else list precise issues.`,
    { label: `spec:review#${i}`, phase: 'Spec', schema: GATE })
  if (specGate.pass) break
}
if (!specGate.pass) return { stoppedAt: 'Spec', reason: 'MVP spec failed review', gate: specGate }
log(`MVP spec: ${spec.specPath}\nOracle: ${spec.testCmd}\nDoD: ${spec.dod.length} item(s)`)

// ---- Scaffold: ensure a GREEN test harness so the oracle is live ------------------------
phase('Scaffold')
const scaffold = await agent(
  `Ensure this repo has an agent-first layer + a GREEN test harness so the oracle is live from the start. ` +
  `If AGENTS.md + .agent/hooks + a working test command (\`${spec.testCmd}\`) already exist and pass, just CONFIRM (do nothing ` +
  `destructive). Otherwise scaffold them via the scaffold-agent-project skill (AGENTS.md, guardrail hooks incl. capture-learnings, ` +
  `a code-reviewer subagent, and a minimal ${stackHint || 'stack'} skeleton whose test command is green from commit 1). ` +
  `Then run \`${spec.testCmd}\` and report pass/fail (pass=true only if it exits 0).`,
  { label: 'scaffold:setup', phase: 'Scaffold', schema: GATE })
if (!scaffold.pass) return { stoppedAt: 'Scaffold', reason: 'agent-first layer / test harness not green', gate: scaffold }

// ---- Decompose: MVP -> ordered, always-functional slices --------------------------------
phase('Decompose')
const decomp = await agent(
  `Read the MVP spec at ${spec.specPath} (Definition of Done: ${JSON.stringify(spec.dod)}). Decompose the MVP into an ORDERED list ` +
  `of small, independently-testable slices, ordered by dependency — each slice MUST leave the project runnable/functional when done ` +
  `(incremental, always-playable milestones). At most ${maxSlices} slices. For each: id, title, goal, and concrete acceptance ` +
  `criteria (what its tests will assert against the oracle).`,
  { label: 'decompose', phase: 'Decompose', schema: SLICES })
const slices = (decomp.slices || []).slice(0, maxSlices)
if (!slices.length) return { stoppedAt: 'Decompose', reason: 'no slices produced' }
log(`MVP -> ${slices.length} slice(s): ${slices.map((s) => s.title).join(' · ')}`)

// ---- Build: ONE stacking branch; each slice test-first, gated by the oracle --------------
phase('Build')
const branchInfo = await agent(
  `Create and switch to a single git branch for the MVP off main: \`mvp/${spec.slug}\` (git checkout -b if it doesn't exist; ` +
  `else switch to it). ALL slices stack on this one branch so later slices build on earlier ones. Report ONLY the branch name.`,
  { label: 'build:branch', phase: 'Build' })
const branch = (branchInfo || '').trim().split(/\s+/).pop() || `mvp/${spec.slug}`
log(`Building all slices on: ${branch}`)

const built = []
for (const s of slices) {
  log(`Slice: ${s.title}`)
  let gate = { pass: false, summary: '', issues: [] }
  for (let i = 1; i <= 6; i++) {
    await agent(
      `On branch ${branch}, ${i === 1 ? 'implement' : 'fix'} slice "${s.title}" TEST-FIRST. Goal: ${s.goal}. ` +
      `Acceptance: ${s.acceptance}. Per the MVP spec at ${spec.specPath}. Write the tests FIRST and confirm they FAIL (RED), ` +
      `then write the minimal code to make them GREEN. Keep the pure/deterministic core pure (no nondeterminism in the logic core). ` +
      `**Do NOT weaken, skip, or delete tests to pass.** ${i > 1 ? 'The gate failed — fix it. Last output:\n' + gate.summary : ''} ` +
      `Make a focused commit. Report what changed.`,
      { label: `build:${s.id}#${i}`, phase: 'Build' })
    gate = await agent(
      `Run the oracle \`${spec.testCmd}\` from the repo root. pass=true ONLY if it exits 0 AND the new slice's tests are present ` +
      `and asserting (grep for them). Put any failure tail in summary. Do NOT edit files; only run and report.`,
      { label: `build:gate:${s.id}#${i}`, phase: 'Build', schema: GATE })
    if (gate.pass) break
  }
  if (!gate.pass) return { stoppedAt: `Build:${s.id}`, reason: `slice "${s.title}" not green after the cap — surfacing to a human`, branch, gate, built }
  const rev = await agent(
    `Act as the code-reviewer (fresh, adversarial eyes). Review the slice's changes on ${branch} (\`git diff main...${branch}\` — focus ` +
    `on the latest slice): correctness, and whether the gate was GAMED (tests weakened/deleted, determinism broken). pass=true only if ` +
    `no must-fix findings; list must-fix items. Do not edit files.`,
    { label: `build:review:${s.id}`, phase: 'Build', schema: GATE })
  built.push({ slice: s.id, title: s.title, review: rev.pass ? 'clean' : 'has-findings', findings: rev.issues })
}

// ---- Integrate: full Definition-of-Done gate --------------------------------------------
phase('Integrate')
const dodGate = await agent(
  `All MVP slices are built on ${branch}. Verify the FULL Definition of Done from ${spec.specPath} ` +
  `(${JSON.stringify(spec.dod)}) end-to-end: run the oracle \`${spec.testCmd}\` and confirm every DoD bullet is genuinely satisfied ` +
  `(not merely that tests pass). pass=true only if the MVP is actually functional per the DoD; else list exactly what's missing. ` +
  `Do not edit files; only verify and report.`,
  { label: 'integrate:dod', phase: 'Integrate', schema: GATE })

return {
  spec: spec.specPath,
  oracle: spec.testCmd,
  branch,
  slices: slices.map((s) => s.title),
  built: built.map((b) => ({ slice: b.slice, review: b.review })),
  mvp: dodGate.pass ? 'functional — Definition of Done met' : 'incomplete — see dodIssues',
  dodIssues: dodGate.issues,
  next: dodGate.pass
    ? `Human gate: review branch ${branch} + play the MVP, then open a PR.`
    : `Human gate: finish the remaining Definition-of-Done items on ${branch}.`,
}
