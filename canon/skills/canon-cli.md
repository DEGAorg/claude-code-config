---
name: canon-cli
description: Command reference for the Canon CLI — agent-callable trading tools for Polymarket
version: 0.0.0
domain: tools
requires: [polymarket]
tools: [canon-cli]
---

# Canon CLI — Agent-Callable Trading Tools

## Context

Load this skill when the user asks to interact with Polymarket — searching
markets, checking positions, placing orders, or monitoring a portfolio.
The Canon CLI wraps Polymarket APIs into shell commands that return
structured JSON.

## How to Use

Call `canon-cli` via Bash. Parse the JSON response to extract data.

```bash
canon-cli <command> [subcommand] [options]
```

### Output format

Every response is a JSON envelope on stdout:

```json
{"ok": true, "data": <result>}
```

Errors go to stderr with exit code 1:

```json
{"ok": false, "error": "<message>"}
```

Add `--pretty` to any command for indented JSON (human-readable).

### Authentication

Read-only commands (`market`, `help`) work without auth.
Write commands (`position`, `balance`, `order`, `kill`) require:

```bash
export POLYMARKET_PRIVATE_KEY=<private-key>
```

Missing auth produces a clear error — never a silent failure.

## Command Reference

### market search

Search for markets by keyword. No auth required.

```bash
canon-cli market search "bitcoin"
canon-cli market search NBA playoffs
```

Returns: array of matching market objects.

```json
{"ok": true, "data": [{"conditionId": "0x...", "question": "Will Bitcoin hit $100k?", "outcomes": ["Yes", "No"], "volume": 1500000}]}
```

### market price

Fetch current price for a market. No auth required.

```bash
canon-cli market price <condition-id>
```

Returns: price object with outcome prices.

```json
{"ok": true, "data": {"conditionId": "0x...", "outcomes": [{"label": "Yes", "price": 0.65}, {"label": "No", "price": 0.35}]}}
```

### market orderbook

Fetch order book for a token. No auth required.

```bash
canon-cli market orderbook <token-id>
```

Returns: bids and asks arrays.

```json
{"ok": true, "data": {"bids": [{"price": 0.64, "size": 500}], "asks": [{"price": 0.66, "size": 300}]}}
```

### market ohlcv

Fetch OHLCV candlestick data for a token. No auth required.

```bash
canon-cli market ohlcv <token-id>
canon-cli market ohlcv <token-id> --timeframe 1h
```

Returns: array of candle objects.

```json
{"ok": true, "data": [{"open": 0.60, "high": 0.68, "low": 0.58, "close": 0.65, "volume": 12000, "timestamp": 1713100800}]}
```

### position list

List all open positions with PnL summary. Auth required.

```bash
canon-cli position list
```

Returns: positions array and portfolio summary.

```json
{
  "ok": true,
  "data": {
    "positions": [
      {
        "marketId": "0x...",
        "outcomeId": "0x...",
        "outcomeLabel": "Yes",
        "size": 100,
        "entryPrice": 0.45,
        "currentPrice": 0.65,
        "unrealizedPnL": 20.0
      }
    ],
    "summary": {
      "totalValue": 1500.0,
      "dailyPnL": 42.5,
      "positionCount": 3
    }
  }
}
```

### balance

Fetch wallet balance. Auth required. No subcommands.

```bash
canon-cli balance
```

Returns: array of currency balances.

```json
{"ok": true, "data": [{"currency": "USDC", "total": 5000.0, "available": 3500.0, "locked": 1500.0}]}
```

### order create

Place a new order. Auth required.

```bash
canon-cli order create \
  --token-id <id> \
  --side buy \
  --size 50 \
  --price 0.45 \
  --type limit \
  --market-id <id>
```

Required flags: `--token-id`, `--side` (buy|sell), `--size` (>0), `--price` (0-1).
Optional flags: `--type` (market|limit, default: limit), `--market-id`.

Returns: order confirmation object.

```json
{"ok": true, "data": {"orderId": "abc123", "status": "placed", "tokenId": "0x...", "side": "buy", "size": 50, "price": 0.45}}
```

### order cancel

Cancel a specific order. Auth required.

```bash
canon-cli order cancel <order-id>
```

Returns: cancellation result.

```json
{"ok": true, "data": {"orderId": "abc123", "status": "cancelled"}}
```

### order list

List recent trades. Auth required.

```bash
canon-cli order list
canon-cli order list --market-id <id> --limit 10
```

Optional flags: `--market-id` (filter by market), `--limit` (max results).

Returns: array of trade objects.

```json
{"ok": true, "data": [{"orderId": "abc123", "side": "buy", "size": 50, "price": 0.45, "status": "filled", "timestamp": 1713100800}]}
```

### kill

Cancel all open orders (kill switch). Auth required.
Without `--yes`, performs a dry run showing what would be cancelled.

```bash
# Dry run — inspect open orders first
canon-cli kill

# Execute — cancel all open orders
canon-cli kill --yes
```

Dry-run response:

```json
{"ok": true, "data": {"dryRun": true, "orderCount": 3, "orders": [...], "message": "Found 3 open order(s). Re-run with --yes to cancel all."}}
```

Execution response:

```json
{"ok": true, "data": {"cancelled": ["id1", "id2"], "failed": []}}
```

No open orders:

```json
{"ok": true, "data": {"cancelled": [], "failed": [], "message": "No open orders"}}
```

### help

List available skills or show skill details. No auth required.

```bash
# List all skills
canon-cli help

# Show details for a specific skill
canon-cli help polymarket
```

List response:

```json
{"ok": true, "data": {"skills": [{"name": "polymarket", "description": "...", "domain": "platform"}]}}
```

Detail response:

```json
{"ok": true, "data": {"name": "polymarket", "description": "...", "domain": "platform", "version": "1.0.0", "requires": ["prediction-markets"], "tools": ["canon-cli"], "content": "# Polymarket Platform Knowledge\n..."}}
```

## Agent Workflow Examples

### Research a market before trading

```bash
# 1. Find the market
canon-cli market search "Will Biden win 2024"

# 2. Check current price (use conditionId from search)
canon-cli market price 0x1234...

# 3. Check liquidity (use tokenId from price response)
canon-cli market orderbook 0x5678...

# 4. Check price history
canon-cli market ohlcv 0x5678... --timeframe 1d
```

### Place a trade and monitor

```bash
# 1. Check available funds
canon-cli balance

# 2. Place a limit buy order
canon-cli order create --token-id 0x5678... --side buy --size 100 --price 0.45

# 3. Check if it filled
canon-cli order list --limit 1

# 4. Monitor position
canon-cli position list
```

### Emergency: cancel everything

```bash
# 1. See what's open (dry run)
canon-cli kill

# 2. Cancel all
canon-cli kill --yes

# 3. Verify positions
canon-cli position list
```

## Common Mistakes

- **Wrong ID type:** `market price` takes a condition ID, `market orderbook` and `market ohlcv` take a token ID. These are different identifiers from the search results.
- **Missing --yes on kill:** Without `--yes`, `kill` only lists orders (dry run). Always inspect before confirming.
- **Price range:** `--price` for orders must be between 0 and 1 (probability). Not a dollar amount.
- **Limit vs market orders:** Default is `limit`. Use `--type market` only when speed matters more than price. Limit orders avoid taker fees.
