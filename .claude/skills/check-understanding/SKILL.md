---
name: check-understanding
version: 2.0.0
description: Test-your-knowledge quiz for the Agent-First Engineering curriculum, driven by each phase's quiz.json. Trigger with "test my knowledge", "quiz me", "check my understanding", "test phase 3", or `/check-understanding <phase>`.
---

# Check Understanding (Test Your Knowledge)

Quiz the user on a curriculum phase using its `quiz.json` question bank, with selectable difficulty.

## Activation
Triggers: `/check-understanding <phase>`, "test my knowledge on context engineering", "quiz me on
phase 3", "am I ready for the next phase".

## Input
A phase number (1-6) or name/keyword. If none given, list the six phases and ask.

## Phase Map
| Input | Directory | Phase |
|---|---|---|
| 1, fundamentals, loop | `docs/curriculum/01-fundamentals` | Fundamentals |
| 2, context, ctx | `docs/curriculum/02-context-engineering` | Context Engineering |
| 3, verification, tdd, testing | `docs/curriculum/03-verification-and-tdd` | Verification & TDD |
| 4, session, memory | `docs/curriculum/04-session-and-memory` | Session & Memory Discipline |
| 5, spec, spec-driven | `docs/curriculum/05-spec-driven-development` | Spec-Driven Development |
| 6, orchestration, harness | `docs/curriculum/06-orchestration-and-harness` | Orchestration & Harness Engineering |

## Procedure

### 1. Resolve phase
Map the argument to a directory (validate 1-6; on miss, list all six and ask).

### 2. Load the question bank
Read `docs/curriculum/<dir>/quiz.json`. It has `{ phase, title, questions: [{ id, difficulty, type,
lesson, question, options, answer, explanation, citations }] }` where `answer` is the 0-based index of
the correct option.
- If `quiz.json` is missing or invalid, FALL BACK: Glob `docs/curriculum/<dir>/*.md` (excluding
  `index.md`), read the lessons, and generate questions on the fly (still follow the difficulty/scoring
  flow below).

### 3. Pick difficulty & length
Ask the user (AskUserQuestion): **Easy**, **Medium**, **Hard**, or **Mixed (recommended)**, and how
many questions (default 6). Filter `questions` by the chosen difficulty (Mixed = sample across all
three, weighted toward medium). Shuffle and take N. Track which `id`s were used so retakes don't repeat
until the pool is exhausted.

### 4. Administer one at a time
For each question, present via AskUserQuestion. Shuffle option order. Show difficulty + lesson tag:
```
Question 2/6 · Hard · from Lesson: 02-context-rot.md
<question>
A) …  B) …  C) …  D) …
```
Do NOT reveal the answer until the user responds.

### 5. Score
Tally correct/total and a per-difficulty breakdown (e.g. Easy 2/2 · Medium 2/3 · Hard 1/2). For each
miss, record the user's choice, the correct option, the `explanation`, and the `lesson`.

### 6. Results & grade
- **≥90%** — Mastered. If phase 6: "You've completed the curriculum — you think like a systems
  engineer for agents." Else: "Strong grasp of <phase>. Ready for the next phase."
- **70-89%** — Almost. List the lessons behind the misses to review.
- **50-69%** — Developing. List each missed topic + lesson.
- **<50%** — Start over. Recommend re-reading the phase, hardest-missed lessons first.

### 7. Wrong-answer breakdown
For each miss:
```
Q<n> (<difficulty>): <abbreviated question>
Your answer: <X>  ·  Correct: <Y> — <correct option text>
Why: <explanation from quiz.json>
Review: docs/curriculum/<dir>/<lesson>
```

### 8. What next?
Offer: (1) retake (fresh questions / harder difficulty), (2) another phase, (3) explain a missed topic.

## Rules
- `answer` in quiz.json is a 0-based index — map carefully after shuffling options.
- Never reveal the answer before the user responds.
- Respect the difficulty filter; "Mixed" should genuinely span easy→hard.
- Ground every question in the bank (or, in fallback mode, the lessons) — no outside trivia.

## Portability
Follows the Agent Skills (`SKILL.md`) standard. Lives in `.claude/skills/` for Claude Code; mirror to
`.agents/skills/check-understanding/` for Codex and Cursor (the scaffolder automates this mirroring).
