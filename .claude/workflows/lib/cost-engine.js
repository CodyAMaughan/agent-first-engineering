// cost-engine.js — notional cost (FR-002). Pure function of (events, rates): no I/O, no agent
// paths. Cache-read and cache-write are costed at THEIR OWN rates, not the input rate (SC-004).
import { rateFor } from './price-table.js'

// costOf(event, table, config) -> USD. Σ over token types of tokens_type × rateFor(model, type).
export function costOf(event, table, config) {
  const m = event.model
  const r = (type) => rateFor(table, m, type, config)
  return (
    (event.inputTokens || 0) * r('input') +
    (event.outputTokens || 0) * r('output') +
    (event.cacheReadTokens || 0) * r('cacheRead') +
    (event.cacheWriteTokens || 0) * r('cacheWrite')
  )
}

function tokensOf(event) {
  return (
    (event.inputTokens || 0) +
    (event.outputTokens || 0) +
    (event.cacheReadTokens || 0) +
    (event.cacheWriteTokens || 0)
  )
}

// costByAgent(events, table, config) -> map<agentId, {usd, tokens}>
export function costByAgent(events, table, config) {
  const out = {}
  for (const ev of events) {
    const id = ev.agentId || 'unknown'
    if (!out[id]) out[id] = { usd: 0, tokens: 0 }
    out[id].usd += costOf(ev, table, config)
    out[id].tokens += tokensOf(ev)
  }
  return out
}

// totalCost(events, table, config) -> { usd, tokens, costBasis }
// `costBasis` is always labeled so the figure is never misread as billed (FR-004, SC-006).
export function totalCost(events, table, config) {
  let usd = 0
  let tokens = 0
  for (const ev of events) {
    usd += costOf(ev, table, config)
    tokens += tokensOf(ev)
  }
  return { usd, tokens, costBasis: 'notional' }
}
