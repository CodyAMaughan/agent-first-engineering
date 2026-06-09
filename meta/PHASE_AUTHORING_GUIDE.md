# Phase Authoring Guide (the rubric)

Every curriculum phase MUST follow this. The gold standard is `ai-engineering-from-scratch`'s
lesson structure (motto → problem → concept-with-visuals → deep dive → key-terms cheatsheet →
further reading), **with one upgrade: visuals first.** Prefer a diagram, table, or ASCII flow over
any paragraph that can be shown instead of told.

## Non-negotiables (the Definition of Done — the critic grades against this)

1. **Visual-first — with ≥1 rendered Mermaid diagram per lesson.** Every lesson MUST include at least
   one ` ```mermaid ` diagram (flowchart / sequence / decision-tree / state) that renders on the site —
   convert a suitable ASCII flow to Mermaid, or add a new one. Plus: comparisons → tables, decisions →
   decision tables, per-agent snippets → `pymdownx.tabbed` blocks, asides → `admonition`/`details`
   callouts. Prose is for the *one idea* a visual can't carry. Keep lessons ~one screen. **Phases 4–6
   are the densest and need the most diagrams + ELI5.**
2. **Concise.** Lead with the point. Cut filler, throat-clearing, and restatement. Tight > complete.
3. **Phase executive summary.** The phase `index.md` opens with a 3–5 sentence **Executive
   Summary** (what this phase makes you able to do + why it matters) and a learning-objectives list.
4. **Subsection summaries.** Every lesson, and every `##`/`###` subsection inside it, starts with a
   **1–2 line summary in _italics_** before the details.
5. **Inline citations as Markdown footnotes.** Claims about agent/tool behavior, stats, and
   "best practice" assertions carry an inline footnote marker `[^n]` (renders as a clickable
   superscript that jumps to the definition and back). Define each at the bottom of the file:
   `[^n]: [Title](url) — Publisher`. **Do NOT use a `## Sources` heading** — footnote definitions
   auto-render as a back-linked list at the page bottom. Number `[^1]`,`[^2]`… sequentially per page;
   **every marker used MUST have exactly one definition (no orphans, no gaps).** Example:
   `… degrades as context fills [^1].`
6. **Authoritative sources only.** Papers (arXiv/ACL/NeurIPS) and blogs/docs from authoritative
   orgs: **Anthropic, OpenAI, Google/DeepMind, GitHub, Cursor, Meta AI, Microsoft, the standards
   bodies (agents.md, agentskills.io, modelcontextprotocol.io), Linux/Agentic AI Foundation.**
   **NEVER cite Reddit, Hacker News, X/Twitter, random Medium/forum posts, or content farms.**
   4–8 sources per phase, reused across lessons via per-file footnote definitions.
7. **Test-Your-Knowledge checkpoints.** Between major sections of a lesson, insert a quick
   `> 🧠 **Test Yourself:**` checkpoint — 1 question with the answer in a `<details>` reveal.
   These are *formative* (quick gut-checks), distinct from the graded `quiz.json`.
8. **Per-phase cheatsheet.** Near the bottom of the phase `index.md`, a **Cheatsheet** section:
   key concepts, definitions, and tools as compact tables (mirror the gold standard's
   "Key Terms | what people say | what it actually means" table, plus a commands/tools table).
9. **`quiz.json`** present and schema-valid (see below), with a difficulty spread.
10. **Agent-agnostic.** Universal idea first; per-agent specifics (Claude Code / Codex / Cursor) in
    a callout or table. "Works only in Claude" is a defect.
11. **Nav + lockstep.** Keep the `← prev · next →` footers. The final lesson maps the phase to the
    scaffolder artifact it teaches (lockstep).

## Required file structure (per phase)

```
docs/curriculum/NN-name/
├── index.md           # exec summary, objectives, lesson map, phase diagram, cheatsheet, sources
├── 01-*.md … 0N-*.md  # lessons (keep existing filenames/nav)
└── quiz.json          # graded quiz (REPLACES quiz.md — delete quiz.md if present)
```

## Lesson file skeleton

```markdown
# Lesson N.M — Title

> _One-line motto — the idea that sticks._

_TL;DR (1–2 lines): what this lesson gives you._

## <Subsection>
_1–2 line italic summary of this subsection._

<visual-first content: a ```mermaid diagram + tables; tight prose with inline [^n] citations>

> 🧠 **Test Yourself:** <question>
> <details><summary>Answer</summary><the answer + one-line why></details>

## Your turn (exercise)
<one concrete exercise>

---
← [prev](…) · next → [next](…)

[^1]: [Title](https://…) — Anthropic
[^2]: [Title](https://…) — arXiv
<!-- footnote definitions render as a back-linked list at the page bottom; NO "## Sources" heading -->`
```

## `quiz.json` schema

```json
{
  "phase": "02-context-engineering",
  "title": "Context Engineering",
  "questions": [
    {
      "id": "ctx-01",
      "difficulty": "easy",
      "type": "conceptual",
      "lesson": "02-context-rot.md",
      "question": "…concise, one or two sentences…",
      "options": ["A …", "B …", "C …", "D …"],
      "answer": 1,
      "explanation": "why the right answer is right and the distractors are wrong",
      "citations": ["https://… (optional, authoritative)"]
    }
  ]
}
```

Rules for `quiz.json`:
- **9–15 questions (≈2–3 per lesson)**, with a spread: **≥3 easy, ≥3 medium, ≥3 hard**. Mix `conceptual` and `practical`.
- `answer` is the 0-based index of the correct option. 3–4 options each.
- **Hard questions must be hard:** plausible distractors, several being *true statements that don't
  answer the question*. **Normalize option length** so the answer isn't inferable from phrasing.
- Every question grounded in a lesson (`lesson` field), not general trivia.
- Valid JSON (no trailing commas, no comments).

## Starter authoritative sources (verify URLs live; add more per phase)

- Anthropic — Claude Code best practices, "Effective context engineering for AI agents", docs (code.claude.com/docs)
- OpenAI — Codex guides, "harness engineering" / "Building an AI-Native Engineering Team" (developers.openai.com/codex)
- Cursor — docs & "Best practices for coding with agents" (cursor.com/docs, cursor.com/blog)
- Standards — agents.md, agentskills.io, modelcontextprotocol.io
- GitHub — Spec Kit (github.com/github/spec-kit), Copilot docs
- humanlayer — 12-factor-agents (github.com/humanlayer/12-factor-agents)
- arXiv — context/compaction/memory & agent-reliability papers (cite specific ones you use)

## Voice
Direct, ELI5 where it helps, no hype. Second person. Match `docs/curriculum/02-context-engineering/` for tone
and density (it is the reference) — but push even harder toward visuals and brevity.
