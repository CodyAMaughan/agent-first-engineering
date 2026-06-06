# AGENTS.md template

Fill from the Project Profile. **Command-first, <200 lines, no frontmatter.** Include only what the
agent can't infer from the code. Delete sections that don't apply. (Plain markdown — read natively by
Codex & Cursor; Claude reads it via a `CLAUDE.md` `@AGENTS.md` bridge.)

```markdown
# <Project name>

<One-line purpose.>

## Commands
- Install: `<cmd>`
- Build: `<cmd>`
- Test (all): `<cmd>`
- Test (one): `<cmd>`
- Lint/format: `<cmd>`
- Run/dev: `<cmd>`

## Stack
<languages, frameworks, package manager, datastore — one line each>

## Conventions
- <style/format rule the agent must follow>
- <naming rule>
- <commit/branch etiquette>

## Architecture (only load-bearing, slow-changing facts)
- <entry points / module boundaries the agent can't infer quickly>

## Do not touch
- <files/areas out of scope — enforced by the git-safety hook>

## Gotchas
- <non-obvious thing that has bitten people>
```

## Authoring rules (enforced by the scaffolder)
- Lead with **Commands** — they're the highest-value, hardest-to-infer lines.
- Keep architecture minimal; stale architecture prose raises cost and misleads the agent.
- "Do not touch" items should also be backed by the `git-safety` hook (guidance + enforcement).
- Prefer concrete imperatives ("Use 2-space indent", "Run `pnpm test` before committing") over vague
  guidance ("format properly").
