export const meta = {
  name: 'feature-pipeline',
  description: 'Drive a feature request to a review-ready branch through verified, looping stages: spec → plan → implement (test-gate) → review. Stops before the PR for human sign-off. Config in .agent/lifecycle.conf.',
  phases: [
    { title: 'Setup', detail: 'read .agent/lifecycle.conf + derive a branch slug' },
    { title: 'Spec', detail: 'draft → review loop until the spec is clear & testable' },
    { title: 'Plan', detail: 'draft → review loop until the plan satisfies the spec' },
    { title: 'Implement', detail: 'code → TEST_CMD gate loop until green (or the cap)' },
    { title: 'Review', detail: 'adversarial code-reviewer gate; fix → re-review' },
    { title: 'Ready', detail: 'branch + summary ready for a human PR' },
  ],
}

// Accept the feature as a string or {feature: "..."}
const feature = (args && typeof args === 'object' && args.feature) || (typeof args === 'string' ? args : '')
if (!feature) throw new Error('Pass the feature request as args — e.g. {feature: "..."} or a plain string.')

const CONF = {
  type: 'object',
  properties: {
    slug: { type: 'string' }, baseBranch: { type: 'string' }, branchPrefix: { type: 'string' },
    maxSpecRounds: { type: 'number' }, maxPlanRounds: { type: 'number' },
    maxImplementRounds: { type: 'number' }, maxReviewRounds: { type: 'number' },
    reviewSubagent: { type: 'string' },
  },
  required: ['slug', 'baseBranch', 'branchPrefix', 'maxSpecRounds', 'maxPlanRounds', 'maxImplementRounds', 'maxReviewRounds', 'reviewSubagent'],
}
const GATE = {
  type: 'object',
  properties: { pass: { type: 'boolean' }, summary: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } } },
  required: ['pass', 'summary', 'issues'],
}

phase('Setup')
const conf = await agent(
  `Read .agent/lifecycle.conf and return its values as structured config. Derive 'slug' = a short ` +
  `kebab-case id (<=5 words) for this feature: "${feature}". Use these defaults for any missing key: ` +
  `baseBranch main, branchPrefix feat/, maxSpecRounds 2, maxPlanRounds 2, maxImplementRounds 6, ` +
  `maxReviewRounds 2, reviewSubagent code-reviewer.`,
  { label: 'setup:config', phase: 'Setup', schema: CONF })

const branch = conf.branchPrefix + conf.slug
log(`Feature: ${feature}\nBranch:  ${branch}`)

// ---- Spec: draft → review loop -------------------------------------------------
phase('Spec')
let specGate = { pass: false, summary: '', issues: [] }
for (let i = 1; i <= conf.maxSpecRounds; i++) {
  await agent(
    `${i === 1 ? 'Write' : 'Revise'} the spec at specs/${conf.slug}/spec.md (create dirs) for: "${feature}". ` +
    `A spec is tight: **Goal**, **Scope** (in/out), 1-2 **Contracts/interfaces**, and **Acceptance criteria** ` +
    `that are concretely checkable. ${i > 1 ? 'Address the reviewer issues: ' + JSON.stringify(specGate.issues) : ''} Report the path.`,
    { label: `spec:draft#${i}`, phase: 'Spec' })
  specGate = await agent(
    `Review specs/${conf.slug}/spec.md as a skeptical senior engineer. Is the goal clear, the scope right, ` +
    `and is every acceptance criterion something a test could actually verify? pass=true only if yes; else list precise issues.`,
    { label: `spec:review#${i}`, phase: 'Spec', schema: GATE })
  if (specGate.pass) break
}
if (!specGate.pass) return { stoppedAt: 'Spec', reason: `spec failed review after ${conf.maxSpecRounds} rounds`, gate: specGate }

// ---- Plan: draft → review loop -------------------------------------------------
phase('Plan')
let planGate = { pass: false, summary: '', issues: [] }
for (let i = 1; i <= conf.maxPlanRounds; i++) {
  await agent(
    `${i === 1 ? 'Write' : 'Revise'} specs/${conf.slug}/plan.md for the spec in specs/${conf.slug}/spec.md: ` +
    `the files to touch, the approach, and the **test strategy** (how each acceptance criterion gets verified). ` +
    `${i > 1 ? 'Address: ' + JSON.stringify(planGate.issues) : ''} Report the path.`,
    { label: `plan:draft#${i}`, phase: 'Plan' })
  planGate = await agent(
    `Review specs/${conf.slug}/plan.md against specs/${conf.slug}/spec.md. Does the plan fully satisfy the spec, ` +
    `and does every acceptance criterion have a concrete verification? pass=true only if yes; else list issues.`,
    { label: `plan:review#${i}`, phase: 'Plan', schema: GATE })
  if (planGate.pass) break
}
if (!planGate.pass) return { stoppedAt: 'Plan', reason: 'plan failed review', gate: planGate }

// ---- Implement: code → TEST_CMD gate loop --------------------------------------
phase('Implement')
await agent(
  `Create and switch to git branch "${branch}" off ${conf.baseBranch} (git checkout -b "${branch}" if it doesn't exist). Report the current branch.`,
  { label: 'implement:branch', phase: 'Implement' })
let implGate = { pass: false, summary: '', issues: [] }
for (let i = 1; i <= conf.maxImplementRounds; i++) {
  await agent(
    `${i === 1 ? 'Implement' : 'Fix'} the feature on branch ${branch} per specs/${conf.slug}/plan.md. Write/extend ` +
    `tests for the acceptance criteria where the stack supports it, then the code; make focused commits. ` +
    `**Do NOT weaken, skip, or delete tests to pass.** ${i > 1 ? 'The gate failed — fix it. Last output:\n' + implGate.summary : ''} Report what you changed.`,
    { label: `implement:code#${i}`, phase: 'Implement' })
  implGate = await agent(
    `Run the implement gate: read .agent/lifecycle.conf and execute its TEST_CMD (and LINT_CMD / TYPECHECK_CMD if non-empty) ` +
    `via Bash from the repo root. Return pass=true ONLY if every command exits 0; put the tail of any failure in summary. ` +
    `Do NOT edit any files — you only run the gate and report.`,
    { label: `implement:test-gate#${i}`, phase: 'Implement', schema: GATE })
  if (implGate.pass) break
}
if (!implGate.pass) return { stoppedAt: 'Implement', reason: `tests not green after ${conf.maxImplementRounds} rounds — surfacing to a human`, branch, gate: implGate }

// ---- Review: adversarial code-reviewer gate ------------------------------------
phase('Review')
let revGate = { pass: false, summary: '', issues: [] }
for (let i = 1; i <= conf.maxReviewRounds; i++) {
  revGate = await agent(
    `Act as a senior code reviewer with fresh, adversarial eyes (the ${conf.reviewSubagent} role). Review the diff of ` +
    `branch ${branch} vs ${conf.baseBranch}: run \`git diff ${conf.baseBranch}...${branch}\`. Check correctness, security, ` +
    `and whether any gate was GAMED (tests deleted/weakened, assertions removed, blanket lint/type ignores). ` +
    `pass=true only if there are NO must-fix findings; list must-fix items in issues. Do not edit files.`,
    { label: `review#${i}`, phase: 'Review', schema: GATE })
  if (revGate.pass) break
  await agent(
    `Address these must-fix review findings on branch ${branch} (edit + commit), WITHOUT weakening tests: ` +
    `${JSON.stringify(revGate.issues)}. Then re-run TEST_CMD from .agent/lifecycle.conf to confirm still green. Report what changed.`,
    { label: `review:fix#${i}`, phase: 'Review' })
}
if (!revGate.pass) return { stoppedAt: 'Review', reason: `unresolved must-fix review findings after ${conf.maxReviewRounds} rounds — surfacing to a human`, branch, gate: revGate }

phase('Ready')
log(`Pipeline complete — branch ${branch} is ready for human PR review.`)
return {
  feature,
  branch,
  spec: `specs/${conf.slug}/spec.md`,
  plan: `specs/${conf.slug}/plan.md`,
  testGate: 'green',
  review: revGate.pass ? 'clean' : 'has-unresolved-findings (review cap reached)',
  reviewFindings: revGate.issues,
  next: `Human gate: review branch ${branch}, then open a PR — CodeRabbit + CI run there.`,
}
