# Contract: `qa-verifier` VERDICT schema (extended)

The structured output the `qa-verifier` subagent returns for each candidate finding, declared as the
`schema` on its `agent()` call in `qa-loop.js`. **Bold fields are new in this feature.** Existing
fields and their semantics are unchanged.

## JSON Schema

```json
{
  "type": "object",
  "properties": {
    "verdict":          { "type": "string", "enum": ["CONFIRMED", "WORKS-AS-INTENDED", "WRONG-THREAT-MODEL", "LOW-SEV-DEFER"] },
    "reproduced":       { "type": "boolean" },
    "evidence":         { "type": "string" },
    "impact":           { "type": "string", "enum": ["data-loss", "security", "correctness", "robustness", "theoretical-edge"] },
    "impactConfidence": { "type": "string", "enum": ["high", "low"] },
    "impactRationale":  { "type": "string" }
  },
  "required": ["verdict", "reproduced", "evidence", "impact", "impactConfidence", "impactRationale"]
}
```

## Semantics & validation

- A `CONFIRMED` verdict MUST have `reproduced === true`, non-empty `evidence` (literal command +
  captured exit/output), and a non-null `impact`. The workflow discards any `CONFIRMED` missing these
  (existing rule, now also requiring `impact`).
- `impact` is judged under the **threat model** (honest-agent mistakes + untrusted content, NOT a
  determined attacker). Reproducible-but-implausible findings ⇒ `impact = theoretical-edge` (FR-B2).
- **Ambiguous impact ⇒ assign the higher class**; name both candidates in `impactRationale` (Edge
  case: conservative classification).
- `impactConfidence = low` on a top-tier class (`data-loss`/`security`) **blocks the auto-fix lane** —
  the finding is routed to the report, not auto-fixed (FR-A3).
- For non-`CONFIRMED` verdicts `impact`/`impactConfidence` MAY be `theoretical-edge`/`low`; they do not
  affect tiering (the finding is already a rejection).

## Verifier role-doc changes (`qa-verifier.md`)

The subagent definition gains a "Classify impact" step after reproduction: pick one `impact` class
under the threat model, state confidence, and record the rationale — with the conservative
"ambiguous → higher class" rule. Tool grants are unchanged (Read, Grep, Glob, Bash; edits nothing
tracked).
