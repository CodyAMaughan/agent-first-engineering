# Git workflow

This repo commits directly to `main` (solo / docs / trunk-based). The `git-safety` hook's branch
protection is intentionally disabled via `PROTECTED_BRANCHES=""` in `.agent/guardrails.conf`, so
commits/pushes to `main` are expected. Push only when the user explicitly asks.
