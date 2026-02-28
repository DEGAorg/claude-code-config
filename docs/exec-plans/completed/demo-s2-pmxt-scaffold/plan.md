# Plan: Demo S2 — pmxt + Sportsbook API Scaffolding

**Status:** In progress
**Created:** 2026-02-27

**Depends on:** demo-s1-strategy-repo (repo must exist with TypeScript scaffold)

## Requirements

- pmxt (or the Polymarket CLOB client as fallback) is installed in the strategy repo
- A typed TypeScript wrapper `src/clients/polymarket.ts` provides `fetchMarketPrice()` and
  `fetchOrderBook()` — no raw SDK calls outside this module
- A typed TypeScript wrapper `src/clients/sportsbook.ts` provides `fetchOdds(sport, game)` via
  The Odds API — no raw HTTP outside this module
- A verification script `scripts/verify-connections.ts` calls both clients and prints:
  - Polymarket: sample market name + current YES/NO prices
  - Sportsbook: one live NBA or NFL game + current moneyline odds
- `scripts/verify.sh` runs the verification script with `tsx` and exits 0 on success
- All TypeScript in `src/clients/` passes `tsc --noEmit` and `oxlint`
- `.env.example` is updated to include `THE_ODDS_API_KEY` if not already present
- A `README.md` section "Verify connections" documents the one-line command

**Note on live verification:** Running `scripts/verify.sh` with real credentials is a human
step requiring `.env` to be populated. The plan ends when the tooling is in place and
compiles cleanly. The human confirms live connectivity before demo-s3.

## Approach

### pmxt availability check

The Canon docs reference `pmxtjs` as "CCXT for prediction markets." Before implementing,
verify whether it's published on npm:

```
pnpm dlx npmjs-package-checker pmxtjs
```

**If pmxtjs is not on npm:** Fall back to `@polymarket/clob-client` (Polymarket's official
Node client). The wrapper interface stays the same — only the underlying SDK call differs.
Record the decision in the Decision log.

### Client design

Both clients are thin typed wrappers. They export named functions, not classes, because:
- Strategy code calls them directly
- Mocking in tests is straightforward (`vi.mock('./clients/polymarket')`)

```typescript
// src/clients/polymarket.ts
export async function fetchMarketPrice(conditionId: string): Promise<MarketPrice>
export async function fetchOrderBook(tokenId: string): Promise<OrderBook>

// src/clients/sportsbook.ts
export async function fetchOdds(sport: string, eventId?: string): Promise<SportEvent[]>
```

### Type definitions

New shared types go in `src/types/market.ts` (not TradeSignal — those are S3):

```typescript
interface MarketPrice { conditionId: string; yes: number; no: number; timestamp: Date }
interface OrderBook  { tokenId: string; bids: PriceLevel[]; asks: PriceLevel[] }
interface SportEvent { id: string; homeTeam: string; awayTeam: string; commence: Date;
                       bookmakers: Bookmaker[] }
```

## Files to touch

All files in `/Users/cerratoa/dega/sports-arb/`.

| File | Change |
|------|--------|
| `package.json` | Add pmxtjs (or @polymarket/clob-client as fallback) + tsx as dev dep |
| `src/types/market.ts` | Create — MarketPrice, OrderBook, SportEvent, PriceLevel, Bookmaker |
| `src/clients/polymarket.ts` | Create — typed pmxt/CLOB wrapper |
| `src/clients/sportsbook.ts` | Create — typed Odds API wrapper |
| `scripts/verify-connections.ts` | Create — smoke test both clients |
| `scripts/verify.sh` | Create — `set -euo pipefail; pnpm exec tsx scripts/verify-connections.ts` |
| `README.md` | Create (or update) — setup steps, credential instructions, verify command |
| `.env.example` | Update — add `THE_ODDS_API_KEY=` if missing |

## Risks and open questions

- **pmxtjs not published on npm (P1):** Verify first. If absent, use
  `@polymarket/clob-client` directly. The Odds API is the real/verified sportsbook source.
  The client wrapper abstracts this so S3 is unaffected by which underlying library is used.
- **The Odds API rate limits:** Free tier is 500 requests/month. The verify script uses 1.
  The sports arb scanner in S3 will poll every 5-30 seconds — this requires a paid plan
  (~$10/mo for 10k requests). Note this in README but don't block on it for dry-run demo.
- **Polymarket credentials format:** Private key must be a Polygon EOA private key. Proxy
  address is the CLOB proxy contract. Document exact format in `.env.example`.

## Progress log

- [x] Check if `pmxtjs` is on npm; document result in Decision log
- [x] Install pmxt (or `@polymarket/clob-client` fallback) + `tsx` dev dep
- [x] Create `src/types/market.ts` with MarketPrice, OrderBook, SportEvent types
- [x] Create `src/clients/polymarket.ts` wrapper
- [x] Create `src/clients/sportsbook.ts` wrapper (The Odds API)
- [x] Create `scripts/verify-connections.ts`
- [x] Create `scripts/verify.sh`
- [x] Update `.env.example` with all credential entries and format notes
- [x] Create `README.md` with setup + verify instructions
- [x] Run `pnpm exec tsc --noEmit` — passes
- [x] Run `pnpm exec oxlint src/` — passes

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| **Use pmxtjs v2.18.0** | pmxtjs (canonical), @polymarket/clob-client (official fallback) | pmxtjs is published on npm (v2.18.0, 93 versions, active maintenance). Provides unified prediction market API ("CCXT for prediction markets") covering Polymarket + Kalshi. No need for fallback. |
| The Odds API for sportsbook | Pinnacle API, DraftKings API, Sportradar | The Odds API aggregates multiple books in one call; free tier available; clean JSON REST API |
| Named function exports not classes | Class-based client | Easier to mock in vitest; no `this` binding; strategy code stays functional |

## Completion criteria

- [x] `pnpm install` exits 0 (all dependencies installed)
- [x] `pnpm exec tsc --noEmit` exits 0
- [x] `pnpm exec oxlint src/` exits 0
- [x] `src/clients/polymarket.ts` exports `fetchMarketPrice` and `fetchOrderBook`
- [x] `src/clients/sportsbook.ts` exports `fetchOdds`
- [x] `scripts/verify.sh` exists and is executable
- [x] `.env.example` documents all required credential keys with format notes
- [x] README "Verify connections" section exists
