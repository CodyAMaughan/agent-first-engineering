# reference/linear-coding-agents
Linear **"Coding sessions"** (launched 2026-06-11, Business/Enterprise) is turnkey: assign an issue to **@linear** and Linear's agent runs Claude Code (default **Opus 4.8**) in the cloud, reads the codebase, **opens a GitHub PR**, syncs the diff/status back to the ticket. Self-host alternative: **Cyrus** (open-source) runs *your* Claude Code as an assignable Linear agent via the Agent Session SDK. **Linear MCP** (`mcp.linear.app/mcp`) lets your Claude read/create/triage issues. Linear↔GitHub: magic branch names + `Closes ENG-123` auto-link/close. The retry-until-green loop is **DIY** — that's what our `feature-pipeline` workflow is.
Sources: linear.app/changelog/2026-06-11-coding-sessions · linear.app/docs/coding-sessions · atcyrus.com

