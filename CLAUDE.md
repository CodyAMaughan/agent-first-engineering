# Claude Code bridge

This project authors to the open standard. **The source of truth is @AGENTS.md** — read it for
commands, structure, and conventions. This file holds only Claude-specific notes.

## Authoring or editing the curriculum
Use the **`author-curriculum`** skill (`.claude/skills/author-curriculum/`) — it carries the full
Mandatory/Recommended/Optional component checklist, the add/update/audit procedures, and the
easily-missed integration edits (mkdocs nav, quiz.json, adjacent lesson nav). It enforces the rubric
in `meta/PHASE_AUTHORING_GUIDE.md`. The `.claude/skills/` copy is a byte-identical mirror of the
canonical `.agents/skills/` one — keep them in sync.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
`specs/003-agent-budget-observability/plan.md`
<!-- SPECKIT END -->
