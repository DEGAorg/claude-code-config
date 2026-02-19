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

- Core provides: dev pipeline, harness patterns, generic commands (`/fix-issue`, `/review-pr`,
  `/plan`, `/cleanup`), generic hooks, generic skills.
- Canon provides: prediction market domain models, market analysis agents, oracle integration
  patterns, position management skills, domain-specific linters and hooks.

When a Canon pattern proves useful beyond prediction markets, promote it to Core.

---

## Installation

Requires Core to be installed first:

```
/apply-core            # Install generic AI development infrastructure
/apply-canon           # Layer Canon on top
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

## Active Work

This layer is being scaffolded. Next steps:

1. Define the Canon domain model in `docs/`.
2. Create first Canon-specific skills for market analysis.
3. Create first Canon-specific agents with domain personas.
4. Build the `/apply-canon` command.
