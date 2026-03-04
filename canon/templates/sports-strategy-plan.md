# Plan: {{STRATEGY_NAME}} — Strategy Build

**Status:** In progress
**Created:** {{DATE}}

**Prerequisite:** `.canon/` scaffold complete, `pnpm install` done, `.env` populated

## Requirements

### Interfaces (non-negotiable per Canon spec)

- `src/types/TradeSignal.ts` implements the TradeSignal interface (already scaffolded)
- `src/types/RiskInterface.ts` implements the RiskInterface with portfolio-level checks (already scaffolded)

### Strategy: {{STRATEGY_NAME}}

{{STRATEGY_DESCRIPTION}}

**Entry logic:**

{{ENTRY_LOGIC}}

**Exit logic:**

{{EXIT_LOGIC}}

**Risk parameters:**

{{RISK_PARAMS}}

### API Clients

- `src/clients/polymarket.ts` — Polymarket client (scaffolded): fetchMarketPrice, searchMarkets
- `src/clients/sportsbook.ts` — The Odds API client (scaffolded): fetchOdds

### Strategy Implementation Files

- `src/strategies/{{STRATEGY_SLUG}}/scanner.ts` — polls data sources, computes edge
- `src/strategies/{{STRATEGY_SLUG}}/signal.ts` — converts detected edge into a TradeSignal
- `src/strategies/{{STRATEGY_SLUG}}/risk.ts` — implements RiskInterface checks:
  - Position never >5% of portfolio
  - No new signal if daily loss >2% of portfolio
  - Configurable circuit breakers per strategy spec

### Dry-Run Runner

- `src/runner.ts` — standalone executable Node script
  - Reads `.env` for credentials
  - Runs the decision loop: poll → scan → signal → risk check → log
  - **Dry-run only**: logs decisions to `.canon/execution/YYYY-MM-DD.jsonl`, never places orders
  - Each log entry is a structured JSON line
  - Runs until `Ctrl+C` (SIGINT handler flushes and exits cleanly)
  - Usage: `node --env-file=.env dist/runner.js --dry-run`

### Decision log schema (`.canon/execution/YYYY-MM-DD.jsonl`)

```json
{
  "ts": "2026-03-05T14:23:01Z",
  "automation_id": "{{STRATEGY_SLUG}}-v1",
  "signal": {
    "market": { "conditionId": "...", "question": "..." },
    "direction": "buy_yes",
    "size": 100,
    "confidence": 0.82,
    "urgency": "immediate"
  },
  "risk_passed": true,
  "action": "DRY_RUN_SKIP",
  "reasoning": "Edge: 4.2% (...)"
}
```

### Tests

- `src/__tests__/scanner.test.ts` — unit tests for scanner edge detection (mocked clients)
- `src/__tests__/signal.test.ts` — unit tests for signal generation (edge cases: below threshold, at threshold, above)
- `src/__tests__/risk.test.ts` — unit tests for RiskInterface checks (over-limit, near-resolution, daily loss)
- All tests pass with `pnpm exec vitest run`
- Tests mock `src/clients/polymarket` and `src/clients/sportsbook` — no live API calls in tests

### Quality bar

- `tsc --noEmit` passes (zero errors)
- `oxlint src/` passes (zero warnings)
- `vitest run` passes (all tests green)
- Dry-run runner starts, polls at least once, writes at least one log entry

## Approach

### Domain layering order

```
src/types/TradeSignal.ts                     ← Layer 1: Types (no imports from higher layers)
src/types/RiskInterface.ts                   ← Layer 1: Types
src/clients/polymarket.ts                    ← Layer 2: Clients (imports types)
src/clients/sportsbook.ts                   ← Layer 2: Clients
src/strategies/{{STRATEGY_SLUG}}/scanner.ts  ← Layer 3: Service (imports clients + types)
src/strategies/{{STRATEGY_SLUG}}/signal.ts   ← Layer 3: Service
src/strategies/{{STRATEGY_SLUG}}/risk.ts     ← Layer 3: Service
src/runner.ts                                ← Layer 5: Runtime (imports everything, entry point)
```

### Scanner poll logic

```typescript
// Pseudo-code — Dev agent fleshes this out
async function scanOnce(): Promise<Edge[]> {
  const [bookOdds, pmMarkets] = await Promise.all([
    fetchOdds('{{SPORT_KEY}}'),
    searchMarkets('{{MARKET_QUERY}}'),
  ]);
  return bookOdds
    .flatMap(game => matchToPolymarket(game, pmMarkets))
    .filter(({ edge }) => edge > MIN_EDGE)
}
```

## Files to touch

| File | Change |
|------|--------|
| `src/types/index.ts` | Create — re-export shared types (Portfolio, MarketPrice, SportEvent) |
| `src/strategies/{{STRATEGY_SLUG}}/scanner.ts` | Create — poll + edge detection |
| `src/strategies/{{STRATEGY_SLUG}}/signal.ts` | Create — TradeSignal builder |
| `src/strategies/{{STRATEGY_SLUG}}/risk.ts` | Create — RiskInterface implementation |
| `src/runner.ts` | Create — dry-run loop, SIGINT handler, JSONL logger |
| `src/__tests__/scanner.test.ts` | Create — edge detection unit tests |
| `src/__tests__/signal.test.ts` | Create — signal generation tests |
| `src/__tests__/risk.test.ts` | Create — risk check tests |

## Risks and open questions

- **Market matching:** Matching sportsbook events to Polymarket questions by team/event name
  may need fuzzy matching. Log unmatched events gracefully.
- **No live data at build time:** Tests must use mocked data. Runner should log
  "no edges detected" gracefully if no markets found.

## Progress log

- [ ] Create `src/types/index.ts` with shared types
- [ ] Create `src/strategies/{{STRATEGY_SLUG}}/scanner.ts`
- [ ] Create `src/strategies/{{STRATEGY_SLUG}}/signal.ts`
- [ ] Create `src/strategies/{{STRATEGY_SLUG}}/risk.ts`
- [ ] Create `src/runner.ts` with dry-run loop and JSONL logger
- [ ] Create `src/__tests__/scanner.test.ts`
- [ ] Create `src/__tests__/signal.test.ts`
- [ ] Create `src/__tests__/risk.test.ts`
- [ ] Run `pnpm exec tsc --noEmit` — zero errors
- [ ] Run `pnpm exec oxlint src/` — zero warnings
- [ ] Run `pnpm exec vitest run` — all tests pass
- [ ] Smoke test: runner writes at least one `.canon/execution/*.jsonl` entry

## Completion criteria

- [ ] `pnpm exec tsc --noEmit` exits 0
- [ ] `pnpm exec oxlint src/` exits 0
- [ ] `pnpm exec vitest run` exits 0 (all tests pass)
- [ ] `src/runner.ts` is a standalone executable that accepts `--dry-run` flag
- [ ] At least one `.canon/execution/*.jsonl` entry written after smoke test
