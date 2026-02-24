# Plan: Canon Agent Framework Artifacts

**Status:** In progress
**Created:** 2026-02-23

## Requirements

- `canon/AGENTS.md` — entry-point quick reference: agent table, available tools,
  key workflows, non-negotiable rules, links to skills and deeper docs
- `canon/skills/*.md` — 8 skill files injecting domain knowledge into context
- `canon/agents/*.md` — 6 agent persona files as Claude Code subagent definitions
  (frontmatter: name, description; body: identity, responsibilities, constraints,
  workflow, handoff protocol)
- `canon/commands/*.md` — 5 workflow slash commands (discover, develop, register,
  ralph-cycle, quick-dev) matching Core's command format
- `commands/apply-canon.md` updated to list and install all new artifacts

All content must be grounded in `canon-docs/specs/SAS_Agent_Framework.md`.
No content beyond that spec; no speculative features.

## Approach

Write each file directly from the spec, adapting format to Claude Code conventions:

- **Skills** — plain markdown, no frontmatter. Context-injection files describing
  domain knowledge, decision frameworks, hard limits, and common mistakes.
- **Agents** — markdown with YAML frontmatter (`name`, `description`). Body follows
  spec: identity, responsibilities, behavioral constraints, workflow steps, handoff
  protocol. Claude Code reads these from `.claude/agents/` as subagent definitions.
- **Commands/Workflows** — markdown slash commands matching Core's `commands/*.md`
  pattern. Step-by-step procedures with inputs, outputs, and success criteria.
- **AGENTS.md** — ~100-line table of contents. Quick reference, not deep content.

After the artifact files, update `apply-canon.md` to enumerate and install them.

## Files to touch

| File | Change |
|------|--------|
| `canon/AGENTS.md` | Create — entry point |
| `canon/skills/prediction-markets.md` | Create |
| `canon/skills/polymarket.md` | Create |
| `canon/skills/risk-management.md` | Create |
| `canon/skills/strategy-patterns.md` | Create |
| `canon/skills/backtesting.md` | Create |
| `canon/skills/arena-tracking.md` | Create |
| `canon/skills/ralph-loop.md` | Create |
| `canon/skills/canon-conventions.md` | Create |
| `canon/agents/strategy-architect.md` | Create |
| `canon/agents/risk-analyst.md` | Create |
| `canon/agents/market-analyst.md` | Create |
| `canon/agents/dev.md` | Create |
| `canon/agents/qa.md` | Create |
| `canon/agents/deployment-ops.md` | Create |
| `canon/commands/discover.md` | Create |
| `canon/commands/develop.md` | Create |
| `canon/commands/register.md` | Create |
| `canon/commands/ralph-cycle.md` | Create |
| `canon/commands/quick-dev.md` | Create |
| `commands/apply-canon.md` | Update — enumerate + install all new files |

## Risks and open questions

- **Resolved:** Workflow format is markdown slash commands (not YAML) — consistent
  with Core's `commands/*.md` convention. Claude Code has no native workflow YAML.
- **Resolved:** Agent format uses YAML frontmatter (`name`, `description`) matching
  Claude Code subagent conventions from `.claude/agents/`.
- **P2:** Some spec sections reference `arena-tracking` — Arena is out of scope for
  Ace (no Arena UI), but the skill and agent can still exist as infra for later.
  Include them as-is from the spec; do not stub them out.
- **P2:** MCP tools (canon_init, canon_register, etc.) are **not** in scope here.
  AGENTS.md references them as available tools without implementing them.

## Progress log

- [x] Read SAS_Agent_Framework.md skill sections fully (pre-work)
- [x] Write `canon/AGENTS.md`
- [x] Write `canon/skills/prediction-markets.md`
- [x] Write `canon/skills/polymarket.md`
- [x] Write `canon/skills/risk-management.md`
- [x] Write `canon/skills/strategy-patterns.md`
- [x] Write `canon/skills/backtesting.md`
- [x] Write `canon/skills/arena-tracking.md`
- [x] Write `canon/skills/ralph-loop.md`
- [x] Write `canon/skills/canon-conventions.md`
- [x] Write `canon/agents/strategy-architect.md`
- [x] Write `canon/agents/risk-analyst.md`
- [x] Write `canon/agents/market-analyst.md`
- [x] Write `canon/agents/dev.md`
- [x] Write `canon/agents/qa.md`
- [x] Write `canon/agents/deployment-ops.md`
- [x] Write `canon/commands/discover.md`
- [x] Write `canon/commands/develop.md`
- [x] Write `canon/commands/register.md`
- [x] Write `canon/commands/ralph-cycle.md`
- [x] Write `canon/commands/quick-dev.md`
- [x] Update `commands/apply-canon.md` to enumerate + install all new files
- [x] Verify all files lint-clean and consistent with spec
- [x] Commit on feature branch

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Workflows as markdown commands | YAML workflow files, Python runner | Core uses `.md` slash commands; no native YAML workflow runner in Claude Code |
| Agent files in `canon/agents/` with YAML frontmatter | Plain markdown, JSON | Claude Code subagent convention requires frontmatter for name + description |
| Arena skill + agent included | Stub or omit | Spec includes them; excluding would diverge from source of truth. Arena UI is out of scope, not the infra skill. |
| MCP tools excluded from this plan | Include stubs | Tools require separate implementation (MCP server); no spec gap to fill here |

## Completion criteria

- [x] All 21 new/updated files written
- [x] Content matches SAS_Agent_Framework.md spec (no fabricated content)
- [x] Agent files have valid YAML frontmatter
- [x] `apply-canon.md` updated to install skills, agents, commands
- [x] No linting issues (shellcheck N/A — all markdown)

**Post-loop (human):** Open PR from `ace-work → main` once `gh` is authenticated.
