# Contract: `qa-loop.js` workflow `args`

The workflow reads a top-level `args` object (string or object). All fields optional; each falls back
to `qa.conf` / safe defaults (see `qa-conf.md`). Determinism: no `new Date()` inline — the date is
threaded via `dateStamp`.

## `args` shape

```jsonc
{
  "mode":        "report" | "fix" | "autofix",  // default: QA_MODE ?? "report"
  "targets":     ["path", ...] | "<group>",      // per-run scope (FR-E1); default: QA_TARGETS
  "minSeverity": "critical" | "high" | "moderate" | "low", // default: QA_MIN_SEVERITY ?? "moderate"
  "fix":         ["id", ...],                     // mode=fix: the human-approved subset (FR-A3, US3)
  "dateStamp":   "YYYY-MM-DD"                      // report filename stamp (deterministic)
}
```

## Mode behavior contract

| `mode` | Branch? | Code change? | Approval | Output |
|---|---|---|---|---|
| `report` (default) | only if top-tier auto-fix fires | only unambiguous top-tier (data-loss/security, high-conf) | none beyond the narrow lane | ranked `.md` + `.json`, then STOP |
| `fix` | one branch | only the `fix` id subset | the human passed the ids | scoped fixes + end-of-run full `TEST_CMD` + fix report |
| `autofix` (opt-in) | one branch | the whole fix tier | none (explicit opt-in) | full-auto fixes, still honoring ceilings + bar (FR-A4) |

## Invariants

- `mode: report` with default config performs **no** fix except the top-tier auto-fix lane (SC-002).
- `mode: fix` with empty/absent `fix` ⇒ no code change (US3-#3).
- `mode: fix` ids are resolved against the latest `qa-<date>.json`; unknown ids are reported as
  skipped, stale (no-longer-reproducible) ids are reported, not fabricated (Edge cases).
- Every mode honors the ceilings (budget, `QA_MAX_FIXES`, rounds, optional wall-clock) and aborts
  gracefully to a ranked report (FR-C4).

## Return value (workflow result)

```jsonc
{
  "mode": "report",
  "targets": 9,
  "rounds": 3,
  "stop": "dry-streak",            // or max-rounds | max-fixes | budget | wall-clock | aborted
  "counts": { "fix": 2, "backlog": 5, "autoFixed": 0, "rejected": 11, "unverifiedAtAbort": 0 },
  "reportMd": "qa/reports/qa-2026-06-13.md",
  "reportJson": "qa/reports/qa-2026-06-13.json",
  "branch": null,                  // set only when a fix/auto-fix landed
  "next": "Review the report; run mode=fix with the ids you approve."
}
```
