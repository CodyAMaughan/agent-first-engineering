# Docs build & quizzes

- The gate is `mkdocs build --strict` (fails on broken links/footnotes/nav). Phase landing pages are
  `index.md` (not `README.md` — the authoring guide was corrected to match).
- `docs/curriculum/<phase>/quiz.json` is the **single source of truth** for a phase quiz, read by BOTH
  the `check-understanding` skill and the web quiz widget (`docs/assets/js/quiz.js`, which fetches
  `../quiz.json`). Never duplicate quiz content.
- To add or edit a lesson, use the `author-curriculum` skill (the Mandatory/Recommended/Optional
  checklist + the nav/quiz/index wiring it enforces).
