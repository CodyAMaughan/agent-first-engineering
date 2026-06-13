# Spec: `tests/check-footnotes.sh` — Markdown footnote integrity check

## Goal

Replace a check done manually many times with a deterministic test script that verifies
Markdown footnote integrity across every curriculum doc, and wire it into both the
agent-first layer check (`tests/validate.sh`) and CI (`.github/workflows/ci.yml`). The
script must catch real footnote imbalances (a key authoring non-negotiable is inline
`[^n]` citations) and must demonstrably fail on bad input, not trivially always-pass.

## Scope

### In
- New file `tests/check-footnotes.sh`: POSIX `sh`, style-matched to
  `tests/check-skill-mirror.sh` (header comment block; per-file `ok`/`FAIL` lines;
  trailing `PASS`/`FAIL` summary; `exit "$fail"`). No external deps beyond `awk`/`grep`
  (plus shell builtins / `find`, `mktemp`, `sort` as `check-skill-mirror.sh` already uses).
- Footnote parsing over `docs/curriculum/**/*.md` with three imbalance classes per file:
  GAPS, ORPHANS, DUPLICATE definitions.
- Fenced-code-block (` ``` `) exclusion so code samples don't trip the parser.
- A built-in self-test proving the negative case (fails on unbalanced fixture input).
- Wiring: a step in `tests/validate.sh` and a step in `.github/workflows/ci.yml`.

### Out
- Validating footnote *content* (whether a citation is authoritative / URL is live) —
  that is the lesson-reviewer's job, not this script.
- Files outside `docs/curriculum/` (e.g. `docs/index.md`, `README.md`).
- Indented (4-space) code blocks and inline-code spans — only triple-backtick fences are
  excluded (matches how the curriculum writes code samples). Out of scope to handle `~~~`
  fences unless they later appear in curriculum docs.
- Reformatting or fixing footnotes; the script only reports.

## Contracts / interfaces

**Invocation.** `sh tests/check-footnotes.sh` from the repo root. No arguments. No env
vars. Operates on the fixed glob `docs/curriculum/**/*.md` (every `*.md` under
`docs/curriculum/`, recursively).

**Footnote grammar (per the feature definition).**
- A footnote token is `[^id]` where `id` matches `[^]]+` (any run of non-`]` characters).
- DEFINITION: `[^id]:` appearing at the **start of a line** (leading whitespace allowed
  before `[`). The `[^id]` is immediately followed by a colon.
- REFERENCE: any `[^id]` **not** immediately followed by a colon (the inline citation
  marker in prose).
- Tokens inside triple-backtick fenced code blocks are ignored for both classes. A fence
  toggles on a line whose first non-whitespace content is ```` ``` ````; the toggling line
  itself is excluded.

**Per-file imbalance classes** (computed over the non-code lines of one file):
- GAP: an `id` that appears as a REFERENCE but is never a DEFINITION in that file.
- ORPHAN: an `id` that appears as a DEFINITION but is never a REFERENCE in that file.
- DUPLICATE: an `id` whose DEFINITION appears 2+ times in that file.

**Exit / output contract.**
- Exit `0` iff every file is balanced (no GAPS, ORPHANS, or DUPLICATES anywhere).
- On any imbalance: exit non-zero, and for each offending file print the file path plus
  the specific offending ids, labelled by class (GAP / ORPHAN / DUPLICATE).
- Balanced files print an `ok` line; the run ends with a `PASS`/`FAIL` summary line.

## Acceptance criteria

1. **Parses markers correctly.** For each `docs/curriculum/**/*.md`, the script
   distinguishes a REFERENCE (`[^id]` not followed by `:`) from a DEFINITION (`[^id]:` at
   line start) and reports, per file: GAPS (referenced, never defined), ORPHANS (defined,
   never referenced), DUPLICATES (defined 2+ times). Verifiable by feeding crafted fixture
   files exhibiting each class and asserting each is reported with its id.
2. **Code fences ignored.** A `[^id]` that appears only inside a triple-backtick fenced
   block produces no GAP/ORPHAN/DUPLICATE. Verifiable: a fixture whose *only* occurrence of
   an id is inside a ```` ``` ```` block passes clean (exit 0).
3. **Correct exit semantics.** Exit `0` when all files balanced; exit non-zero and print
   the offending file path + specific ids when any imbalance exists. Verifiable by running
   against a clean fixture (0) and an unbalanced one (non-zero, with path + id in output).
4. **Passes on the current repo.** `sh tests/check-footnotes.sh` exits 0 against the repo
   as-is (curriculum footnotes are balanced now). Verifiable by running it.
5. **Proves the negative case (not trivially always-pass).** The script includes a
   self-test that builds a temp fixture (via `mktemp`) containing at least an unbalanced
   case (e.g. a REFERENCE with no DEFINITION) and asserts the core check returns non-zero
   on it; the script reports the self-test result and fails if the self-test does *not*
   detect the imbalance. Verifiable by reading the script and by temporarily breaking the
   detector to confirm the self-test catches it.
6. **Wired into both gates.** `tests/validate.sh` runs `tests/check-footnotes.sh` as a
   step (so it participates in the agent-first layer check), and `.github/workflows/ci.yml`
   has a dedicated step invoking `sh tests/check-footnotes.sh`. Verifiable by reading both
   files and by `sh tests/validate.sh` exercising the footnote check.

## Notes / references
- Style reference: `tests/check-skill-mirror.sh` (header block, `ok`/`FAIL` lines,
  `fail=0` accumulator, `exit "$fail"`).
- `tests/validate.sh` is invoked as `sh tests/validate.sh [target-dir]`; the footnote step
  must use a path rooted at the repo (not the optional scaffold `target-dir`), since
  `docs/curriculum/` is this repo's content, not part of a scaffolded target. Keep it a
  repo-root-relative `tests/check-footnotes.sh` call guarded to run only when
  `docs/curriculum/` exists, so `validate.sh`'s scaffold-target use is unaffected.
- The strict site build (`.venv/bin/mkdocs build --strict`) already fails on some footnote
  issues at render time; this script is an explicit, fast, deps-light pre-render gate that
  also catches ORPHANS/DUPLICATES strict-build may tolerate.
