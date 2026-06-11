# Interview Guide & Project Profile

The interview is **adaptive**, not a form. Ask one topic at a time, follow up on vague answers, and
in `adopt` mode confirm what you inferred from the repo instead of asking cold. Stop when the Profile
is complete enough to generate. Record unresolved items; surface conflicts.

## Project Profile (the interview's output)

```yaml
purpose:        # one sentence: what this project is
stack:          # languages, frameworks, package manager, db
conventions:    # style/lint/format rules, naming, branch etiquette
commands:       # exact build / test / lint / run commands (the agent can't guess these)
risk_tier:      # low | standard | high   (drives the guardrail set)
target_agents:  # [claude, codex, cursor]   (default all three)
team:           # solo | small | large     (affects shared-vs-personal config)
testing:        # framework + how to run a single test + CI provider
out_of_scope:   # things the agent must NOT touch
unresolved:     # questions the user deferred
```

## Question flow (adapt as needed)

1. **Purpose** — "In one sentence, what is this project?" → `purpose`.
2. **Stack** — language(s), framework(s), package manager, datastore. In `adopt`, infer from
   manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, lockfiles) and **confirm**.
3. **Commands** — "What's the exact command to install / build / test / run one test / lint?" These
   are the highest-value lines in `AGENTS.md` (the agent cannot infer them). Infer from scripts in
   `adopt` and confirm.
4. **Conventions** — style/format tool, naming rules, anything a reviewer repeatedly corrects.
5. **Risk tier** — "How dangerous is a bad agent action here?"
   - `low` — toy/personal, no secrets, no prod.
   - `standard` — real app, has secrets/tests, normal repo. **(default)**
   - `high` — prod systems, money/PII, strict compliance.
6. **Target agents** — which of Claude Code / Codex / Cursor the team uses (default: all three).
7. **Team** — solo vs team → decides what goes in shared (git) vs personal (gitignored) config.
8. **Out of scope** — files/areas the agent must never modify (→ `out_of_scope`, becomes a guardrail).

## Conflict & gap handling
- If answers conflict (e.g. "no external deps" + "uses Postgres"), **state the conflict** and ask.
- If a needed fact is missing and can't be inferred, add it to `unresolved` and note it in the run
  summary rather than guessing.

## Defaults (use when the user says "just pick sensible defaults")
`risk_tier: standard` · `target_agents: [claude, codex, cursor]` · memory loop: on ·
guardrails: git-safety + secret-scan + test-gate · Spec Kit hand-off: offer.
