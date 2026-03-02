# Canon — Prediction Market Development Layer

Canon builds on top of the AI Development Core (`../CLAUDE.md`). Everything here is
specific to prediction market development. Generic patterns belong in the parent Core.

---

## Structure

```
canon/
├── CLAUDE.md          ← You are here
├── commands/          ← Canon-specific slash commands
├── hooks/             ← Canon-specific lifecycle hooks
├── skills/            ← Canon-specific skills (market analysis, oracle patterns, etc.)
├── agents/            ← Canon-specific agents (market analyst, risk evaluator, etc.)
└── docs/              ← Canon architecture, domain models, API references
```

---

## Relationship to Core

Canon **depends on** Core. Core **never depends on** Canon.

- Core provides: dev pipeline, harness patterns, generic commands (`/dega:fix-issue`, `/dega:review-pr`,
  `/dega:plan`, `/dega:cleanup`), generic hooks, generic skills.
- Canon provides: prediction market domain models, market analysis agents, oracle integration
  patterns, position management skills, domain-specific linters and hooks.

When a Canon pattern proves useful beyond prediction markets, promote it to Core.

---

## Installation

Requires Core to be installed first:

```
/dega:apply-core       # Install generic AI development infrastructure
/dega:canon-init       # Scaffold Canon in current project (run from strategy directory)
```

---

## Domain (to be expanded)

Canon targets prediction market development. Key areas to be covered:

- Market creation and resolution patterns
- Oracle integration and data feeds
- Position management and risk modeling
- Liquidity pool mechanics
- Event outcome verification
- Smart contract patterns for prediction markets

---

## Harness

Canon inherits all Core harness infrastructure (lean CLAUDE.md map, `rules/`,
commands, hooks, `docs/exec-plans/`, quality grades) automatically. No
duplication needed here.

Canon-specific addition: domain layering enforcement
(`Types → Config → Repo → Service → Runtime → UI`) is defined in
`canon/rules/domain-layering.md` and enforced via `ast-grep` rules with
agent-friendly error messages. See the `custom-linter-authoring` skill
for how to write and extend these rules.

---

## Active Work

This layer is being scaffolded. Next steps:

1. Define the Canon domain model in `docs/`.
2. Create first Canon-specific skills for market analysis.
3. Create first Canon-specific agents with domain personas.
4. ~~Build the `/dega:canon-init` command.~~ **Done** — `commands/canon-init.md` created.
