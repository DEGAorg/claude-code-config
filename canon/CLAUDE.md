# Canon — Prediction Market Development Layer

Canon builds on top of the AI Development Core (`../CLAUDE.md`). Everything here is
specific to prediction market development. Generic patterns belong in the parent Core.

---

## Structure

```
canon/
├── CLAUDE.md          ← You are here
├── AGENTS.md          ← Agent personas, skills, and workflow reference
├── commands/          ← Slash commands (canon-start, develop, discover, register, ralph-cycle, quick-dev)
├── hooks/             ← Canon-specific lifecycle hooks
├── skills/            ← Skills (prediction-markets, polymarket, strategy-patterns, risk-management, backtesting, arena-tracking, canon-conventions, ralph-loop)
├── agents/            ← Agent personas (dev, market-analyst, strategy-architect, risk-analyst, qa, deployment-ops)
├── rules/             ← Domain layering enforcement (ast-grep)
├── templates/         ← Strategy templates (client-polymarket.ts, client-sportsbook.ts, nba-momentum/)
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

## Domain

Canon targets prediction market development. Shipped skills cover:

- Prediction market fundamentals and terminology (`skills/prediction-markets.md`)
- Polymarket API integration (`skills/polymarket.md`)
- Strategy design patterns (`skills/strategy-patterns.md`)
- Risk management and position sizing (`skills/risk-management.md`)
- Backtesting methodology (`skills/backtesting.md`)
- Arena tracking and performance monitoring (`skills/arena-tracking.md`)

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

The Canon layer is shipped. Commands, skills, agents, rules, and templates are
all in place. The live runner with terminal dashboard and Ralph Loop convergence
are operational.

Current focus areas:
- Strategy template expansion (new market types beyond NBA/sports)
- Arena integration for live performance tracking
- Backtesting pipeline refinement
