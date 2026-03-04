# Plan: NBA Momentum Strategy Build

**Status:** In progress
**Created:** {{DATE}}

## Requirements

Implement the NBA Game Momentum Trader strategy from `docs/strategy-nba-momentum.md`.
Bootstrapped files (runner, types, test harness, clients) are already in place.
Build the decision logic, config, and risk management.

### Quality bar

- `tsc --noEmit` passes (zero errors)
- `oxlint src/` passes (zero warnings)
- `vitest run` passes (all tests green)
- Dry-run runner starts and writes at least one `.canon/execution/*.jsonl` entry

## Domain layering

```
src/types/game.ts              ← Layer 1: Types (bootstrapped)
src/types/TradeSignal.ts       ← Layer 1: Types (bootstrapped)
src/types/RiskInterface.ts     ← Layer 1: Types (bootstrapped)
src/clients/polymarket.ts      ← Layer 2: Clients (bootstrapped)
src/clients/sportsbook.ts      ← Layer 2: Clients (bootstrapped)
src/config/strategy.ts         ← Layer 2: Config (BUILD)
src/config/risk.ts             ← Layer 2: Config (BUILD)
src/service/signals.ts         ← Layer 3: Service (BUILD)
src/service/risk.ts            ← Layer 3: Service (BUILD)
src/strategy.ts                ← Layer 4: Strategy (BUILD)
src/runner.ts                  ← Layer 5: Runtime (bootstrapped)
```

## Progress log

- [x] Bootstrap types: `src/types/game.ts` (Game, InjuryReport, Portfolio, Position, ExitReason)
- [x] Bootstrap types: `src/types/TradeSignal.ts`, `src/types/RiskInterface.ts`
- [x] Bootstrap clients: `src/clients/polymarket.ts`, `src/clients/sportsbook.ts`
- [x] Bootstrap runner: `src/runner.ts` (polling loop, JSONL logger, SIGINT handler)
- [x] Bootstrap test harness: `src/__tests__/strategy.test.ts` (factories, test shells)
- [ ] Create `src/config/strategy.ts` — entry thresholds from spec (minLineMovePoints: 3, minMispricingThreshold: 0.05, etc.)
- [ ] Create `src/config/risk.ts` — risk limits from spec (maxPositionSizePct: 0.03, stopLossPct: 0.08, etc.)
- [ ] Create `src/service/signals.ts` — shouldEnter() and shouldExit() decision logic per spec pseudocode
- [ ] Create `src/service/risk.ts` — NbaRiskManager implementing RiskInterface with circuit breaker, drawdown, daily loss, position size checks
- [ ] Create `src/strategy.ts` — NbaMomentumStrategy wiring class (evaluate + checkExit)
- [ ] Fill in test assertions in `src/__tests__/strategy.test.ts` to verify signal logic
- [ ] Run `pnpm exec tsc --noEmit` — zero errors
- [ ] Run `pnpm exec oxlint src/` — zero warnings
- [ ] Run `pnpm exec vitest run` — all tests pass

## Completion criteria

- [ ] `pnpm exec tsc --noEmit` exits 0
- [ ] `pnpm exec oxlint src/` exits 0
- [ ] `pnpm exec vitest run` exits 0 (all tests pass)
