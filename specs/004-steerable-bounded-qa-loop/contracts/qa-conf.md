# Contract: `.agent/qa.conf` keys & defaults

`qa.conf` is sourced POSIX `sh`. Every key is `KEY="value"`. With **no** qa.conf present the workflow
MUST adopt these safe defaults (FR-CFG2). `tests/check-qa-manifest.sh` continues to assert every
`QA_TARGETS` entry exists; `tests/check-qa-loop.sh` (new) asserts these defaults resolve.

## Existing keys (retained)

| Key | Default | Meaning |
|---|---|---|
| `QA_TARGETS` | the repo's hooks + test scripts + orchestrator | systems-under-test (space/newline separated) |
| `QA_LENSES` | `boundary threat-evasion race encoding gate-false-verdict dos` | generator lenses |
| `QA_MAX_ROUNDS` | `4` | hard rounds cap |
| `QA_DRY_STREAK` | `2` | convergence streak — **now keyed on at/above-bar findings** |
| `QA_THREAT_MODEL` | (existing prose) | passed to generators + verifier |

## New keys (this feature)

| Key | Default | Meaning | Requirement |
|---|---|---|---|
| `QA_MODE` | `report` | default run mode: `report` \| `fix` \| `autofix` | FR-A1, FR-CFG1 |
| `QA_MIN_SEVERITY` | `moderate` | the fix-tier bar (`critical`\|`high`\|`moderate`\|`low`) | FR-B3, FR-CFG3 |
| `QA_MAX_FIXES` | `5` | max fix-tier findings acted on per run | FR-C2 |
| `QA_BUDGET` | (from `.agent/budget.conf`; unset ⇒ degrade) | token/notional-cost ceiling (003 primitive) | FR-C1 |
| `QA_WALLCLOCK` | unset (optional) | wall-clock minutes ceiling | FR-C3 |
| `QA_AFFECTED_MAP` | unset ⇒ self-test fallback | `target:check[,check]` pairs for the fast fix-gate | FR-D1 |

`QA_TARGETS` doubles as the per-run scope; `args.targets` overrides it for a single run (FR-E1). A
named subset convention (e.g. grouping hooks vs. test scripts) MAY be expressed as additional
`QA_TARGETS_<group>` keys, selected via `args.targets="<group>"`.

## Default-resolution contract

```
resolved.mode         = args.mode        ?? QA_MODE          ?? "report"
resolved.minSeverity  = args.minSeverity ?? QA_MIN_SEVERITY  ?? "moderate"
resolved.maxFixes     = QA_MAX_FIXES                          ?? 5
resolved.maxRounds    = QA_MAX_ROUNDS                         ?? 4
resolved.dryStreak    = QA_DRY_STREAK                         ?? 2
resolved.targets      = args.targets     ?? QA_TARGETS        (full manifest)
resolved.budget       = QA_BUDGET / budget.conf  (003)        ?? degrade(no-op + warn)
```

**Invariant:** absent config never yields unbounded auto-fix — the resolved default is always
report-first with ceilings on.
