---
name: project-conventions
description: "This project's code conventions and etiquette. Use when writing or reviewing code here — covers style, commits, branching, and the do-not-touch list."
---

# Project conventions

<!-- The scaffolder fills the {{...}} from the Project Profile (conventions + out_of_scope). -->

- **Style:** {{STYLE}} (run `{{LINT_CMD}}` before committing).
- **Commits:** {{COMMIT_CONVENTION}}.
- **Branches:** {{BRANCH_RULE}} (a git-safety hook enforces the protected branch).
- **Do not touch:** {{OUT_OF_SCOPE}}. Secrets live in `.env` (never read or commit it).
