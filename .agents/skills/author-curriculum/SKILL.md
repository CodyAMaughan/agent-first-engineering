---
name: author-curriculum
version: 1.0.0
description: Add or update a curriculum lesson, phase, or doc so it meets the project's authoring standard — the full Mandatory/Recommended/Optional component checklist, a gap-audit pass, and the easily-missed integration edits (mkdocs nav, quiz.json, adjacent nav). Trigger with "add a lesson", "update the curriculum", "write a new phase", "audit a lesson for gaps", or "/author-curriculum".
---

# Author Curriculum

Add or update curriculum content (a lesson, a phase, or supporting docs) so it ships **complete** —
visual-first, heavily cited, agent-agnostic, and wired into nav/quiz — on the first pass.

## Operating principle

> **The rubric is the source of truth; this skill is the procedure that enforces it.**
> `meta/PHASE_AUTHORING_GUIDE.md` defines the Definition of Done. This skill turns it into a
> repeatable workflow + a categorized component checklist + a gap audit, so nothing is forgotten.
> When the standard evolves, update **both** this skill and the guide (see [Living document](#living-document)).

**Read first, every run:** `meta/PHASE_AUTHORING_GUIDE.md` (the rubric) and one reference lesson —
`docs/curriculum/02-context-engineering/` is the tone/density gold standard; Phase 1 lessons are the
cleanest structural template.

> Phase landing pages are **`index.md`** (not `README.md`).

## Modes

| Mode | Trigger | What it does |
|---|---|---|
| **add-lesson** | "add a lesson on X to phase N" | New `NN-*.md`, wire nav + quiz + index |
| **update-lesson** | "update / expand lesson X" | Edit in place, re-grade against the checklist |
| **add-phase** | "add a new phase" | New `docs/curriculum/NN-name/` with index + lessons + quiz |
| **gap-audit** | "audit lesson/phase X for gaps" | Grade against the checklist, report misses by severity — no edits unless asked |

---

## The component checklist

Grade every lesson/phase against this. **Mandatory** = a defect if missing (the critic fails it).
**Recommended** = include unless there's a reason not to. **Optional** = use when it earns its place.

### Lesson file (`NN-title.md`)

| Component | Tier | Notes |
|---|---|---|
| Filename `NN-title.md` (zero-padded, kebab-case) | **Mandatory** | Matches sibling numbering |
| H1 `# Lesson N.M — Title` | **Mandatory** | |
| Motto blockquote `> _one-line idea that sticks_` | **Mandatory** | |
| `_TL;DR (1–2 lines)_` italic | **Mandatory** | Cite if it asserts behavior `[^n]` |
| Italic 1–2 line summary under **every** `##`/`###` | **Mandatory** | "Subsection summaries" rule |
| ≥1 rendered ` ```mermaid ` diagram | **Mandatory** | flowchart/sequence/decision/state — must render on the site |
| ≥1 `> 🧠 **Test Yourself:**` + `<details>` answer | **Mandatory** | Formative check between major sections |
| Inline footnote citations `[^n]` on every behavior/stat/best-practice claim | **Mandatory** | Defined at bottom; **no orphans, no gaps, no `## Sources` heading** |
| Authoritative sources only | **Mandatory** | See [Citation standard](#research--citation-standard) |
| Agent-agnostic framing (universal idea first) | **Mandatory** | "Claude-only" is a defect; per-agent specifics go in tabs/callout |
| Nav footer `← [prev](…) · next → [next](…)` | **Mandatory** | |
| `## Your turn (exercise)` — one concrete exercise | **Mandatory** | |
| `## ELI5` section | **Recommended** | Effectively required for the dense phases 4–6 |
| Worked example with ✅/❌ contrast | **Recommended** | Show the failure and the fix |
| Comparison/decision **tables** | **Recommended** | Comparisons → tables, decisions → decision tables |
| `pymdownx.tabbed` per-agent blocks (Claude Code / Codex / Cursor) | **Recommended** | When steps genuinely differ by agent |
| ASCII flow sketch | **Optional** | When a quick before/after beats a Mermaid render |
| `admonition` / `> [!NOTE]` / `details` callouts, "Rule of thumb" asides | **Optional** | For asides that would break the main thread |
| Extra diagrams (sequence, state, subgraphs) | **Optional** | Add when one diagram can't carry the idea |

### Phase landing page (`index.md`)

| Component | Tier |
|---|---|
| H1 phase title + one-line framing blockquote | **Mandatory** |
| **Executive summary** (3–5 sentences: what it makes you able to do + why) | **Mandatory** |
| Learning-objectives list | **Mandatory** |
| Lesson-map table (one row per lesson, "the one idea") | **Mandatory** |
| Phase diagram (` ```mermaid `) | **Mandatory** |
| Cheatsheet: key-terms table ("what people say \| what it actually means") + agent-translation table | **Mandatory** |
| Quiz link `→ **[Check your understanding](quiz.json)**` | **Mandatory** |
| Nav footer (curriculum home + next phase) | **Mandatory** |
| Footnotes (authoritative, 4–8 per phase, reused across lessons) | **Mandatory** |
| Prerequisite line | **Recommended** |
| "The big idea (in one sentence)" | **Recommended** |
| Phase exercise ("do this for real") | **Recommended** |
| Difficulty stars (★) in nav | **Optional** |

### `quiz.json`

| Component | Tier |
|---|---|
| Schema-valid JSON (no trailing commas/comments) — `check-json` pre-commit enforces it | **Mandatory** |
| 9–15 questions (≈2–3 per lesson), spread **≥3 easy / ≥3 medium / ≥3 hard** | **Mandatory** |
| Every question has a `lesson` field grounding it in a lesson | **Mandatory** |
| `answer` = 0-based index; 3–4 options; normalized option length | **Mandatory** |
| Hard questions use plausible distractors (true-but-irrelevant statements) | **Mandatory** |
| `explanation` says why right is right and distractors are wrong | **Mandatory** |
| `citations` (authoritative URL) | **Recommended** |

### Integration / cross-cutting — the easily-missed edits

> These are where "the lesson looks done" but the site is broken or the quiz is stale. Check **all**.

| Edit | Tier | When |
|---|---|---|
| `mkdocs.yml` nav entry for the new lesson/phase | **Mandatory** | Any new file — it's invisible on the site otherwise |
| Phase `index.md` lesson-map row **+** phase-diagram node | **Mandatory** | New lesson |
| Adjacent lessons' `← prev · next →` footers updated | **Mandatory** | Inserting between existing lessons |
| `quiz.json` gains ≥1 question for the new lesson (keep the ≥3/≥3/≥3 spread) | **Mandatory** | New lesson |
| Final lesson of a phase maps to its scaffolder artifact (lockstep) | **Mandatory** | New/changed final lesson |
| Renumber subsequent lessons + their nav, mkdocs entries, and quiz `lesson` fields | **Mandatory** | Inserting mid-phase |
| `meta/curriculum-outline.md` updated | **Recommended** | Structure changed |
| Cross-links from related lessons in other phases | **Recommended** | New concept that earlier/later lessons should point to |

---

## Procedures

### add-lesson
1. **Place it.** Pick phase + number `N.M`; decide whether it's appended or inserted (insert ⇒ renumber + fix all nav/mkdocs/quiz `lesson` fields).
2. **Research.** Gather authoritative sources *before* drafting (see standard below). One claim → one citation.
3. **Draft visual-first.** Lead each idea with a diagram/table; prose only for the one thing a visual can't carry. Follow the lesson skeleton in the guide. Keep it ~one screen.
4. **Wire it in** (the integration table): `mkdocs.yml`, phase `index.md` (lesson map + diagram node), adjacent nav footers, `quiz.json` (≥1 new question, keep the spread).
5. **Self-critique** (grade against the checklist; fix every Mandatory miss).
6. **Validate** (build + scripts below).

### update-lesson
1. Read the current lesson **and** the checklist. 2. Make the edit. 3. Re-grade the whole file (an edit can orphan a footnote, break a `<details>`, or drift a subsection summary). 4. If you added a claim, add its citation. 5. Validate.

### add-phase
Create `docs/curriculum/NN-name/` with `index.md` + lessons + `quiz.json`; add the whole `nav:` subtree to `mkdocs.yml`; link it from `docs/curriculum/index.md` and the prior phase's "next phase →"; map the final lesson to a scaffolder artifact. Then grade every file.

### gap-audit
Grade the target against all four checklist sections. Report as: `Mandatory misses` (must fix) · `Recommended gaps` (should fix) · `Optional ideas` (could add). Cite the exact rule for each. **Make no edits unless the user asks** — the audit is read-only by default.

---

## Research & citation standard
- **Authoritative only:** peer-reviewed papers (arXiv/ACL/NeurIPS) and docs/blogs from **Anthropic, OpenAI, Google/DeepMind, GitHub, Cursor, Meta AI, Microsoft**, or standards bodies (agents.md, agentskills.io, modelcontextprotocol.io), humanlayer 12-factor-agents. **Never** Reddit, HN, X/Twitter, random Medium/forum/content-farm posts.
- **One claim, one citation.** Every assertion about agent/tool behavior, a stat, or a "best practice" carries a `[^n]`. Prefer **primary** sources; when evidence is mixed, say so and cite both sides (honest > tidy).
- **Verify URLs resolve** and the source actually says what you cite. Note publication dates when a claim is version-sensitive (tools change fast).
- Footnote markers render as back-linked superscripts; define each once at file bottom. **No `## Sources` heading.**

## Self-critique (run before declaring done)
Re-read as the critic and answer yes to all: Mandatory components all present? ≥1 Mermaid renders? Every claim cited, no orphan/gap footnotes? Agent-agnostic? Nav/mkdocs/quiz wired? Tight (no filler)? Fix every "no" before finishing.

## Validate
```sh
# JSON sanity for quizzes (pre-commit also runs this)
python -c "import json,sys; json.load(open(sys.argv[1]))" docs/curriculum/<dir>/quiz.json
# Build the site to catch broken nav / unrendered Mermaid / dead links
mkdocs build --strict
# Agent-first layer well-formed (AGENTS.md, .agents/skills core)
sh tests/validate.sh
```

## Living document
This skill and `meta/PHASE_AUTHORING_GUIDE.md` are a pair: the guide is the *rubric*, this is the
*procedure*. When a convention changes (a new Mandatory component, a tooling shift, a corrected path),
update **both** in the same commit, and bump this skill's `version`. If you discover a recurring gap
during a gap-audit, add it to the checklist — that's how this stays a living standard.

## Portability
Follows the Agent Skills (`SKILL.md`) standard. Canonical copy lives in `.agents/skills/author-curriculum/`
(the portable core that `tests/validate.sh` checks); mirrored byte-identical to
`.claude/skills/author-curriculum/` so Claude Code loads it. Keep the two copies in sync.
