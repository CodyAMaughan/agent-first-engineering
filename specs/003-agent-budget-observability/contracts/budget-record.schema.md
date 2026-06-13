# Contract: Per-Task Budget Record (the run ledger)

One JSON object per workflow run, appended as a single line to `.agent/budget/runs/<date>.ndjson`
(newline-delimited JSON). Written on **every** run end — completed **or** aborted-on-budget (FR-020,
SC-002). This is the durable data foundation the future P2 analytics layer consumes; **no analytics is
built in this feature**.

## JSON shape

```json
{
  "runId": "qa-loop-2026-06-13T14-50-22",
  "workflowType": "qa-loop",
  "taskId": "harden-budget-guardrail",
  "startedAt": "2026-06-13T14:50:22Z",
  "endedAt": "2026-06-13T14:58:09Z",
  "costBasis": "notional",
  "totalNotionalCostUsd": 4.12,
  "totalTokens": 1830422,
  "status": "aborted-on-budget",
  "breachedThreshold": "perTask.hard",
  "perAgent": [
    {
      "agentId": "main",
      "model": "claude-opus-4-...",
      "inputTokens": 220110,
      "outputTokens": 90233,
      "cacheReadTokens": 1400000,
      "cacheWriteTokens": 120079,
      "notionalCostUsd": 2.71
    },
    {
      "agentId": "subagent:code-reviewer",
      "model": "claude-sonnet-4-...",
      "inputTokens": 40110,
      "outputTokens": 12000,
      "cacheReadTokens": 0,
      "cacheWriteTokens": 0,
      "notionalCostUsd": 1.41
    }
  ]
}
```

## Field contract

| Field | Type | Required | Notes |
|---|---|---|---|
| `runId` | string | yes | unique per run |
| `workflowType` | enum | yes | `feature-pipeline` \| `qa-loop` \| `create-mvp` (FR-020) |
| `taskId` | string | yes | the task the run served |
| `startedAt` / `endedAt` | ISO-8601 | yes | |
| `costBasis` | enum | yes | `notional` \| `billed` — so the figure is never misread (SC-006) |
| `totalNotionalCostUsd` | number | yes | total at API rates |
| `totalTokens` | int | yes | |
| `status` | enum | yes | `completed` \| `aborted-on-budget` |
| `breachedThreshold` | string | when aborted | which ceiling tripped (FR-010) |
| `perAgent` | array | yes | per-agent breakdown; tokens-by-type + notional cost (FR-005) |

## Behavioral contract

- A record is written even when the run was **aborted by the guardrail**, marked
  `status: "aborted-on-budget"` with the spend at abort time (SC-002 acceptance scenario 2).
- On a subscription account, `costBasis` is `notional`; on an API account it MAY be `billed`. Reports
  and the live view label which (FR-004, SC-006).
- The file is append-only NDJSON (greppable, diff-friendly, no DB). `.agent/budget/` cache files are
  gitignored; whether the `runs/` ledger is committed is a repo choice (default gitignored).
