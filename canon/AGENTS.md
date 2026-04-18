# Canon — Prediction Market Development Layer

Canon builds on top of the AI Development Core (`../AGENTS.md`). Everything here is
specific to prediction market development. Generic patterns belong in the parent Core.

---

## Structure

```
canon/
├── AGENTS.md          ← You are here (single source of truth)
├── CLAUDE.md          ← Shim → points to AGENTS.md
├── commands/          ← Slash commands (canon-start, develop, discover, register, quick-dev)
├── hooks/             ← Canon-specific lifecycle hooks (empty — future use)
├── skills/            ← Skills (prediction-markets, polymarket, strategy-patterns, risk-management, backtesting, arena-tracking, canon-conventions)
├── agents/            ← Agent personas (dev, market-analyst, strategy-architect, risk-analyst, qa, deployment-ops)
├── rules/             ← Domain layering enforcement (ast-grep)
├── templates/         ← Strategy templates (client-polymarket.ts, client-sportsbook.ts, nba-momentum/)
└── docs/              ← Canon-specific docs (empty — future use)
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
```

Canon artifacts are included in the repo and loaded automatically when working
in the `canon/` directory. No separate install command needed.

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

Canon inherits all Core harness infrastructure (lean AGENTS.md map, `rules/`,
commands, hooks, `docs/exec-plans/`, quality grades) automatically. No
duplication needed here.

Canon-specific addition: domain layering enforcement
(`Types → Config → Repo → Service → Runtime → UI`) is defined in
`canon/rules/domain-layering.md` and enforced via `ast-grep` rules with
agent-friendly error messages. See the `custom-linter-authoring` skill
for how to write and extend these rules.

---

## Available Agents

| Agent | Role | Load When |
|-------|------|-----------|
| strategy-architect | Designs strategies from market analysis | Starting a new strategy |
| market-analyst | Interprets market data, finds opportunities | Exploring markets |
| dev | Implements strategies in TypeScript | Writing code |
| qa | Validates quality and standards compliance | Reviewing before registration |
| risk-analyst | Evaluates risk and portfolio impact | Before registration |
| deployment-ops | Registers on Arena, monitors tracked performance | Registering a strategy |

## Available Tools (CLI)

The Canon CLI (`canon-cli`) wraps Polymarket APIs into shell commands
that return structured JSON. Install via `/apply-core`.

| Command | Description | Auth |
|---------|-------------|------|
| `canon-cli market search <query>` | Search markets by keyword | No |
| `canon-cli market price <id>` | Fetch current outcome prices | No |
| `canon-cli market orderbook <id>` | Fetch order book depth | No |
| `canon-cli market ohlcv <id>` | Fetch OHLCV candlestick data | No |
| `canon-cli position list` | List open positions with PnL | Yes |
| `canon-cli balance` | Fetch wallet balances | Yes |
| `canon-cli order create` | Place a new order | Yes |
| `canon-cli order cancel <id>` | Cancel a specific order | Yes |
| `canon-cli order list` | List recent trades | Yes |
| `canon-cli kill [--yes]` | Cancel all open orders | Yes |
| `canon-cli help [skill]` | Show skill reference | No |

Full reference: `canon/skills/canon-cli.md`

### Where skill knowledge lives

Canon skills (`canon-cli.md`, `polymarket.md`) have **two on-disk
locations** that agents read from:

| Location | Who writes it | Who reads it |
|---|---|---|
| `canon/skills/*.md` (this repo) | PRs to this repo | Agents running **inside this repo** (e.g. Conductor workers in worktrees) |
| `~/.degacore/config/skills/*.md` | `/apply-core` installer | Agents running **anywhere on the machine** (Claude Code's global skill loader, `canon-cli help` fallback, other Canon projects) |

**Edit rule:** always edit `canon/skills/*.md` in this repo. `/apply-core`
copies them to the global location. Never edit the installed copy — it
gets overwritten on the next install.

**`canon-cli help` resolution:** reads project-local `canon/skills/` when
the binary lives inside a checkout of this repo; falls back to
`~/.degacore/config/skills/` otherwise. See `canon/cli/commands/help.ts`.

**Canon TUI (`DEGAorg/conductor-view`, Toad fork):** separate repo. It
does not automatically inherit these skills. Wire it to read from
`~/.degacore/config/skills/` when agent-facing knowledge is needed there.

## Key Workflows
1. **Discover** (`/discover`): Market analysis → opportunity → strategy design
2. **Develop** (`/develop`): Scaffold → implement → test → iterate (Ralph Loop)
3. **Register** (`/register`): Risk review → pre-registration checks → Arena tracking
4. **Ralph Cycle** (`/ralph-cycle`): Execute → check → iterate → SHIP or ESCALATE
5. **Quick Dev** (`/quick-dev`): Small changes with lightweight validation

## Non-Negotiable Rules
1. All strategies implement TradeSignal + RiskInterface
2. Position size never >5% of portfolio
3. Domain layering: Types → Config → Repo → Service → Runtime → UI
4. Error messages include what/why/how
5. "If it's not in the repo, it doesn't exist"

## Strategy Quick Reference

- Framework config: `.canon/config.yaml`
- Ralph Loop config: `.canon/dega-core.yaml`
- Agent personas: `.canon/agents/`
- Skills (domain knowledge): `.canon/skills/`
- Workflows: `.canon/workflows/`

### Strategy Structure
- `src/strategy.ts` — Strategy logic
- `src/types/TradeSignal.ts` — Output interface
- `src/types/RiskInterface.ts` — Risk validation
- `.canon/dega-core.yaml` — Ralph Loop config

## Domain Knowledge (Skills)
For prediction market concepts, strategy patterns, risk management, and
platform-specific knowledge, see `.canon/skills/`:
- `prediction-markets.md` — Fundamentals, mechanics, pricing
- `polymarket.md` — Polymarket-specific knowledge (fees, API, resolution)
- `risk-management.md` — Position sizing, exposure limits, hard limits
- `strategy-patterns.md` — Six strategy archetypes and when to use them
- `backtesting.md` — Testing methodology, interpreting results, avoiding overfitting
- `arena-tracking.md` — Registration pipeline, monitoring live strategies
- `orchestrator.md` — Configuring and operating the automated build engine
- `canon-conventions.md` — Coding standards, domain layering, error messages

---

## Active Work

The Canon layer is shipped. Commands, skills, agents, rules, and templates are
all in place. The live runner with terminal dashboard and orchestrator are
operational.

Current focus areas:
- Strategy template expansion (new market types beyond NBA/sports)
- Arena integration for live performance tracking
- Backtesting pipeline refinement
