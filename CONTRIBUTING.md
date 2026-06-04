# Contributing to Agent-First Engineering

Thanks for your interest! This project is a **curriculum** (teaching agent-first engineering) plus a
**scaffolder** (a `SKILL.md`-first tool that sets up agent-ready repos). Contributions of every size
are welcome — fixing a typo, sharpening a lesson, adding a diagram, proposing a new topic, or
improving the tool.

## Ways to contribute

- **Fix or improve a lesson** — clarity, diagrams, ELI5, better or more current sources.
- **Propose a new lesson or topic** — see the [Roadmap](docs/roadmap.md) for the Advanced tier, then
  open an issue describing the topic and an authoritative source or two.
- **Improve the scaffolder** — the tool lives in `.claude/skills/scaffold-agent-project/`.
- **Strengthen sources** — if a citation is weak or outdated, suggest an authoritative replacement.

## Ground rules

- **Markdown is the source of truth.** Lessons live in `docs/curriculum/<NN-phase>/`; the site is
  built from them with MkDocs Material.
- **Follow the authoring rubric:** [`meta/PHASE_AUTHORING_GUIDE.md`](meta/PHASE_AUTHORING_GUIDE.md) —
  visual-first (at least one diagram per lesson), an executive summary, per-subsection summaries,
  inline footnote citations, a Test-Yourself checkpoint, and a `quiz.json`.
- **Cite authoritative sources only** — papers (arXiv/ACL/NeurIPS) and docs/blogs from the AI labs and
  standards bodies (Anthropic, OpenAI, Google, Cursor, GitHub, Microsoft, agents.md, agentskills.io,
  modelcontextprotocol.io). **No Reddit, forum, or low-quality sources.**
- **Keep it agent-agnostic** — Claude Code is the reference implementation, not the requirement.

## Run the site locally

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/mkdocs serve   # http://127.0.0.1:8000
```

## Pull requests

1. Fork the repo and create a branch (`feat/...`, `fix/...`, or `docs/...`).
2. Make your change. If you touched a lesson, run `mkdocs build` to confirm it builds with no broken
   links or footnotes.
3. Use clear [Conventional Commit](https://www.conventionalcommits.org/) messages.
4. Open a PR describing what changed and why, and link any related issue.

## Code of Conduct

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
