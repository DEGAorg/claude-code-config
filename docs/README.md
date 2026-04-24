# Docs — Index

Reference documentation for DEGA Core contributors and agents. Everything here
describes **this repo's internals** — harness design, install flow, agent
patterns, and architecture decisions.

Content that is strictly product, roadmap, or Canon-initiative strategy lives
in the sibling [`canon-docs`](../../canon-docs) repo instead. See
[authoring-docs.md](authoring-docs.md) before adding or renaming files.

---

## Architecture & design

| Doc | Covers |
|-----|--------|
| [agent-agnostic-architecture.md](agent-agnostic-architecture.md) | Multi-agent abstraction layer, per-agent adapters, `agent-shim.sh` |
| [bootstrap-install-pattern.md](bootstrap-install-pattern.md) | Natural-language install pattern (fetch `INSTALL.md`, run phases) |
| [conductor-agent-design.md](conductor-agent-design.md) | Conductor = the orchestration engine that runs plans |
| [harness-implementation.md](harness-implementation.md) | Harness internals — hooks, settings, orchestrator |
| [canon-installation-architecture-analysis.md](canon-installation-architecture-analysis.md) | Core vs Canon install scope, `canon_init` behavior |

## Guides

| Doc | Covers |
|-----|--------|
| [canon-quickstart.md](canon-quickstart.md) | First-run flow for Canon |
| [canon-tui-integration.md](canon-tui-integration.md) | How the Canon TUI attaches to orchestrator state |
| [timeline-api-guide.md](timeline-api-guide.md) | GitHub Issues + Milestones + Project board as timeline |
| [dev-flow.md](dev-flow.md) | Day-to-day dev loop with the harness |
| [ai-dev-pipeline.md](ai-dev-pipeline.md) | End-to-end AIDD pipeline overview |

## Reference

| Doc | Covers |
|-----|--------|
| [agent-operating-mode.md](agent-operating-mode.md) | When to operate autonomously vs ask |
| [agnostic-gem-recommendations.md](agnostic-gem-recommendations.md) | Cross-agent tool/gem picks |
| [dega-core-vs-vanilla.md](dega-core-vs-vanilla.md) | What DEGA Core adds on top of stock agent setups |
| [ralph-loop-reference.md](ralph-loop-reference.md) | Minimal outer-loop pattern (**superseded** by orchestrator) |
| [quality.md](quality.md) | Quality gates and review standards |
| [self-development.md](self-development.md) | How the harness improves itself |

## Decisions (ADRs)

Date-prefixed architecture decision records. Format: `YYYYMMDD-topic-slug.md`.

- [`decisions/`](decisions/) — browse the full list.

## Canon specs (external)

Canon-initiative specs, roadmap, and product strategy are in the sibling
[`canon-docs`](../../canon-docs) repo, **not here**. Do not duplicate them.
See [`AGENTS.md`](../AGENTS.md) for the read-only reference table.

---

## Adding a doc

See [authoring-docs.md](authoring-docs.md) for naming conventions, category
placement, and when to pick README/guide/reference/ADR.
