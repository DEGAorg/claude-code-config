---
name: polymarket
description: Polymarket-specific knowledge — API, fees, resolution, mechanics
version: 1.0.0
domain: platform
requires: [prediction-markets]
tools: [canon_market, canon_position]
---

# Polymarket Platform Knowledge

## Context
Load this skill when building strategies that trade on Polymarket specifically.
Polymarket has platform-specific mechanics that affect strategy design.

## Core Knowledge

### Platform Mechanics
- Blockchain-based (Polygon) — trades are on-chain transactions
- CLOB (Central Limit Order Book) model via CTF Exchange
- USDC-denominated — all positions and P&L in USDC
- Conditional tokens: ERC-1155 tokens representing outcome shares

### Fee Structure
- No trading fees for makers (limit orders that add liquidity)
- Taker fee: ~1-2% (market orders that remove liquidity)
- Strategy implication: Prefer limit orders to avoid taker fees
- Withdrawal fees: Polygon gas costs (minimal)

### API Access (via pmxt)
- REST API for market data, order placement, position tracking
- WebSocket for real-time order book and trade updates
- Rate limits: Respect rate limits to avoid API bans
- Authentication: API key-based (CLOB API key)

### Resolution Process
- Oracle-based resolution (UMA optimistic oracle)
- Resolution proposals can be disputed (24-48 hour window)
- Edge case: Disputed resolutions can delay payouts significantly
- "N/A" resolution possible — returns all shares to $0.50

### Market Categories (relevant to NBA Playoffs hackathon)
- Sports: Individual games, series outcomes, player props, MVP
- Politics: Elections, policy outcomes, appointments
- Crypto: Price targets, protocol events, regulatory actions
- Current events: Science, entertainment, weather

## Decision Frameworks

### Order Type Selection
- Limit order: When you have time and want to avoid fees → Use for most trades
- Market order: When speed matters (breaking news, rapid price movement) → Accept taker fee
- GTC (Good Till Cancelled): Default for strategies that wait for fills
- FOK (Fill or Kill): When partial fills would unbalance your position

### Monitoring Positions
- Check positions via `canon_position --action list`
- Monitor P&L via `canon_position --action pnl`
- Watch for resolution approaching — exit or hold decision
- Set alerts for price movements >10% (potential information event)

## Common Mistakes
- **Ignoring gas costs:** Polygon gas is low but not zero — frequent small trades add up
- **Market order slippage:** Large market orders in thin books get terrible fills
- **Missing resolution disputes:** Disputed resolutions can lock capital for weeks
- **API rate limiting:** Aggressive polling gets your key throttled — use WebSocket for live data
