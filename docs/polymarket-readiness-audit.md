# Canon x Polymarket Readiness Audit

**Date:** 2026-04-13
**Hackathon kickoff:** 2026-04-18 (5 days)
**Purpose:** Assess whether Canon can read and take actions on Polymarket today, identify all gaps, and define what's needed to be automation-ready.

---

## Executive Summary

Canon has **validated SDK access** to Polymarket (pmxt POC passed all 10 methods) and has **strategy design workflows** (`/discover`, `/develop`, `/register`). Two reference strategy repos exist (`sports-arb`, `nba-strategy`). However, **no end-to-end live trading pipeline has been tested**. The critical gaps are: no CLI tools for trading operations, no live order execution test, no wallet/signer management, no real-time WebSocket runner, and no Arena MVP for tracking.

Note: Canon uses **CLI commands and skills** (in this repo), not MCP servers. Commands like `/canon-init`, `/discover`, `/develop` are skill files that agents execute. References to `canon_market`, `canon_position` etc. in older docs referred to planned MCP tools -- these are now CLI commands/skills instead.

**Verdict: Canon can READ from Polymarket today. Canon CANNOT take automated actions (trade) on Polymarket without additional work.**

---

## What Works Today

### 1. SDK Validation (pmxt POC) -- DONE

| Method | Status | Auth |
|--------|--------|------|
| `fetchMarkets()` | PASS | None |
| `fetchEvents()` | PASS | None |
| `fetchOHLCV()` | PASS (workaround) | None |
| `fetchOrderBook()` | PASS | None |
| `watchOrderBook()` | PASS (workaround) | None |
| `watchTrades()` | PASS (workaround) | None |
| `fetchPositions()` | PASS | privateKey |
| `fetchBalance()` | PASS | privateKey |
| `createOrder()` | PASS | privateKey |
| `cancelOrder()` | PASS | privateKey |
| `fetchMyTrades()` | PASS | privateKey |

- **SDK:** pmxtjs v2.22.1 (validated 2026-03-25)
- **Known bug:** Header-clobbering in 3 methods (fetchOHLCV, watchOrderBook, watchTrades) -- workaround: direct sidecar HTTP
- **Sidecar requirement:** pmxt-core must be running locally (auto-starts from SDK)
- **Decision:** GO -- proceed with pmxt as exchange adapter

### 2. Polymarket Client Template -- DONE

`canon/templates/client-polymarket.ts` provides:
- `fetchMarketPrice(conditionId)` -- YES/NO price snapshot
- `searchMarkets(query)` -- market discovery with binary filtering
- `fetchOrderBook(tokenId)` -- order book depth

Missing from template: `createOrder`, `cancelOrder`, `fetchPositions`, `fetchBalance`, `fetchMyTrades`

### 3. Reference Implementations -- DONE

| Repo | SDK Version | What It Does |
|------|-------------|--------------|
| `sports-arb` | pmxtjs 2.18.0 | Cross-market arbitrage (Polymarket vs sportsbook) |
| `nba-strategy` | pmxtjs 1.1.2 | NBA momentum strategy |

Both have: typed Polymarket client, strategy logic, risk management, signal detection, test suites. Neither has been run against live markets with real money.

### 4. Strategy Workflows -- DONE

| Command | Purpose | Status |
|---------|---------|--------|
| `/discover` | Market scan, opportunity selection, strategy design | Implemented |
| `/develop` | Scaffold, implement, test, iterate | Implemented |
| `/register` | Risk review, pre-registration, Arena tracking | Implemented (but Arena doesn't exist yet) |
| `/canon-start` | Entry point, phase detection | Implemented |
| `/quick-dev` | Lightweight changes | Implemented |

### 5. Domain Knowledge (Skills) -- DONE

All 8 Canon skills are written: prediction-markets, polymarket, strategy-patterns, risk-management, backtesting, arena-tracking, orchestrator, canon-conventions.

### 6. Agent Personas -- DONE

All 6 personas defined: strategy-architect, market-analyst, dev, qa, risk-analyst, deployment-ops.

---

## What's Missing -- Gaps Blocking Live Automation

### GAP 1: No CLI Commands for Trading Operations

**Impact: CRITICAL**

Existing Canon CLI commands (`/discover`, `/develop`, `/register`, `/canon-start`) define workflows but **none of them directly execute trades**. The `/discover` command scans markets and designs strategies. The `/develop` command scaffolds and tests code. The `/register` command does risk review and registration. But there's no command that:

- Places a live order on Polymarket
- Monitors and manages open positions
- Executes a strategy runner loop (poll -> signal -> trade)
- Provides real-time portfolio/P&L view

**What's needed:**
- A CLI command or skill for **live trading** (execute strategy signals as real orders)
- A CLI command or skill for **position management** (list positions, P&L, close positions)
- A CLI command or skill for **market data** (query prices, order books on demand)
- These build on `client-polymarket.ts` but add the orchestration layer

### GAP 2: No Live Order Execution Pipeline

**Impact: CRITICAL**

The POC validated `createOrder()` with a $0.01 limit buy that never fills. No one has:
- Placed a real trade that actually fills
- Managed a live position (monitor, adjust, close)
- Handled order lifecycle (open -> partial fill -> filled)
- Tested error recovery (failed orders, network issues, sidecar crashes)

**What's needed:**
- End-to-end order execution test with real USDC (even $1-5)
- Order lifecycle handler (track status, handle partials, timeout stale orders)
- Error recovery: sidecar restart, rate limit backoff, insufficient balance
- Kill switch: emergency position close

### GAP 3: No Wallet/Signer Management

**Impact: CRITICAL**

Current setup: `POLYMARKET_PRIVATE_KEY` env var. No:
- Wallet creation or import workflow
- USDC balance check before trading
- Token approval flow (ERC-20 approve for CTF Exchange contracts)
- Proxy wallet support tested (email/Magic wallet users)

**What's needed:**
- Document wallet setup (EOA with Polygon USDC.e)
- Token approval script for CTF Exchange contracts:
  - `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` (CTF Exchange)
  - `0xC5d563A36AE78145C45a50134d48A1215220f80a` (Neg Risk CTF Exchange)
  - `0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296` (Neg Risk Adapter)
- Balance validation before order submission
- Private key security (not just env var -- encrypted storage or keyring)

### GAP 4: No Real-time Market Data Runner

**Impact: HIGH**

Strategies need continuous market data (prices, order book changes, trade events). Current state: POC validated WebSocket methods work, but no persistent runner exists.

**What's needed:**
- WebSocket connection manager (connect, heartbeat every 10s, reconnect on drop)
- Price feed aggregator (subscribe to token IDs, emit price updates)
- Order book watcher (maintain local order book state)
- Trade event listener (detect fills, market movements)

### GAP 5: No Arena MVP (Leaderboard/Tracking)

**Impact: HIGH (for hackathon), LOW (for raw automation)**

Arena is the hackathon product -- leaderboard, portfolio tracking, strategy registration. It reads Polymarket on-chain data via the Data API (no auth needed).

**Status:** Not started. Was scheduled for Mar 30 - Apr 6.

**For pure Polymarket automation, Arena is not blocking.** The agent can trade without Arena. Arena is needed for the hackathon competition format.

### GAP 6: No Backtesting Infrastructure

**Impact: MEDIUM**

The `backtesting.md` skill defines methodology but no runner exists. OHLCV data fetch works (via pmxtjs) but there's no:
- Historical data collection/storage
- Backtest runner (simulate strategy against historical prices)
- Result analyzer (win rate, profit factor, drawdown)

### GAP 7: No State Persistence for Positions

**Impact: MEDIUM**

If the agent restarts, it has no local record of open positions. It must re-fetch from Polymarket API. This works for positions (via `fetchPositions`) but doesn't recover:
- Pending order intents (orders that haven't hit the API yet)
- Strategy state (which signals have fired, what phase the strategy is in)
- P&L tracking history

**What's needed:**
- Local state file (JSON or SQLite) for open positions and pending orders
- Reconciliation on startup: compare local state to Polymarket API state
- Strategy checkpoint/resume mechanism

### GAP 8: No Integration Testing

**Impact: MEDIUM**

No test has ever run the full pipeline: discover market -> design strategy -> execute trade -> monitor position -> close position.

**What's needed:**
- Integration test with Polymarket mainnet (no testnet exists)
- Use minimal amounts ($1-5 per trade)
- Test the full lifecycle with at least one strategy

### GAP 9: Client Template Missing Trading Methods

**Impact: LOW (easy fix)**

`canon/templates/client-polymarket.ts` only has read methods. Missing:
- `createOrder(params)` -- place limit/market orders
- `cancelOrder(orderId)` -- cancel open orders
- `fetchPositions()` -- get current positions
- `fetchBalance()` -- get USDC balance
- `fetchMyTrades()` -- get trade history
- `buildOrder(params)` -- dry-run order construction

### GAP 10: pmxtjs Version Drift

**Impact: LOW**

| Location | Version |
|----------|---------|
| POC (validated) | 2.22.1 |
| sports-arb | 2.18.0 |
| nba-strategy | 1.1.2 |
| client template | unspecified (imports from pmxtjs) |

Should pin all to 2.22.1 (the validated version) or later.

---

## Polymarket API Reference (for implementation)

### Authentication

| Level | Headers | Used For |
|-------|---------|----------|
| None | -- | Market data, prices, order books |
| L1 (wallet) | POLY_ADDRESS, POLY_SIGNATURE, POLY_TIMESTAMP, POLY_NONCE | Derive API credentials |
| L2 (trading) | POLY_ADDRESS, POLY_SIGNATURE, POLY_TIMESTAMP, POLY_API_KEY, POLY_PASSPHRASE | Place/cancel orders |

pmxtjs handles auth internally -- just pass `privateKey` to constructor.

### Rate Limits

| API | Limit |
|-----|-------|
| Gamma (markets/events) | 4,000 req/10s general, 500/10s events, 300/10s markets |
| CLOB (trading) | 9,000 req/10s general, 3,500/10s orders (burst), 1,500/10s book/price |
| Data (positions/trades) | 1,000 req/10s general, 200/10s trades, 150/10s positions |

### Key Endpoints (direct API, bypassing pmxtjs if needed)

| Action | Endpoint | Auth |
|--------|----------|------|
| Search markets | `GET gamma-api.polymarket.com/markets?query=X` | None |
| Get order book | `GET clob.polymarket.com/book?token_id=X` | None |
| Get price | `GET clob.polymarket.com/price?token_id=X&side=BUY` | None |
| Price history | `GET clob.polymarket.com/prices-history?token_id=X` | None |
| Place order | `POST clob.polymarket.com/order` | L2 |
| Cancel order | `DELETE clob.polymarket.com/order` | L2 |
| Get positions | `GET data-api.polymarket.com/positions` | None (public) |
| Get trades | `GET data-api.polymarket.com/trades` | None (public) |
| WebSocket market | `wss://ws-subscriptions-clob.polymarket.com/ws/market` | None |
| WebSocket user | `wss://ws-subscriptions-clob.polymarket.com/ws/user` | L2 |

### Blockchain Infrastructure

| Contract | Address |
|----------|---------|
| CTF Exchange | `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` |
| Conditional Tokens | `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045` |
| Neg Risk CTF Exchange | `0xC5d563A36AE78145C45a50134d48A1215220f80a` |
| Neg Risk Adapter | `0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296` |
| USDC.e (collateral) | `0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174` |

### Third-Party MCP Servers (reference only)

These exist in the ecosystem but Canon uses CLI commands/skills, not MCP:

| Project | Tools | Trading |
|---------|-------|---------|
| `@iqai/mcp-polymarket` | 18 tools | Yes |
| `playainetwork/polymarket-mcp` | Trading + portfolio | Yes |
| `guangxiangdebizi/PolyMarket-MCP` | ~10 tools | Read-only |

These can serve as **reference implementations** for what Canon CLI commands should cover.

---

## Legal/Compliance Notes

- Polymarket acquired CFTC-licensed exchange (QCEX) in July 2025
- U.S. platform requires KYC, FCM/brokerage access, Form 1099-DA
- Automated trading allowed but subject to CFTC surveillance
- Bot operators should implement: trade logging, kill switches, position limits, daily loss caps
- **No testnet** -- all API calls hit production mainnet
- Start with $1-5 positions for testing

---

## Priority Action Plan

### P0 -- Must Do Before Hackathon (5 days)

| # | Task | Effort | Blocking |
|---|------|--------|----------|
| 1 | **Extend client template** with trading methods (createOrder, cancelOrder, fetchPositions, fetchBalance) | 2h | Everything below |
| 2 | **Live order execution test** -- place a real $1 limit order, verify fill, check position, close | 2h | Proves the pipeline works |
| 3 | **Wallet setup documentation** -- EOA creation, USDC.e funding, token approvals for CTF contracts | 1h | Participants need this |
| 4 | **Build CLI commands** for trading (`/trade`), position management (`/positions`), market query (`/market`) | 4h | Agents need these to act |
| 5 | **Pin pmxtjs to 2.22.1** across all repos | 30m | Prevents version drift bugs |

### P1 -- Should Do Before Hackathon

| # | Task | Effort | Blocking |
|---|------|--------|----------|
| 6 | **Simple strategy runner** -- loop that polls prices, checks signals, places orders | 4h | Automation demo |
| 7 | **WebSocket price feed** -- persistent connection with heartbeat and reconnect | 3h | Real-time strategies |
| 8 | **State persistence** -- JSON file for open positions and pending orders | 2h | Agent restart recovery |
| 9 | **Kill switch** -- cancel all orders + close all positions on signal | 1h | Safety requirement |

### P2 -- Nice to Have

| # | Task | Effort |
|---|------|--------|
| 10 | Advanced CLI commands (backtest runner, portfolio analytics) | 1-2d |
| 11 | Backtesting runner with OHLCV data | 1d |
| 12 | Arena MVP (leaderboard, portfolio tracking) | 5-7d |
| 13 | Multi-exchange support (Kalshi via pmxtjs) | 1d |

---

## Minimum Viable Polymarket Automation

The absolute minimum to have Canon reading and acting on Polymarket:

```
1. POLYMARKET_PRIVATE_KEY env var set (funded EOA wallet on Polygon)
2. Token approvals done for CTF Exchange contracts
3. client-polymarket.ts extended with createOrder/cancelOrder/fetchPositions
4. A strategy file that:
   a. Calls searchMarkets() or fetchMarketPrice() to find opportunities
   b. Evaluates a signal (price threshold, edge calculation, etc.)
   c. Calls createOrder() when signal fires
   d. Polls fetchPositions() to track the position
   e. Calls createOrder(sell) or cancelOrder() to exit
5. A runner loop (setInterval or cron) that executes the strategy
6. CLI commands (/trade, /positions, /market) so agents can invoke these
```

This can be built in a day. Everything else (Arena, backtesting, WebSocket) is enhancement.

---

## Files Referenced

| File | Purpose |
|------|---------|
| `poc/pmxt-poc/RESULTS.md` | SDK validation results |
| `canon/templates/client-polymarket.ts` | Polymarket client wrapper (read-only) |
| `canon/skills/polymarket.md` | Platform knowledge |
| `canon/skills/prediction-markets.md` | Market fundamentals |
| `canon/commands/discover.md` | Market discovery workflow |
| `canon/commands/register.md` | Strategy registration workflow |
| `data/timeline.json` | Project timeline |
| `dega/sports-arb/src/clients/polymarket.ts` | Reference implementation (v2.18.0) |
| `dega/nba-strategy/src/clients/polymarket.ts` | Reference implementation (v1.1.2) |
