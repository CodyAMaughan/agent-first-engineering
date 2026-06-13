#!/bin/sh
# check-skill-mirror-mode.sh — assert tests/check-skill-mirror.sh is NOT a
# false-green when a mirrored hook keeps identical CONTENT but loses its
# executable bit on one side.
#
# Bug under test (check-skill-mirror.sh:41,45): the per-skill comparison is
# `diff -r "$AG/$name" "$CL/$name"`, which compares file CONTENT only and
# ignores the file MODE / executable bit. A skill hook that is executable in
# .agents/skills (canonical) but non-executable in .claude/skills (mirror)
# therefore passes as "ok"/"PASS"/exit 0 even though the mirror's copy will not
# run when invoked. The script nonetheless asserts the two trees are
# "byte-identical ... mirror byte-for-byte."
#
# Materiality: the skills library ships executable hook scripts that must run
# from the mirror — e.g. scaffold-agent-project/assets/hooks/{load-memory,
# git-safety,test-gate,secret-scan,capture-learnings,format}.sh (git mode
# 100755 on both sides). A +x bit lost on a .claude/skills copy is a real
# functional divergence (the mirror's hook would not run) that this parity gate
# is supposed to catch.
#
# EXPECTED: a parity gate that promises "byte-for-byte" must NOT report
# PASS/exit 0 when a mirrored executable hook is non-executable on one side.
#
# Like check-skill-mirror-empty.sh / check-test-gate-isolation.sh, this drives
# the REAL target script in a throwaway temp repo and runs a built-in self-test
# first to prove the oracle isn't trivially always-fail: it must accept a
# healthy (byte-identical content AND mode) tree and reject the mode-diverged one.
# Deterministic, POSIX sh, deps: mktemp/cp/chmod/find. Run from the repo root.

set -u
ROOT="${1:-.}"
TARGET="$ROOT/tests/check-skill-mirror.sh"
# Absolute path: we run the target from inside a temp repo, so a relative path
# would vanish once we leave the real repo root.
case "$TARGET" in /*) ;; *) TARGET="$(pwd)/$TARGET" ;; esac
fail=0

[ -f "$TARGET" ] || { echo "FAIL — target not found: $TARGET"; exit 1; }

echo "Checking skill-mirror gate is not a false-green on an executable-bit divergence: $TARGET"

# run_gate <skills-tree-builder>: build a temp repo (.agents/skills + .claude/skills),
# let the caller-supplied function populate it, then run the REAL gate from that
# repo root. Echoes the gate's combined output. The gate's exit code is written
# to $RC_FILE (a file, not a var) so it survives the $(...) subshell capture.
RC_FILE=$(mktemp) || { echo "FAIL — mktemp failed"; exit 1; }
run_gate() {
  builder="$1"
  td=$(mktemp -d) || { echo "MKTEMP-FAIL"; echo 99 > "$RC_FILE"; return; }
  mkdir -p "$td/.agents/skills" "$td/.claude/skills" "$td/tests"
  cp "$TARGET" "$td/tests/check-skill-mirror.sh"
  ( cd "$td" && "$builder" "$td" )   # populate the trees for this scenario
  out=$( cd "$td" && sh tests/check-skill-mirror.sh 2>&1 ); rc=$?
  echo "$rc" > "$RC_FILE"
  rm -rf "$td"
  printf '%s\n' "$out"
}

# Scenario builders ------------------------------------------------------------
# Healthy: one first-party skill whose hook is identical in content AND mode
# (executable on both sides). This MUST pass the gate.
build_healthy() {
  td="$1"
  mkdir -p "$td/.agents/skills/demo" "$td/.claude/skills/demo"
  printf 'name: demo\n' > "$td/.agents/skills/demo/SKILL.md"
  printf 'name: demo\n' > "$td/.claude/skills/demo/SKILL.md"
  printf '#!/bin/sh\necho hi\n' > "$td/.agents/skills/demo/run.sh"
  printf '#!/bin/sh\necho hi\n' > "$td/.claude/skills/demo/run.sh"
  chmod +x "$td/.agents/skills/demo/run.sh" "$td/.claude/skills/demo/run.sh"
}
# Mode-diverged: identical CONTENT, but the mirror copy lost its +x bit. The
# canonical hook is executable; the mirror's is not. This is the bug repro.
build_mode_drift() {
  td="$1"
  mkdir -p "$td/.agents/skills/demo" "$td/.claude/skills/demo"
  printf 'name: demo\n' > "$td/.agents/skills/demo/SKILL.md"
  printf 'name: demo\n' > "$td/.claude/skills/demo/SKILL.md"
  printf '#!/bin/sh\necho hi\n' > "$td/.agents/skills/demo/run.sh"
  printf '#!/bin/sh\necho hi\n' > "$td/.claude/skills/demo/run.sh"
  chmod +x "$td/.agents/skills/demo/run.sh"     # canonical: executable
  chmod -x "$td/.claude/skills/demo/run.sh"     # mirror: NOT executable (drift)
}

# --- self-test (proves this regression oracle isn't trivially always-fail) -----
# A healthy tree (identical content AND mode) MUST pass the gate (exit 0). If the
# oracle rejected even that, it would be meaningless.
healthy_out=$(run_gate build_healthy); healthy_rc=$(cat "$RC_FILE")
if [ "$healthy_rc" -eq 0 ]; then
  echo "  ok   self-test: healthy tree (same content + same +x bit) passes the gate (exit 0)"
else
  echo "  FAIL self-test: healthy tree did NOT pass (exit $healthy_rc) — oracle too strict:"
  printf '%s\n' "$healthy_out" | sed 's/^/         /'
  echo "FAIL — self-test failed; aborting."
  exit 1
fi

# --- real check: the executable-bit drift MUST NOT be a clean PASS -------------
drift_out=$(run_gate build_mode_drift); drift_rc=$(cat "$RC_FILE")
echo "  ..   mode-drift gate exited $drift_rc"
if [ "$drift_rc" -eq 0 ]; then
  echo "  FAIL mode-drift parity gate reported success (exit 0) — the mirror's hook lost its +x bit yet it passes as byte-identical:"
  printf '%s\n' "$drift_out" | sed 's/^/         /'
  fail=1
else
  echo "  ok   mode-drift gate flags the lost executable bit (exit $drift_rc)"
fi

rm -f "$RC_FILE"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — skill-mirror gate refuses to false-green a hook that lost its +x bit on the mirror side."
else
  echo "FAIL — tests/check-skill-mirror.sh declares a mirrored hook 'byte-identical' even though it is executable in .agents/skills but NOT in .claude/skills ('diff -r' at line 41/45 compares content only, ignoring file mode). The mirror's hook would not run. Compare the executable bit too (e.g. per-file mode check, or 'find -perm' parity)."
fi
exit "$fail"
