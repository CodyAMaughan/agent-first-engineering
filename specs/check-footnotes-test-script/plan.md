# Plan: `tests/check-footnotes.sh` — Markdown footnote integrity check

Implements `specs/check-footnotes-test-script/spec.md`.

## Files to touch

| File | Change |
|---|---|
| `tests/check-footnotes.sh` | **New.** POSIX-`sh` footnote integrity checker + built-in self-test. Style-matched to `tests/check-skill-mirror.sh`. `chmod +x`. |
| `tests/validate.sh` | **Edit.** Add a new numbered step that runs `tests/check-footnotes.sh`, guarded to fire only when `docs/curriculum/` exists (so the scaffold-`target-dir` use is unaffected). |
| `.github/workflows/ci.yml` | **Edit.** Add a dedicated step `run: sh tests/check-footnotes.sh`, placed alongside the other `tests/*.sh` steps (after skill-mirror / validate). |

No other files. No new deps — only `awk`, `grep`, `find`, `mktemp`, plus shell builtins (the same toolset `check-skill-mirror.sh`/`validate.sh` already rely on).

## Approach

### 1. `tests/check-footnotes.sh` structure

Mirror the house style of `check-skill-mirror.sh`:
- Header comment block (what it asserts, determinism, deps, "run from repo root").
- `set -u`, `fail=0` accumulator, per-file `ok`/`FAIL` lines, blank line, trailing `PASS`/`FAIL` summary, `exit "$fail"`.

Decompose into:

**(a) A pure core checker `check_file <path>`** — the only place footnote grammar lives. It prints nothing on a balanced file and returns 0; on imbalance it prints the offending ids (labelled `GAP`/`ORPHAN`/`DUPLICATE`) and returns 1. Keeping this a single function is what lets the self-test exercise the *real* detector (AC5) rather than a parallel reimplementation.

**(b) A single `awk` pass per file** does the parsing (the spec's grammar is line-oriented, so one `awk` program is cleaner and faster than grep loops):
- Track a `in_fence` toggle: a line whose first non-whitespace content is ` ``` ` flips it; that toggling line is itself skipped (matches spec — fence lines excluded).
- For non-fence, non-skipped lines, scan for `[^id]` tokens where `id` = `[^]]+`:
  - token immediately followed by `:` → **DEFINITION** of `id` (only when the `[` is at line start ignoring leading whitespace, per grammar) → increment `def[id]`.
  - any other `[^id]` → **REFERENCE** → increment `ref[id]`.
  - A line may legitimately hold both a definition and trailing references; the scan walks the whole line, not just the first match.
- `END`: emit, for the file, the classes:
  - **GAP**: `ref[id] > 0 && def[id] == 0`
  - **ORPHAN**: `def[id] > 0 && ref[id] == 0`
  - **DUPLICATE**: `def[id] >= 2`
  - Print each offending id on a labelled line; set a non-zero awk exit via `exit 1` when any class fired, `exit 0` otherwise. The shell wrapper turns that into the `ok`/`FAIL` line + `fail` accumulation.
- Emit offending ids in a stable order (`sort`-friendly / `asorti` or accumulate then sort) so output is deterministic.

**(c) Main loop**: `find docs/curriculum -name '*.md'` (the fixed recursive glob), sorted, calling `check_file` on each; one `ok`/`FAIL` line per file.

**(d) Self-test (AC5)** runs *before* the real scan and gates the whole script:
- `mktemp` a fixture containing at least an unbalanced case — a REFERENCE with no DEFINITION (a GAP) — and ideally one of each class plus a clean control, including an id that appears **only inside a ` ``` ` fence** to also assert AC2 negatively.
- Run the *same* `check_file` against the fixture; assert it returns non-zero **and** names the expected id. If the self-test does **not** detect the planted imbalance, print `FAIL self-test` and `exit 1` immediately — the script refuses to certify the repo using a detector that can't catch a known break. `rm -rf` the temp dir (trap on EXIT for cleanliness).

### 2. `tests/validate.sh` wiring

Add a step (numbered after the current step 4) that runs the footnote check **only when this is the agent-first repo itself**, not a scaffolded `target-dir`:

```sh
# 5. Curriculum footnote integrity (repo-self only; scaffold targets have no docs/curriculum).
if [ -d "$ROOT/docs/curriculum" ]; then
  if ( cd "$ROOT" && sh tests/check-footnotes.sh >/dev/null 2>&1 ); then
    ok "curriculum footnotes balanced"
  else
    bad "curriculum footnote imbalance (run: sh tests/check-footnotes.sh)"
  fi
fi
```

- Rooted at `$ROOT` and guarded by `[ -d "$ROOT/docs/curriculum" ]`, so passing a scaffold `target-dir` (which has no curriculum) is a clean no-op — preserving `validate.sh`'s existing contract.
- Uses the existing `ok`/`bad` helpers so it folds into the same `fail` accumulator and `PASS`/`FAILURES` summary. The full per-file output stays in the standalone script; `validate.sh` shows a one-line roll-up and points to the script for detail.

### 3. `.github/workflows/ci.yml` wiring

Add a dedicated step next to the other shell-test steps (so it is its own visible, independent gate even though `validate.sh` also exercises it):

```yaml
- name: Footnote integrity (curriculum [^n] balance)
  run: sh tests/check-footnotes.sh
```

Placed after "Validate agent-first layer". Independent of the strict mkdocs build — this is the fast, deps-light pre-render gate the spec's Notes call for (also catches ORPHANS/DUPLICATES strict-build may tolerate).

## Test strategy — acceptance-criterion coverage

Each AC is verified by a concrete, repeatable command; the AC5 self-test makes the script self-verifying on every run.

| # | Acceptance criterion | How it's verified |
|---|---|---|
| 1 | Parses REFERENCE vs DEFINITION; reports GAP/ORPHAN/DUPLICATE per file with the id | Feed three crafted `mktemp` fixtures (one per class) through `check_file`; assert each prints its class label + the exact id. The built-in self-test (run on every invocation) covers ≥ the GAP class; the others verified by an ad-hoc fixture during dev (`printf` a file with a duplicate `[^a]:`/`[^a]:`, an orphan `[^b]:` with no `[^b]`, a gap `[^c]` with no `[^c]:`) and asserting the labelled output. |
| 2 | Code fences ignored | Fixture whose **only** occurrence of an id is inside a ` ``` ` block → `check_file` returns 0 / `ok`. Verified both ad-hoc and as a case inside the self-test fixture (an id that would be an ORPHAN/GAP if the fence weren't skipped must produce nothing). |
| 3 | Exit semantics | `sh tests/check-footnotes.sh` on a **clean** fixture → exit 0; on an **unbalanced** fixture → non-zero with the offending path + id in stdout. Checked via `echo $?` and grepping output for the path and id. |
| 4 | Passes on current repo | `sh tests/check-footnotes.sh` from repo root → `echo $?` is `0` (the 62 `docs/curriculum/**/*.md` files are balanced today). Run as the final integration check. |
| 5 | Proves the negative case | Read the script to confirm the self-test exists and gates execution. Then **temporarily break the detector** (e.g. neuter the GAP rule) and run the script → it must print `FAIL self-test` and exit non-zero; revert. This proves the script isn't trivially always-pass. |
| 6 | Wired into both gates | Read `tests/validate.sh` (the guarded step present) and `.github/workflows/ci.yml` (the dedicated step present). Run `sh tests/validate.sh` from repo root and confirm the new `ok curriculum footnotes balanced` line appears and the run still exits 0. CI step is byte-checked by reading the YAML; broader CI validity covered by the existing `check-yaml` pre-commit hook. |

**Regression / non-breakage checks (beyond the ACs):**
- `sh tests/validate.sh <some-empty-tmpdir>` still passes (no `docs/curriculum/` → footnote step is a no-op), proving the scaffold-target path is unaffected.
- `chmod +x tests/check-footnotes.sh` and confirm it's executable (validate.sh's hook check pattern; CI invokes via `sh` so the bit isn't strictly required, but keep parity with `check-skill-mirror.sh`).
- Determinism: run twice, diff output — identical (sorted file list + sorted id output).

## Risks / notes
- **Grammar edge — definition lines that also reference.** The `awk` scan must walk the entire line so a line like `[^1]: Source, see also [^2].` records a *definition* of `1` and a *reference* of `2`. Covered by adding such a line to a dev fixture.
- **`id` charset.** `[^]]+` is greedy up to the next `]`; nested/adjacent tokens on one line are handled by advancing past each matched `]`. A fixture with two tokens on one line (`...[^a][^b]...`) verifies the walk.
- **Fence detection scope.** Only triple-backtick fences are toggled (per spec); `~~~` and 4-space indented blocks are intentionally out of scope — no handling added, documented in the header comment so a future maintainer knows it's deliberate.
- **`set -e` interaction in CI.** The script ends in `exit "$fail"`; CI's `run:` is a single command so no `set -e` subtlety. In `validate.sh` the call is wrapped in `if ( ... )` so a non-zero exit is caught, not fatal.
