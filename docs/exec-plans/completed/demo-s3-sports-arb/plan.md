# Plan: Demo S3 — Sports Arb Strategy Build (The Demo Moment)

**Status:** In progress
**Created:** 2026-02-27

**Depends on:** demo-s1 (repo scaffold), demo-s2 (clients working)
**Prerequisite (human):** `.env` populated with real credentials and `scripts/verify.sh` confirmed

## Requirements

This is the strategy implementation — what the demo clip shows Claude Code building.

### Interfaces (non-negotiable per Canon spec)

- `src/types/TradeSignal.ts` implements the exact TradeSignal interface from the demo doc
- `src/types/RiskInterface.ts` implements the RiskInterface with portfolio-level position checks

### Strategy: Sports Arb Scanner

- `src/strategies/sports-arb/scanner.ts` — polls sportsbooks every 5-30 seconds (configurable),
  fetches matching Polymarket sports markets, computes implied probability delta
- `src/strategies/sports-arb/signal.ts` — converts a detected edge into a TradeSignal when
  delta > `MIN_EDGE` (default 0.03 = 3%)
- `src/strategies/sports-arb/risk.ts` — implements RiskInterface checks:
  - Position never >5% of portfolio
  - No new signal if daily loss >2% of portfolio
  - No signal on markets within 60 seconds of resolution

### Dry-Run Runner

- `src/runner.ts` — the standalone executable Node script
  - Reads `.env` for credentials
  - Loads config from `.canon/config.yaml`
  - Runs the decision loop (poll → scan → signal → risk check → log)
  - **Dry-run only**: logs decisions to `.canon/execution/YYYY-MM-DD.jsonl`, never places orders
  - Each log entry is a structured JSON line (schema below)
  - Runs until `Ctrl+C` (SIGINT handler flushes and exits cleanly)

### Decision log schema (`.canon/execution/YYYY-MM-DD.jsonl`)

```json
{
  "ts": "2026-03-05T14:23:01Z",
  "automation_id": "sports-arb-v1",
  "signal": {
    "market": { "conditionId": "...", "question": "Warriors vs Celtics" },
    "direction": "buy_yes",
    "size": 100,
    "confidence": 0.82,
    "urgency": "immediate"
  },
  "risk_passed": true,
  "action": "DRY_RUN_SKIP",
  "reasoning": "Edge: 4.2% (sportsbook 0.62 vs Polymarket 0.58)"
}
```

### Tests

- `src/__tests__/scanner.test.ts` — unit tests for scanner edge detection logic (mocked clients)
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

### Agent workflow (the demo story)

1. **Load Canon:** AGENTS.md loads `.canon/agents/` and `.canon/skills/`. Worker reads the
   plan and uses the **market-analyst** persona to understand the sports arb edge from the
   spec (`AUTO_Arbitrage.md § Sports Arbitrage on Polymarket`).

2. **Market Analyst produces analysis:** Documents the strategy rationale inline in the code
   as structured comments — why 3% minimum edge, why 5-30 second poll interval, which sports
   markets to target.

3. **Dev agent implements:** Using `dev.md` persona + `canon-conventions.md` skill, writes
   TypeScript following domain layering: Types → Clients (already done in S2) → Strategy →
   Runner.

4. **Ralph Loop iterates:** `.canon/ralph.yaml` defines the 4 automated checks. The loop
   runs until all pass or max_iterations (5) is hit. Typical flow: 2-3 cycles to get
   types, lint, tests all green.

### Domain layering order

```
src/types/TradeSignal.ts         ← Layer 1: Types (no imports from higher layers)
src/types/RiskInterface.ts       ← Layer 1: Types
src/strategies/sports-arb/scanner.ts   ← Layer 3: Service (imports clients + types)
src/strategies/sports-arb/signal.ts    ← Layer 3: Service
src/strategies/sports-arb/risk.ts      ← Layer 3: Service
src/runner.ts                    ← Layer 5: Runtime (imports everything, entry point)
```

### Scanner poll logic

```typescript
// Pseudo-code — Dev agent fleshes this out
async function scanOnce(): Promise<TradeSignal[]> {
  const [bookOdds, pmMarkets] = await Promise.all([
    fetchOdds('basketball_nba'),
    fetchSportsMarkets(),  // pmxt filter for sports
  ]);
  return bookOdds
    .flatMap(game => matchToPolymarket(game, pmMarkets))
    .filter(({ edge }) => edge > MIN_EDGE)
    .map(({ market, direction, edge }) => buildSignal(market, direction, edge));
}
```

## Files to touch

All files in `/Users/cerratoa/dega/sports-arb/`.

| File | Change |
|------|--------|
| `src/types/TradeSignal.ts` | Create — exact interface from demo doc |
| `src/types/RiskInterface.ts` | Create — portfolio checks interface |
| `src/strategies/sports-arb/scanner.ts` | Create — poll + edge detection |
| `src/strategies/sports-arb/signal.ts` | Create — TradeSignal builder |
| `src/strategies/sports-arb/risk.ts` | Create — RiskInterface implementation |
| `src/runner.ts` | Create — dry-run loop, SIGINT handler, JSONL logger |
| `src/__tests__/scanner.test.ts` | Create — edge detection unit tests |
| `src/__tests__/signal.test.ts` | Create — signal generation tests |
| `src/__tests__/risk.test.ts` | Create — risk check tests |

## Risks and open questions

- **Polymarket sports market discovery:** The scanner needs to find sports markets on Polymarket
  by name/team. The query strategy (fuzzy match or structured search via pmxt) may need tuning.
  If no live game is found at demo time, the runner should log "no markets found" gracefully
  rather than crash.
- **Sportsbook ↔ Polymarket matching:** Matching "Warriors vs Celtics" in The Odds API to
  Polymarket's market question text is the hardest part of the scanner. The implementation
  should use team names as the match key and log unmatched games.
- **Clock during demo:** Live NBA games run Feb-April 2026. There will be games on March 5.
  Dry-run should work even if no edge is found — log "scanning, no edge detected" entries.

## Progress log

- [x] Create `src/types/TradeSignal.ts`
- [x] Create `src/types/RiskInterface.ts`
- [x] Create `src/strategies/sports-arb/scanner.ts`
- [x] Create `src/strategies/sports-arb/signal.ts`
- [x] Create `src/strategies/sports-arb/risk.ts`
- [x] Create `src/runner.ts` with dry-run loop and JSONL logger
- [x] Create `src/__tests__/scanner.test.ts`
- [x] Create `src/__tests__/signal.test.ts`
- [x] Create `src/__tests__/risk.test.ts`
- [x] Run `pnpm exec tsc --noEmit` — zero errors
- [x] Run `pnpm exec oxlint src/` — zero warnings
- [x] Run `pnpm exec vitest run` — all tests pass
- [x] Manual smoke: `node --env-file=.env src/runner.ts` writes at least one `.canon/execution/*.jsonl` entry

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Dry-run only (no live orders) | Paper trading with testnet, live with tiny size | Demo doc specifies dry-run; no capital at risk; first results same day |
| JSONL decision log format | JSON file, SQLite, console only | Matches `.canon/execution/` convention; agent-readable; append-only safe |
| The Odds API as sportsbook oracle | Pinnacle direct, DraftKings API | Already decided in S2; consistent oracle source |
| Named function scanner (not class) | Scanner class | Consistent with S2 client design; easier to test |

## Completion criteria

- [x] `pnpm exec tsc --noEmit` exits 0
- [x] `pnpm exec oxlint src/` exits 0
- [x] `pnpm exec vitest run` exits 0 (all tests pass)
- [x] `src/types/TradeSignal.ts` implements all fields from the demo doc spec
- [x] `src/types/RiskInterface.ts` exported interface is non-empty
- [x] `src/runner.ts` is a standalone executable that accepts `--dry-run` flag
- [x] At least one `.canon/execution/*.jsonl` entry written after a manual smoke test run
