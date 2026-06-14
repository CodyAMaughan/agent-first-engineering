# qa-loop evaluation fixtures

These two tiny scripts are the **oracle** for the lean `qa-loop` — they define "working as intended"
(few, real, grounded findings; abstains on correct code). They are the precision/recall test.

| Fixture | Contains | A correct `qa-loop` run should… |
|---|---|---|
| `planted.sh` | exactly ONE real **critical** bug (path-traversal data-loss: `$name` unsanitized in `rm -f "$base/$name"`) | **find it**, classify it `critical` (or `high`), grounded with `file:line` + a safe sandbox repro (recall + grounding) |
| `clean.sh` | the same helper, **correct** (rejects `..`/`/`/empty) — nothing real to find | **abstain** — emit no invented findings (precision / anti-invention) |

## How to re-run (report mode, hard-capped)

```sh
# finds the planted bug:
#   Workflow qa-loop { mode:'report', targets:['tests/eval-qa-loop/planted.sh'], dateStamp:'<YYYY-MM-DD>' }
# abstains on clean code:
#   Workflow qa-loop { mode:'report', targets:['tests/eval-qa-loop/clean.sh'],   dateStamp:'<YYYY-MM-DD>' }
```

Every run is hard-capped (≤ `QA_MAX_AGENTS`, a token ceiling, 1 round) — it cannot run away.

**Pass criteria:** `planted.sh` → 1 finding, critical/high, grounded; `clean.sh` → 0 findings (abstain).
If it invents on `clean.sh` or misses `planted.sh` after ~2–3 prompt tunings, that's a design signal —
stop and reassess rather than overfitting to these two files.
