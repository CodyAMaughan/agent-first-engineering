# Implementation Plan: Steerable, Bounded QA-Loop (Report-First)

**Branch**: `004-steerable-bounded-qa-loop` | **Date**: 2026-06-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/004-steerable-bounded-qa-loop/spec.md`

## Summary

Reshape the existing adversarial QA-loop (`.claude/workflows/qa-loop.js`, `.agent/qa.conf`, the
`quality-loop` skill, and the `qa-adversary`/`qa-verifier` subagents) from
**find-and-auto-fix-everything** into a **steerable, bounded, report-first** tool. The post-mortem
(4h unbounded run, 28 pedantic auto-fixes) maps to four root causes; this plan turns the spec's five
capabilities into a concrete control-flow redesign:

- **Report-first control flow** — the default run does `generate → verify → rank → report → STOP`. It
  creates no branch and changes no code, except a **narrow autonomous lane** that may auto-fix only
  *unambiguous top-tier* (data-loss / security) findings. All other fixing happens in a separate,
  human-approved **scoped fix-run** (`mode: fix` over an approved id subset) on one branch.
- **Impact bar** — the `qa-verifier` VERDICT schema gains an `impact` class + classification
  confidence, evaluated under the spec's threat model. A configurable `QA_MIN_SEVERITY` (default
  **moderate**) gates the fix tier, and **convergence keys on "no new finding at/above the bar."**
- **Bounded execution** — consume spec 003's `budget` Workflow primitive + cost-engine; add
  `QA_MAX_FIXES` and keep a rounds cap. Any ceiling → graceful abort + partial ranked report.
- **Faster fix gate** — per-fix validation runs only the new regression check + directly-affected
  checks; the full integration suite runs once at the end of a fix-run.
- **Steering & visibility** — per-run `--targets`/`QA_TARGETS` scoping and live observability via
  003's P0 (`/workflows`/OTel) so a human can watch and abort mid-flight.

The redesign is an **evolution of existing files**, not a green-field tool. Spec 003 is a hard
dependency for the budget ceiling (FR-C1) and live visibility (FR-E2/E3-watch); those degrade
gracefully if 003 is not yet merged (see Research R7).

## Technical Context

**Language/Version**: JavaScript (ES modules) for `.claude/workflows/qa-loop.js`, executed by the
Claude Code Workflow runner (the host that injects `agent()`, `parallel()`, `phase()`, `log()`, and —
from spec 003 — `budget()`). POSIX `sh` for `.agent/qa.conf` and the deterministic check scripts
(`tests/*.sh`, `.agent/hooks/*.sh`). Markdown for the `quality-loop` SKILL and the two subagent
definitions.

**Primary Dependencies**:
- The Workflow runner API already used by `qa-loop.js` / `feature-pipeline.js`: `agent(prompt, {label,
  phase, schema})`, `parallel([fns])`, `phase(name)`, `log(msg)`, top-level `args`, JSON-schema
  structured outputs.
- **Spec 003 primitives (dependency, not re-specified)**: the `budget` Workflow primitive + cost-engine
  + `.agent/budget.conf` for token/notional-cost accounting and soft-alert/hard-abort; 003's P0 live
  observability (`/workflows`, OTel spans) for watch-and-abort. Lives on branch
  `003-agent-budget-observability` (not yet on `main`).
- `TEST_CMD` from `.agent/lifecycle.conf` remains the **full** oracle, but is now invoked **once at
  end-of-fix-run** instead of per-fix (FR-D2).

**Storage**: Plain files in the working tree. Triage reports under `qa/reports/qa-<date>.md` (Markdown,
human-readable) plus a machine-readable sidecar `qa/reports/qa-<date>.json` (the ranked findings,
consumed by a later `mode: fix --fix <ids>` run). Config in `.agent/qa.conf`. No database.

**Testing**: Deterministic `sh` fixtures invoked by `tests/validate.sh` + a new
`tests/check-qa-loop.sh` (self-test asserting config defaults, report schema, and the post-mortem
replay assertions). `mkdocs build --strict` + `tests/check-skill-mirror.sh` keep the docs/skill-mirror
gates green. CI (`.github/workflows/`) is the real gate; `sh tests/validate.sh` is the local check.

**Target Platform**: Local developer machine running Claude Code (reference implementation), agent-
agnostic at the config/skill layer; the workflow JS is Claude-specific (subagent definitions are
per-tool — see Constitution note).

**Project Type**: Single-repo agent-tooling layer (workflows + skills + hooks + config), not an app
or service. No frontend/backend split.

**Performance Goals**: A typical default run finishes in **minutes, not hours** (SC-001). Per-fix
validation cost drops from "full `mkdocs --strict` + `validate` every iteration" to "one regression
check + affected checks" (FR-D1), with the full suite run once (FR-D2). No fixed throughput target;
the cost ceiling is the hard bound.

**Constraints**:
- The workflow must keep using the existing runner API only (no new host primitives invented here
  beyond consuming 003's `budget`).
- Subagents are read-mostly: `qa-adversary` is read-only; `qa-verifier` runs targets in `mktemp -d`
  and edits nothing tracked. The redesign must not widen those tool grants.
- `qa.conf` is sourced POSIX `sh` — additions must be plain `KEY="value"` with safe defaults, and
  `tests/check-qa-manifest.sh` must still validate every `QA_TARGETS` entry exists.
- Determinism: the workflow must not call `new Date()` inline (current code threads `dateStamp` via
  args); keep that discipline for the report filename.

**Scale/Scope**: ~9 QA targets today (the repo's own hooks + test scripts + orchestrator). 6 lenses.
Rounds cap default 4. The fix tier is expected to be small (single-digit) per run by design.

## Constitution Check

*GATE: evaluated against `.specify/memory/constitution.md` v1.0.0.*

| Principle | Status | Notes |
|---|---|---|
| I. Open Standards First | PASS | Behavior/config lives in `.agent/qa.conf` + the portable `quality-loop` `SKILL.md` (the source of truth); the Claude `.claude/` workflow + subagents are the **adapter**. No proprietary format introduced. |
| II. Agent-Agnostic by Construction | PASS (with noted seam) | The mode/severity/ceiling **semantics** are authored once in `qa.conf` + the SKILL. The *workflow JS* and *subagent definitions* remain Claude-specific, which the project already accepts (AGENTS.md: "Subagent definitions are still per-tool… there's no shared cross-tool standard yet"). No new agnosticism debt added. |
| III. Teach and Generate in Lockstep | PASS | This evolves an existing taught/generated artifact (the quality-loop). The SKILL doc is updated alongside the workflow so the explanation tracks the generation. No curriculum lesson is added by this feature (it edits existing tooling), so no lesson-authoring rubric applies. |
| IV. Guardrails Over Vibes (NON-NEGOTIABLE) | PASS | The ceilings, the report-first default, and the severity bar are **enforced in code** (the round loop + budget primitive + config defaults), not prose. A new `tests/check-qa-loop.sh` fires the post-mortem-replay assertions in a fixture (guardrail must *fire*, not merely exist). |
| V. Minimal Context, Progressive Disclosure | PASS | `qa.conf` stays command-first KEY=value; the SKILL stays short with deep detail in its body. The verifier's `impact` rationale lives in the report, not inflating the prompt. |
| VI. Adopt, Don't Reinvent | PASS | Reuses spec 003's budget/observability rather than re-implementing cost accounting; reuses `TEST_CMD` and the existing runner API. No new dependency added. |
| VII. Specs Are the Source of Truth | PASS | This plan derives strictly from the clarified `spec.md`; behavior changes are spec-first. |

**Initial gate: PASS** (no violations → Complexity Tracking left empty).

**Post-design re-check (after Phase 1): PASS.** The data model, contracts, and quickstart introduce no
new agent-specific hardcoding beyond the already-accepted per-tool subagent/workflow seam, add no
copyleft/heavy dependency, and keep every new rule encoded as config-default-or-code rather than prose.

## Project Structure

### Documentation (this feature)

```text
specs/004-steerable-bounded-qa-loop/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 — decisions (control flow, impact schema, affected-check selection, 003 dependency)
├── data-model.md        # Phase 1 — Finding, Verdict(+impact), Triage report, Run ceilings, Run config, modes
├── quickstart.md        # Phase 1 — how to run report-first, approve a subset, scoped fix-run, ceiling demo
├── contracts/
│   ├── qa-conf.md       # .agent/qa.conf keys + defaults (mode, QA_MIN_SEVERITY, QA_MAX_FIXES, rounds, budget, scope)
│   ├── verdict-schema.md # qa-verifier VERDICT JSON contract (+ impact, confidence)
│   ├── report-schema.md  # triage report Markdown layout + JSON sidecar schema
│   └── workflow-args.md  # qa-loop.js args contract (mode, fix ids, targets, severity, dateStamp)
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
.claude/workflows/
└── qa-loop.js               # REWORKED: report-first control flow, modes, impact ranking,
                             #   budget()/ceilings, fast fix-gate, scoped fix-run

.claude/agents/
├── qa-adversary.md          # (light edit) generators tag a proposed impact + threat-model note
└── qa-verifier.md           # REWORKED: emit impact class + classification confidence in VERDICT

.agent/
├── qa.conf                  # EXTENDED: QA_MODE, QA_MIN_SEVERITY, QA_MAX_FIXES, QA_MAX_ROUNDS,
│                            #   QA_BUDGET (→003), QA_WALLCLOCK (optional), QA_TARGETS scope
├── budget.conf              # CONSUMED from spec 003 (not authored here)
└── lifecycle.conf           # unchanged; still the source of TEST_CMD (the full oracle)

.agents/skills/quality-loop/SKILL.md   # source-of-truth skill doc — updated to report-first
.claude/skills/quality-loop/SKILL.md   # byte-identical mirror (keep in sync)

qa/reports/
├── qa-<date>.md             # human-readable ranked triage report (output)
└── qa-<date>.json           # machine-readable ranked findings (output; input to scoped fix-run)

tests/
├── check-qa-loop.sh         # NEW: self-test — config defaults, report schema, post-mortem replay asserts
├── check-qa-manifest.sh     # unchanged contract: every QA_TARGETS entry must exist
└── validate.sh              # wires in check-qa-loop.sh
```

**Structure Decision**: Single-repo agent-tooling layer. No `src/`/`tests/` app split — the "code"
is the workflow JS + POSIX config + skill markdown + deterministic `sh` checks that already constitute
this repo's agent-first layer. The redesign edits those files in place and adds exactly one new check
script (`tests/check-qa-loop.sh`) plus the report JSON sidecar.

## Complexity Tracking

> No constitution violations — section intentionally empty.
