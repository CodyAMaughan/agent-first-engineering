# Contract: Triage report (Markdown + JSON sidecar)

A default (`mode: report`) run writes **two** files under `qa/reports/`, both stamped with the run date
(threaded via `args.dateStamp`, never `new Date()` inline):

- `qa-<date>.md` — the human-readable ranked triage output (FR-A2).
- `qa-<date>.json` — the machine-readable ranked findings, consumed as input by a later
  `mode: fix --fix <ids>` run.

## JSON sidecar schema (`qa-<date>.json`)

```json
{
  "type": "object",
  "required": ["meta", "findings"],
  "properties": {
    "meta": {
      "type": "object",
      "required": ["date", "mode", "targets", "minSeverity", "rounds", "stop", "counts"],
      "properties": {
        "date":        { "type": "string" },
        "mode":        { "type": "string", "enum": ["report", "fix", "autofix"] },
        "targets":     { "type": "array", "items": { "type": "string" } },
        "minSeverity": { "type": "string", "enum": ["critical", "high", "moderate", "low"] },
        "rounds":      { "type": "number" },
        "stop":        { "type": "string", "enum": ["dry-streak", "max-rounds", "max-fixes", "budget", "wall-clock", "aborted"] },
        "spend":       { "type": ["object", "null"] },
        "counts": {
          "type": "object",
          "properties": {
            "fix": {"type":"number"}, "backlog": {"type":"number"},
            "autoFixed": {"type":"number"}, "rejected": {"type":"number"},
            "unverifiedAtAbort": {"type":"number"}
          }
        }
      }
    },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "target", "line", "class", "claim", "repro", "impact", "impactConfidence", "tier", "recommendation"],
        "properties": {
          "id": {"type":"string"}, "target": {"type":"string"}, "line": {"type":"number"},
          "class": {"type":"string"}, "claim": {"type":"string"}, "repro": {"type":"string"},
          "evidence": {"type":"string"},
          "impact": {"type":"string","enum":["data-loss","security","correctness","robustness","theoretical-edge"]},
          "impactConfidence": {"type":"string","enum":["high","low"]},
          "impactRationale": {"type":"string"},
          "tier": {"type":"string","enum":["fix","backlog","auto-fixed","unverified-at-abort"]},
          "recommendation": {"type":"string"},
          "fixBranch": {"type":["string","null"]}
        }
      }
    }
  }
}
```

`findings` MUST be ordered by impact rank (highest first), then by confidence — i.e. the ranked order
the Markdown renders.

## Markdown layout (`qa-<date>.md`)

Required sections in order (FR-A2):

1. **Summary** — one paragraph: rounds run, `stop` reason, counts, spend, any breached ceiling.
2. **Fix tier** — ranked; each finding shows `id`, impact class, confidence, reproduction,
   recommendation. Empty-state: "No fix-tier findings at/above the `<minSeverity>` bar."
3. **Auto-fixed (top-tier)** — present only if the auto-fix lane acted; lists id, impact, branch,
   regression test path.
4. **Backlog / won't-fix** — each finding with its impact class **and a stated reason** it is below the
   bar (FR-A2, US2-#2).
5. **Rejected** — id + verdict + the one-line reason it is not a bug (so it is never re-investigated).
6. **Unverified-at-abort** — present only if a ceiling tripped mid-verify; lists findings not resolved
   to a tier (Edge case — never silently dropped).

## Invariants

- In `mode: report`, the working tree and git branches are unchanged **except** any top-tier auto-fix
  (which is recorded in section 3 with its branch) — SC-002.
- A ranked output is emitted on **every** terminating path, including a ceiling abort (SC-005) — the
  `.md` and `.json` write atomically at end-of-run.
