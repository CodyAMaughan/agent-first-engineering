// price-table.js — the price-table adapter (FR-003, FR-019). Reads a cached LiteLLM-style
// `model_prices_and_context_window.json` (per-model, per-token-type rates), tracks freshness,
// and on a missing model/rate applies the configured fallback policy — NEVER silently $0.
//
// Agent-neutral: knows about the price-table SCHEMA, not about any agent's paths.
import { readFileSync, statSync } from 'node:fs'

// LiteLLM key names per token type. cache_read ≈ 0.1× input; cache_creation ≈ 1.25–2× input.
const KEY = {
  input: 'input_cost_per_token',
  output: 'output_cost_per_token',
  cacheRead: 'cache_read_input_token_cost',
  cacheWrite: 'cache_creation_input_token_cost',
}

// A conservative HIGH rate used by `assume-max` so an unknown model can never be under-costed.
// Anchored above current frontier list prices (Opus input is $15/Mtok = 1.5e-5/token); output is
// the priciest axis, so we cost ALL unknown token types at this ceiling.
const ASSUME_MAX_PER_TOKEN = 100 / 1e6 // $100 / 1M tokens

// loadPriceTable(config) -> PriceTable. Reads config.priceTable.cacheFile (or the default cache
// path); does not fetch over the network here (the cache is refreshed out-of-band) — but stamps
// freshness so callers can react to a stale/missing table.
export function loadPriceTable(config) {
  const pt = (config && config.priceTable) || {}
  const cacheFile = pt.cacheFile || '.agent/budget/price-table.cache.json'
  const maxAgeHours = pt.maxAgeHours
  let rates = null
  let fetchedAt = null
  let state = 'missing'
  try {
    const txt = readFileSync(cacheFile, 'utf8')
    const json = JSON.parse(txt)
    // Accept either a raw LiteLLM map { model: {...} } or a wrapped { fetchedAt, rates }.
    if (json && json.rates && typeof json.rates === 'object') {
      rates = json.rates
      fetchedAt = json.fetchedAt || null
    } else {
      rates = json
    }
    if (!fetchedAt) {
      try { fetchedAt = statSync(cacheFile).mtime.toISOString() } catch { /* keep null */ }
    }
    state = computeState(fetchedAt, maxAgeHours)
  } catch {
    rates = null
    state = 'missing'
  }
  return { rates, fetchedAt, maxAgeHours, source: pt.source || 'litellm', state }
}

function computeState(fetchedAt, maxAgeHours) {
  if (!fetchedAt) return 'missing'
  if (!Number.isFinite(maxAgeHours)) return 'fresh'
  const ageHours = (Date.now() - Date.parse(fetchedAt)) / 36e5
  return ageHours > maxAgeHours ? 'stale' : 'fresh'
}

export function tableState(table) {
  return (table && table.state) || 'missing'
}

// rateFor(table, model, tokenType, config) -> USD per token. NEVER returns 0 for an unknown
// rate: missing model/rate (or a missing/stale table) invokes config.priceTable.fallback.
export function rateFor(table, model, tokenType, config) {
  const key = KEY[tokenType]
  if (!key) throw new Error(`price-table: unknown tokenType "${tokenType}"`)
  const fallback = (config && config.priceTable && config.priceTable.fallback) || 'assume-max'

  const entry = table && table.rates && table.rates[model]
  const rate = entry ? entry[key] : undefined

  if (typeof rate === 'number' && rate > 0) return rate
  // A rate of 0 in the table for a priced type is treated as "missing" so we never under-cost.

  // --- fallback policy (FR-019) — never silently $0 ----------------------------------------
  switch (fallback) {
    case 'block':
      throw new Error(
        `price-table: no rate for model "${model}" tokenType "${tokenType}" ` +
        `(table state=${tableState(table)}); PRICE_TABLE_FALLBACK=block ⇒ refusing to proceed.`)
    case 'warn-continue':
    case 'assume-max':
    default:
      // Both non-blocking policies cost the unknown rate conservatively (never $0). `warn-continue`
      // additionally surfaces a warning so the gap is observable.
      if (fallback === 'warn-continue') {
        process.stderr.write(
          `[budget] warn: no price for model "${model}" (${tokenType}); using a conservative ` +
          `estimate (table state=${tableState(table)}).\n`)
      }
      return ASSUME_MAX_PER_TOKEN
  }
}

export const ASSUME_MAX = ASSUME_MAX_PER_TOKEN
