# Prior Art & State of the Art (as of May 2026)

Research capture behind this project. The field moved from "vibe coding" to **engineering
the codebase + harness so agents succeed**. Nothing here is reinvented; we adopt the mature,
permissively-licensed pieces and add the missing layer (a teaching curriculum + an
agent-agnostic interview-driven scaffolder).

## The four layers of "agent-first engineering"

| Layer | What it is | Standard / tool we adopt | License |
|---|---|---|---|
| 1. Context / instructions | The file an agent reads to understand the repo | **`AGENTS.md`** (Linux Foundation; read by Codex, Copilot, Cursor, opencode, Gemini, Claude Code…) | Open standard |
| 2. Reusable skills | Capability loaded on demand | **`SKILL.md`** / Agent Skills (agentskills.io; Anthropic-originated, open standard Dec 18 2025) | Apache-2.0 (reference skills) |
| 3. Methodology / workflow | How you drive the agent | **GitHub Spec Kit** (spec→plan→tasks→implement) | MIT |
| 4. Guardrails / verification | What stops agents wrecking things | lifecycle **hooks**, tests, CI gates; pattern from Spec Kit extensions + `12-factor-agents` | MIT / Apache-2.0 |

## Key reference repos (teardown done locally)

- **`github/spec-kit`** (MIT) — the agent-agnostic engine we model. One shared template →
  **31 agent outputs** via an `INTEGRATION_REGISTRY` of adapter classes; each adapter knows
  *where* files go, *what* format, and *how* commands are invoked. `specify init` scaffolds
  `.specify/` (templates, scripts, memory/constitution) + per-agent command files. Extension
  + hook system (`before_specify`, `before_plan`, …) models our guardrail layer. **This is
  the architecture to copy.**
- **`anthropics/skills`** (mixed; example skills Apache-2.0, doc skills source-available) —
  Anthropic's *implementation* of the `SKILL.md` standard. Format: YAML frontmatter
  (`name`, `description` required) + Markdown body; **progressive disclosure** (metadata
  ~100 tokens → body <5k tokens → `references/`/`scripts/`/`assets/` on demand). The standard
  itself lives at **agentskills.io** and is explicitly cross-agent.
- **`anthropics/claude-plugins-official`** (Apache-2.0) — Claude Code plugin packaging
  (`.claude-plugin/plugin.json` + `marketplace.json`). **Claude-specific**, so we treat it as
  one *optional output adapter*, not the core. Its `plugin-dev` plugin (7 skills for authoring
  hooks/commands/agents/skills) is a useful reference for our generator.
- **`humanlayer/12-factor-agents`** (Apache-2.0) — the principles substrate (own your prompts,
  own your context window, small focused agents, stateless reducers). Cited, not depended on.

## Hooks / guardrails landscape (the convergence)

Lifecycle **hooks** went from a Claude Code feature to a near-universal one in the last year,
and the interfaces are converging on a de-facto standard: a shell command that receives a JSON
event on **stdin** and returns a decision via **exit code / stdout JSON**, registered in a
`hooks.json`-style config.

| Agent | Mechanism | Config | `PreCompact` | Event naming |
|---|---|---|---|---|
| Claude Code | shell + JSON stdin/stdout | `.claude/settings.json` | ✅ `PreCompact`/`PostCompact` | PascalCase, 27+ events |
| Codex CLI | shell + JSON (near-direct port of Claude) | `.codex/hooks/hooks.json` / plugin | ✅ | PascalCase |
| Cursor | shell + JSON stdin/stdout | `.cursor/hooks.json` | ✅ `preCompact` | camelCase |
| Copilot CLI | shell + JSON | `.github/hooks/*.json`, `~/.copilot/hooks/*.json` | ⚠️ session/tool events | camelCase |
| Gemini CLI | shell scripts | `.gemini/settings.json` | ⚠️ lifecycle, string matchers | mixed |
| opencode | JS/TS plugin module | plugin `.ts` | ⚠️ via session lifecycle | `tool.execute.before` |

**Implications for this project:**
- A **portable guardrail layer is feasible**: author once, render per-agent via adapters (same
  pattern as Spec Kit's commands). The hook *logic* is a shared shell script; only the
  *registration* differs per agent.
- **`PreCompact` is native on Claude/Codex/Cursor**; elsewhere fall back to `SessionEnd`/`Stop`
  and record the downgrade.
- **"Capture learnings before compaction" is a known pattern** ("self-improving agent memory" /
  "unified agentic memory across harnesses"): a deterministic, LLM-free hook merges session
  learnings into a markdown memory wiki (merged-by-path, not appended); `SessionStart` re-injects
  them. Heavyweight variants (Neo4j + LLM "dream phase") exist but are too heavy for a default —
  we ship the dependency-free markdown version and offer heavy backends as optional presets.
- `weykon/agent-hooks` (MIT, Rust) does exactly this cross-agent adapter registration but is
  **experimental** (1★, 3 commits) — inspiration, not a dependency. It validates the architecture.

## Methodology references

- **Harper Reed's LLM codegen workflow** — `spec.md → prompt_plan.md → todo.md → execute`;
  the blog-level origin of what Spec Kit productized.
- **OpenAI "harness engineering" / "Building an AI-Native Engineering Team"** — org-level
  framing of agent-first as systems/scaffolding/leverage.

## Does the thing we're building already exist? (Surveyed)

**Building blocks: yes and mature.** The interview-driven, agent-agnostic scaffolder paired
with a curriculum: **no authoritative version exists.** What exists:

- Official primitives, too low-level for our goal: Claude Code's built-in `/init` (only writes
  `CLAUDE.md`), `claude plugin init` (scaffolds a plugin skeleton).
- Individual "kitchen-sink" kits (inspiration, not dependencies — fail our maturity/scope bar):
  `alinaqi/claude-bootstrap` ("Maggy", MIT, ~674★, but sprawling + 13-model router),
  `affaan-m/everything-claude-code` (MIT, Feb 2026 hackathon, unproven),
  `TheDecipherist/claude-code-mastery-project-starter-kit` (MIT, individual), and various
  awesome-lists (`rohitg00/awesome-claude-code-toolkit`, `sickn33/antigravity-awesome-skills`).

**Conclusion:** the gap is real. The official building blocks are mature and permissive; the
missing piece is a curriculum-paired, agent-agnostic, opinionated-but-minimal scaffolder. That
is exactly this project's scope.

## Sources

- AGENTS.md standard — https://agents.md/ · guide: https://blog.buildbetter.ai/agents-md-complete-guide-for-engineering-teams-in-2026/
- Agent Skills standard — https://agentskills.io/ · repo: https://github.com/anthropics/skills · explainer: https://www.firecrawl.dev/blog/agent-skills
- GitHub Spec Kit — https://github.com/github/spec-kit · blog: https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/
- 12-factor-agents — https://github.com/humanlayer/12-factor-agents
- Claude plugins (official) — https://github.com/anthropics/claude-plugins-official
- Harper Reed workflow — https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/
- OpenAI harness engineering — https://openai.com/index/harness-engineering/ · https://developers.openai.com/codex/guides/build-ai-native-engineering-team
- Guardrails / tests — https://htek.dev/articles/tests-are-everything-agentic-ai/ · https://www.propelcode.ai/blog/agentic-engineering-code-review-guardrails
- Agent-ready repo checklist — https://dev.to/domizajac/is-your-repo-ready-for-the-ai-agents-revolution-checklist-1a1b
- Hooks references — Claude: https://code.claude.com/docs/en/hooks · Codex: https://developers.openai.com/codex/hooks · Cursor: https://cursor.com/docs/hooks · Copilot: https://docs.github.com/en/copilot/concepts/agents/hooks · Gemini: https://geminicli.com/docs/hooks/ · opencode: https://opencode.ai/docs/plugins/
- Hook convergence analysis — https://www.speakeasy.com/resources/ai-agent-hooks
- Cross-agent hook registration (experimental) — https://github.com/weykon/agent-hooks
- Unified agentic memory across harnesses — https://towardsdatascience.com/unified-agentic-memory-across-harnesses-using-hooks/ · OpenAI memory+compaction cookbook — https://developers.openai.com/cookbook/examples/agents_sdk/building_reliable_agents_memory_compaction
