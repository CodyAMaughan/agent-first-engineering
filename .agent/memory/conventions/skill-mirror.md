# Skill mirror parity

`.agents/skills/<name>/` is the canonical open-standard copy; `.claude/skills/<name>/` is a
**byte-identical** mirror that Claude Code loads. They MUST stay identical — enforced by
`tests/check-skill-mirror.sh` (wired into pre-commit AND CI). After editing a skill, re-copy to the
other side (`cp -R`) or the commit/CI fails. Third-party `speckit-*` skills are not mirrored.
