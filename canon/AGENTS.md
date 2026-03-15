# Canon Strategy Development

## Quick Reference
- Framework config: `.canon/config.yaml`
- Ralph Loop config: `.canon/dega-core.yaml`
- Agent personas: `.canon/agents/`
- Skills (domain knowledge): `.canon/skills/`
- Workflows: `.canon/workflows/`

## Available Agents

| Agent | Role | Load When |
|-------|------|-----------|
| strategy-architect | Designs strategies from market analysis | Starting a new strategy |
| market-analyst | Interprets market data, finds opportunities | Exploring markets |
| dev | Implements strategies in TypeScript | Writing code |
| qa | Validates quality and standards compliance | Reviewing before registration |
| risk-analyst | Evaluates risk and portfolio impact | Before registration |
| deployment-ops | Registers on Arena, monitors tracked performance | Registering a strategy |

## Available Tools (MCP)
- `canon_init` — Scaffold strategy from template
- `canon_register` — Register strategy on Arena for performance tracking
- `canon_test` — Run against historical data
- `canon_market` — Query market data (Polymarket, Kalshi)
- `canon_position` — Check positions, P&L, portfolio
- `canon_ralph` — Run Ralph Loop iteration
- `canon_help` — Get contextual guidance

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

## Domain Knowledge (Skills)
For prediction market concepts, strategy patterns, risk management, and
platform-specific knowledge, see `.canon/skills/`:
- `prediction-markets.md` — Fundamentals, mechanics, pricing
- `polymarket.md` — Polymarket-specific knowledge (fees, API, resolution)
- `risk-management.md` — Position sizing, exposure limits, hard limits
- `strategy-patterns.md` — Six strategy archetypes and when to use them
- `backtesting.md` — Testing methodology, interpreting results, avoiding overfitting
- `arena-tracking.md` — Registration pipeline, monitoring live strategies
- `ralph-loop.md` — Configuring and operating autonomous iteration
- `canon-conventions.md` — Coding standards, domain layering, error messages

## Strategy Structure
- `src/strategy.ts` — Strategy logic
- `src/types/TradeSignal.ts` — Output interface
- `src/types/RiskInterface.ts` — Risk validation
- `.canon/dega-core.yaml` — Ralph Loop config
