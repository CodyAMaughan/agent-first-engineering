# Agent-First Engineering

A free, six-phase curriculum that teaches engineers and data scientists to **drive** coding agents
(Claude Code, Codex, Cursor) — plus a scaffolder skill that turns any repo agent-first. The product
is the docs site in `docs/`; everything else supports it.

Live site: https://codyamaughan.github.io/agent-first-engineering/

## Commands

```sh
pip install -r requirements.txt   # MkDocs Material (use the .venv if present)
mkdocs serve                      # local preview at http://127.0.0.1:8000
mkdocs build --strict             # fail on broken nav / dead links / bad config
sh tests/validate.sh              # assert the agent-first layer is well-formed
```

`check-json` / `check-yaml` pre-commit hooks validate every `quiz.json` and workflow. CI (`.github/workflows/`) is the real gate.

## Structure

| Path | What |
|---|---|
| `docs/curriculum/NN-name/` | The six phases — `index.md` (landing) + `NN-*.md` lessons + `quiz.json` |
| `meta/PHASE_AUTHORING_GUIDE.md` | The authoring **rubric** (Definition of Done for a lesson/phase) |
| `.agents/skills/` | Portable skill library (the open-standard source of truth) |
| `.claude/skills/` | Claude Code mirror of the skills (+ third-party `speckit-*`) |
| `mkdocs.yml` | Site nav — **edit this when you add a lesson/phase**, or it's invisible |
| `tests/validate.sh` | Deterministic check of the agent-first layer |
| `scripts/build-plugin.sh` | Regenerates the **git-ignored** `plugin/` from canonical sources — never hand-edit `plugin/` |
| `.claude-plugin/marketplace.json` | The marketplace catalog (committed; points at the generated `plugin/`) |

The Claude Code **plugin** in `plugin/` is **generated, not hand-maintained**: run `sh scripts/build-plugin.sh`
to (re)build it from the canonical `.agents/skills/` + `.agent/hooks/` + `.claude/agents/`. `plugin/` is
git-ignored; only the generator and `.claude-plugin/marketplace.json` are committed. Editing `plugin/`
by hand reintroduces the drift the generator exists to kill.

## Authoring or editing the curriculum

**Use the `author-curriculum` skill** (`.agents/skills/author-curriculum/SKILL.md`). It carries the
full Mandatory/Recommended/Optional component checklist, the add/update/audit procedures, and the
easily-missed integration edits (mkdocs nav, quiz, adjacent lesson nav). The rubric in
`meta/PHASE_AUTHORING_GUIDE.md` is the source of truth the skill enforces.

Non-negotiables for any lesson: **visual-first** (≥1 rendered Mermaid diagram), inline footnote
citations `[^n]` from **authoritative sources only** (papers + Anthropic/OpenAI/Google/GitHub/Cursor/
Microsoft/standards bodies — never Reddit/HN/X/Medium), a `🧠 Test Yourself` check, an italic summary
under every subsection, and **agent-agnostic** framing (per-agent specifics go in tabs/callouts).

## Conventions
- **Author once to the open standard, adapt at the edges.** Source of truth is `AGENTS.md` +
  `.agents/skills/`; `.claude/` is an adapter/mirror. Keep mirrored `SKILL.md` copies byte-identical.
- Phase landing pages are **`index.md`** (not `README.md`).
- Direct, ELI5-where-it-helps, no hype. Second person. Tight beats complete.
- Never overwrite a file without showing the change. Commit/push only when asked.

## Available skills
- **`author-curriculum`** — add/update/audit a lesson, phase, or doc against the authoring standard.
- **`scaffold-agent-project`** — turn a repo agent-first (the curriculum's capstone artifact).
- **`check-understanding`** — quiz the user on a phase from its `quiz.json`.
- **`feature-lifecycle`** — drive a feature request → review-ready branch through verified, looping
  stages (spec → plan → implement → test-gate → review). Config in `.agent/lifecycle.conf`.

## Subagents (Claude Code: `.claude/agents/`)
- **`lesson-reviewer`** — adversarial, fresh-context review of a lesson/phase against the authoring
  checklist + citation verification (read-only). Use after writing or editing a lesson (Phase 6.2's
  reviewer pattern).
- **`code-reviewer`** — least-privilege (read + inspect) reviewer of a diff for correctness, security,
  and gamed gates; the review gate in the feature pipeline.

Subagent *definitions* are still per-tool (Codex/Cursor use their own custom-agent/mode files) —
unlike `SKILL.md`, there's no shared cross-tool standard yet.

## Workflows (Claude Code: `.claude/workflows/`)
- **`feature-pipeline`** — the orchestrator for `feature-lifecycle`: runs the staged loops, gates each
  on a reviewer subagent or `TEST_CMD`, and stops before the PR for human sign-off.

## Agent guardrails & memory (`.agent/`)
Deterministic hooks (registered in `.claude/settings.json`) run on agent events: `git-safety` +
`secret-scan` (PreToolUse), a `test-gate` on Stop, and the capture-learnings **memory loop**
(`PreCompact` + `SessionStart`). Config in `.agent/guardrails.conf`; details in `.agent/README.md`.
`tests/validate.sh` checks this layer (also in CI).
