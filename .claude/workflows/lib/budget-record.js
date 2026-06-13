// budget-record.js — the per-task durable ledger writer (the P2 data foundation). Writes one
// validated NDJSON line per run end (completed OR aborted-on-budget) to
// `.agent/budget/runs/<date>.ndjson` (FR-020, SC-002). Append-only, greppable, no DB.
//
// Contract: contracts/budget-record.schema.md. NO analytics is built here — data capture only.
import { mkdirSync, appendFileSync } from 'node:fs'
import { join } from 'node:path'

const REQUIRED = [
  'runId', 'workflowType', 'taskId', 'startedAt', 'endedAt',
  'costBasis', 'totalNotionalCostUsd', 'totalTokens', 'status', 'perAgent',
]
const STATUSES = ['completed', 'aborted-on-budget']
const COST_BASES = ['notional', 'billed']

function dateStampOf(record) {
  // Derive YYYY-MM-DD from endedAt (ISO-8601) for the ledger filename; fall back to startedAt.
  const iso = record.endedAt || record.startedAt || ''
  const m = /^(\d{4}-\d{2}-\d{2})/.exec(iso)
  return m ? m[1] : 'undated'
}

// writeBudgetRecord(record, dir) -> path written. Validates the record fail-closed, appends one
// NDJSON line, and returns the file path. `dir` defaults to .agent/budget/runs.
export function writeBudgetRecord(record, dir = '.agent/budget/runs') {
  if (!record || typeof record !== 'object') throw new Error('budget-record: record must be an object')
  for (const k of REQUIRED) {
    if (!(k in record) || record[k] === undefined || record[k] === null) {
      throw new Error(`budget-record: missing required field "${k}" (invalid record)`)
    }
  }
  if (!STATUSES.includes(record.status)) {
    throw new Error(`budget-record: status must be one of ${STATUSES.join(' | ')}, got "${record.status}"`)
  }
  if (!COST_BASES.includes(record.costBasis)) {
    throw new Error(`budget-record: costBasis must be one of ${COST_BASES.join(' | ')}, got "${record.costBasis}"`)
  }
  if (record.status === 'aborted-on-budget' && !record.breachedThreshold) {
    throw new Error('budget-record: an aborted-on-budget record must name breachedThreshold')
  }
  if (!Array.isArray(record.perAgent)) {
    throw new Error('budget-record: perAgent must be an array')
  }

  mkdirSync(dir, { recursive: true })
  const path = join(dir, `${dateStampOf(record)}.ndjson`)
  appendFileSync(path, JSON.stringify(record) + '\n')
  return path
}
