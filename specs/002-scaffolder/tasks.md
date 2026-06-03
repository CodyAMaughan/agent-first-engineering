# Tasks: Agent-First Scaffolder (Deliverable B)

**Input**: [plan.md](plan.md) + [spec.md](spec.md). **Format**: `[ID] [P?] [Story] Description`
— `[P]` = parallelizable (different files, no dependency). Paths are under
`.claude/skills/scaffold-agent-project/` unless noted.

> **Status (2026-06-01):** MVP DOGFOODED on a fresh sample project (see `docs/dogfood-report.md`).
> DONE: T001-T023 incl. T009-T010 (starter skill-templates now shipped), 6 hooks (added `format.sh`),
> 3 per-agent adapters, `validate.sh`. Dogfooding **found & fixed a real bug** (git-safety branch
> detection: `git branch --show-current`, not `rev-parse`). `validate.sh` PASS on the generated repo;
> guardrails verified firing across Claude/Codex/Cursor configs. REMAINING: T024-T031 (adopt-mode
> branch, Spec Kit hand-off wiring, re-run manifest, dogfood gate on THIS repo, lockstep map doc).

## Phase 1: Setup
- [ ] T001 Create the skill directory tree (`references/`, `assets/hooks/`, `assets/adapters/`, `assets/skill-templates/`) and `tests/fixtures/`.
- [ ] T002 Write `SKILL.md` frontmatter + skeleton (name `scaffold-agent-project`, description with triggers, modes `init`/`adopt`).

## Phase 2: Foundational (blocking — the data the generator reads)
- [ ] T003 [P] `references/interview-guide.md` — the adaptive question set + **Project Profile** schema (purpose, stack, conventions, risk tier, target agents, team, test/CI).
- [ ] T004 [P] `references/adapter-paths.md` — per-agent output paths/formats (Claude `.claude/`, Codex `.agents/`+`AGENTS.md`, Cursor `.cursor/`+`.agents/skills`) — the registry as data.
- [ ] T005 [P] `references/event-map.md` — canonical→native hook events + fallbacks (from `docs/translation-matrix.md`).
- [ ] T006 [P] `references/agents-md-template.md` — the command-first `AGENTS.md` skeleton (<200 lines, no frontmatter).
**Checkpoint:** the generator has its reference data; user-story work can begin.

## Phase 3: US1 — Interview-driven scaffold (P1, MVP) 🎯
- [ ] T007 [US1] In `SKILL.md`, write the **interview** procedure (adaptive follow-ups, record unresolved items, surface conflicts).
- [ ] T008 [US1] Write the **generation** procedure: Profile → root `AGENTS.md` (from T006) + thin `CLAUDE.md` (`@AGENTS.md`).
- [ ] T009 [P] [US1] `assets/skill-templates/` — 2-3 starter `.agents/skills/*/SKILL.md` (e.g. `run-tests`, `project-conventions`).
- [ ] T010 [US1] Generation step: emit the starter skills into `.agents/skills/` + mirror to `.claude/skills/`.
- [ ] T011 [US1] `tests/validate.sh` — assert `AGENTS.md` <200 lines/no-frontmatter and each `SKILL.md` has `name`+`description`.

## Phase 4: US2 — Agent-agnostic adapters (P1)
- [ ] T012 [P] [US2] `assets/adapters/claude.md` — how to render hooks/skills/context for Claude (`.claude/settings.json`, `.claude/skills/`, `@AGENTS.md`).
- [ ] T013 [P] [US2] `assets/adapters/codex.md` — Codex rendering (`AGENTS.md` native, `.codex/hooks.json`, `.agents/skills/`).
- [ ] T014 [P] [US2] `assets/adapters/cursor.md` — Cursor rendering (`.cursor/hooks.json` w/ `failClosed`, `.cursor/rules`, `.agents/skills/`).
- [ ] T015 [US2] SKILL.md: the adapter step — one shared core, render selected targets; unsupported target → generic `.agents/` fallback + record downgrade.

## Phase 5: US3 — Guardrail layer (P2)
- [ ] T016 [P] [US3] `assets/hooks/secret-scan.sh` (block reading/committing secrets).
- [ ] T017 [P] [US3] `assets/hooks/git-safety.sh` (block dangerous git ops + default-branch edits).
- [ ] T018 [P] [US3] `assets/hooks/test-gate.sh` (Stop-gate: refuse to finish until tests pass).
- [ ] T019 [US3] Risk-tier → hook-set selection logic in SKILL.md; render registrations per agent (canonical events via T005).
- [ ] T020 [US3] `validate.sh`: assert each hook is executable and *fires* against a crafted violation fixture.

## Phase 6: US3b — Capture-learnings memory loop (P2, flagship)
- [ ] T021 [US3b] `assets/hooks/capture-learnings.sh` — deterministic, no LLM: merge session learnings into `.agent/memory/*.md` by semantic path.
- [ ] T022 [US3b] `assets/hooks/load-memory.sh` (or session-start step) — re-inject relevant memory.
- [ ] T023 [US3b] Wire to canonical `pre-compact`→`session-end` fallback per agent; `validate.sh` end-to-end memory fixture.

## Phase 7: US6 — Adopt mode (P2)
- [ ] T024 [US6] SKILL.md `adopt` branch: analyze existing repo (langs/test/CI/existing `CLAUDE.md`/`.cursor/rules`) to shorten the interview.
- [ ] T025 [US6] Migrate/merge pre-existing agent config into `AGENTS.md`; never clobber source without confirmation.
- [ ] T026 [P] [US6] `tests/fixtures/legacy-repo/` with a pre-existing `CLAUDE.md` to verify migration.

## Phase 8: US4 — Spec Kit hand-off (P2)
- [ ] T027 [US4] SKILL.md final step: offer `uvx ... specify init`; complete valid scaffold whether accepted or declined; stay decoupled.

## Phase 9: US5 — Re-run / update (P3)
- [ ] T028 [US5] Generation manifest (per-file checksums/provenance) + re-run logic: update changed, flag stale, preserve manual edits.

## Phase 10: Polish & dogfood gate
- [ ] T029 Run the scaffolder against a fresh fixture for all three agents; confirm shared core + per-agent outputs.
- [ ] T030 Dogfood gate: confirm the scaffolder can (re)generate *this* repo's agent-first layer.
- [ ] T031 Map each generated artifact → curriculum phase (lockstep doc).

**MVP = Phases 1-3 (T001-T011).** Ship that first; T012+ layer on.
