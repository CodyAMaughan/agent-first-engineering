// budget-config.js — read + validate .agent/budget.conf (the JS twin of the POSIX KEY=value
// grammar in contracts/budget.conf.schema.md). Fails CLOSED: a malformed/contradictory value
// makes the workflow refuse to start, so a typo can never silently disable the guardrail
// (Constitution IV). Absent file ⇒ a disabled no-op (opt-in, SC-005).
//
// This module is agent-neutral — it knows nothing about Claude paths.
import { readFileSync } from 'node:fs'

const FALLBACKS = ['block', 'assume-max', 'warn-continue']

// Parse a shell-sourceable KEY=value file the way a POSIX `sh` reader would see it: ignore blank
// lines and `#` comments, strip a trailing inline comment, and unquote a simple value. We do NOT
// execute the file (no command substitution) — it is data, not code.
function parseConfFile(path) {
  const raw = readFileSync(path, 'utf8')
  const out = {}
  for (let line of raw.split('\n')) {
    line = line.trim()
    if (!line || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq < 0) continue
    const key = line.slice(0, eq).trim()
    let val = line.slice(eq + 1)
    // Strip a trailing inline comment only when the value is unquoted.
    const isQuoted = /^\s*["']/.test(val)
    if (!isQuoted) {
      const hash = val.indexOf('#')
      if (hash >= 0) val = val.slice(0, hash)
      val = val.trim()
    } else {
      val = val.trim().replace(/^["']|["']$/g, '')
    }
    if (key) out[key] = val
  }
  return out
}

function asNumber(v, key) {
  if (v === undefined || v === '') return undefined
  const n = Number(v)
  if (!Number.isFinite(n)) throw new Error(`budget.conf: ${key} must be a number, got "${v}"`)
  return n
}
function asInt(v, key) {
  const n = asNumber(v, key)
  if (n === undefined) return undefined
  if (!Number.isInteger(n)) throw new Error(`budget.conf: ${key} must be an integer, got "${v}"`)
  return n
}
function asBool(v) {
  return String(v).trim().toLowerCase() === 'true'
}

// readBudgetConfig(path) -> BudgetConfig. Absent file ⇒ { enabled:false } (no-op).
export function readBudgetConfig(path) {
  let kv
  try {
    kv = parseConfFile(path)
  } catch {
    // No file (or unreadable) ⇒ opt-in default: disabled, behavior unchanged (SC-005).
    return { enabled: false }
  }

  const enabled = kv.BUDGET_ENABLED === undefined ? true : asBool(kv.BUDGET_ENABLED)
  if (!enabled) return { enabled: false }

  const softUsd = asNumber(kv.PERTASK_SOFT_USD, 'PERTASK_SOFT_USD')
  const hardUsd = asNumber(kv.PERTASK_HARD_USD, 'PERTASK_HARD_USD')
  const hardTokens = asInt(kv.PERTASK_HARD_TOKENS, 'PERTASK_HARD_TOKENS')
  const workflowHardUsd = asNumber(kv.PERWORKFLOW_HARD_USD, 'PERWORKFLOW_HARD_USD')
  const iterationCap = asInt(kv.ITERATION_CAP, 'ITERATION_CAP')
  const source = kv.PRICE_TABLE_SOURCE || 'litellm'
  const maxAgeHours = asNumber(kv.PRICE_TABLE_MAX_AGE_HOURS, 'PRICE_TABLE_MAX_AGE_HOURS')
  const fallback = kv.PRICE_TABLE_FALLBACK || 'assume-max'

  // --- fail-closed validation (a typo must never disable the guardrail) ---------------------
  if (hardUsd === undefined) throw new Error('budget.conf: PERTASK_HARD_USD is required')
  if (softUsd === undefined) throw new Error('budget.conf: PERTASK_SOFT_USD is required')
  if (!(softUsd < hardUsd)) {
    throw new Error(`budget.conf: PERTASK_SOFT_USD (${softUsd}) must be < PERTASK_HARD_USD (${hardUsd}) [soft alert before hard abort]`)
  }
  if (workflowHardUsd !== undefined && !(workflowHardUsd >= hardUsd)) {
    throw new Error(`budget.conf: PERWORKFLOW_HARD_USD (${workflowHardUsd}) must be >= PERTASK_HARD_USD (${hardUsd})`)
  }
  if (iterationCap === undefined || iterationCap < 1) {
    throw new Error(`budget.conf: ITERATION_CAP must be an integer >= 1, got "${kv.ITERATION_CAP}"`)
  }
  if (!FALLBACKS.includes(fallback)) {
    throw new Error(`budget.conf: PRICE_TABLE_FALLBACK must be one of ${FALLBACKS.join(' | ')}, got "${fallback}"`)
  }
  if (maxAgeHours === undefined || maxAgeHours <= 0) {
    throw new Error(`budget.conf: PRICE_TABLE_MAX_AGE_HOURS must be a positive number, got "${kv.PRICE_TABLE_MAX_AGE_HOURS}"`)
  }

  return {
    enabled: true,
    perTask: { softUsd, hardUsd, hardTokens },
    perWorkflow: { hardUsd: workflowHardUsd },
    iterationCap,
    priceTable: { source, maxAgeHours, fallback },
  }
}
