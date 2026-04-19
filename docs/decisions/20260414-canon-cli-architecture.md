# Canon CLI Architecture — Discovery & Decision

**Date:** 2026-04-14
**Status:** Draft — pending Alberto's feedback
**Context:** Issue #104 (Canon CLI register + help + wallet), Canon TUI integration

---

## Current State

### What exists

| Layer | What | Location | Status |
|-------|------|----------|--------|
| Shell launchers | `canon.sh`, `canon-runner.sh`, `canon-scaffold.sh` | `scripts/` | Working |
| Agent commands | `/canon-start`, `/develop`, `/discover`, `/register`, `/ralph-cycle`, `/quick-dev` | `canon/commands/` | Working (agent-only) |
| TypeScript modules | `client-polymarket.ts`, `runner.ts`, `order-executor.ts`, `position-manager.ts`, `kill-switch.ts`, `state.ts`, `sidecar.ts` | `canon/templates/` | Working (import-only) |
| Type interfaces | `TradeSignal.ts`, `RiskInterface.ts` | `canon/templates/types/` | Working |
| Agent personas | dev, market-analyst, strategy-architect, risk-analyst, qa, deployment-ops | `canon/agents/` | Working |
| Skills (knowledge) | prediction-markets, polymarket, risk-management, strategy-patterns, backtesting, arena-tracking | `canon/skills/` | Working |

### What AGENTS.md promises but does NOT exist

These 7 tools are listed as "Available Tools (MCP)" but none are implemented:

| Tool | Described Purpose | Actual Status |
|------|-------------------|---------------|
| `canon_init` | Scaffold strategy from template | **Shell script** `canon-scaffold.sh` exists, but no CLI interface |
| `canon_register` | Register strategy on Arena | **Not implemented** — `/register` command references it but it doesn't exist |
| `canon_test` | Run against historical data | **Not implemented** |
| `canon_market` | Query market data | **TypeScript functions** exist (`fetchMarketPrice`, `searchMarkets`, `fetchOrderBook`) but no CLI |
| `canon_position` | Check positions, P&L | **TypeScript functions** exist (`fetchPortfolio`, `calculatePnL`) but no CLI |
| `canon_ralph` | Run Ralph Loop iteration | **Agent workflow** via `/ralph-cycle`, not a tool |
| `canon_help` | Get contextual guidance | **Not implemented** |

### The Gap

Canon has two layers that don't connect:

```
Agent Layer (md instructions)     TypeScript Layer (runtime code)
─────────────────────────────     ──────────────────────────────
/register says:                   position-manager.ts exports:
  "canon_position --action pnl"     fetchPortfolio()
  → DOES NOT EXIST                  calculateUnrealizedPnL()
                                    → No CLI wraps these
```

The agent commands (.md files) tell the agent to call CLI tools that don't exist.
The TypeScript modules have the functionality but are only accessible via `import`.

---

## What Needs to Change

### Principle: CLI is the bridge between agents and TypeScript

The Canon CLI should be a **thin executable** that wraps the TypeScript template
modules and exposes them as shell commands. Agents call the CLI; the CLI calls
the TypeScript; results come back as structured output the agent can parse.

```
Canon TUI / Agent Session
    ↓ calls
Canon CLI (executable)
    ↓ imports
TypeScript modules (templates/)
    ↓ calls
Polymarket API (via pmxtjs)
```

### What the CLI needs to do

| Command | Wraps | Output |
|---------|-------|--------|
| `canon market search <query>` | `searchMarkets()` from client-polymarket.ts | JSON: markets matching query |
| `canon market price <token-id>` | `fetchMarketPrice()` | JSON: current price, volume |
| `canon market orderbook <token-id>` | `fetchOrderBook()` | JSON: bids/asks |
| `canon position list` | `fetchPortfolio()` from position-manager.ts | JSON: open positions |
| `canon position pnl` | `calculateUnrealizedPnL()` + `calculateRealizedPnL()` | JSON: P&L breakdown |
| `canon balance` | `fetchBalance()` from client-polymarket.ts | JSON: wallet balance |
| `canon order create <params>` | `submitOrder()` from order-executor.ts | JSON: order confirmation |
| `canon order cancel <id>` | `cancelOrder()` from client-polymarket.ts | JSON: cancellation status |
| `canon order list` | `fetchMyTrades()` from client-polymarket.ts | JSON: trade history |
| `canon kill` | `cancelAllOrders()` from kill-switch.ts | JSON: cancellation results |
| `canon help [topic]` | Reads skills/*.md | Formatted text |

### What the CLI does NOT do

- **Strategy logic** — that's the user's `src/strategy.ts`
- **Agent orchestration** — that's the .md commands (`/develop`, `/register`)
- **Scaffolding** — that stays in `canon-scaffold.sh`
- **Running the strategy loop** — that stays in `canon-runner.sh`
- **Arena registration** — blocked on DEGA Rank, deferred

### What the .md commands should change

After the CLI exists, the agent commands should reference real CLI calls:

```markdown
# Before (broken)
canon_position --action portfolio

# After (works)
canon position list
```

---

## Implementation Approach

### Single entry point: `canon/cli/canon.ts`

A TypeScript CLI using a minimal arg parser (no heavy framework). Compiles to
a single executable via `tsx` or `esbuild`. Reuses all existing template modules
via direct import.

### Directory structure

```
canon/cli/
├── canon.ts              # Entry point — arg parser, routes to subcommands
├── commands/
│   ├── market.ts         # canon market {search,price,orderbook}
│   ├── position.ts       # canon position {list,pnl}
│   ├── balance.ts        # canon balance
│   ├── order.ts          # canon order {create,cancel,list}
│   ├── kill.ts           # canon kill
│   └── help.ts           # canon help [topic]
├── output.ts             # JSON/table output formatter
└── config.ts             # Read wallet key from env/config
```

### Auth

- `POLYMARKET_PRIVATE_KEY` env var (same as integration tests)
- Read-only commands (market, help) work without auth
- Write commands (order, kill) require auth and fail fast with clear message

### Output

All commands output JSON by default. Agent-friendly. The TUI can parse and
render it. Add `--pretty` flag for human-readable tables.

---

## What's NOT in scope

- `canon register` — blocked on DEGA Rank (Carlos, Apr 27)
- `canon test` (backtesting) — separate milestone, not needed for hackathon MVP
- `canon ralph` — stays as agent workflow, not a CLI tool
- Arena API client — depends on DEGA Rank existing

---

## Decisions (resolved 2026-04-14)

1. **CLI lives in this repo** at `canon/cli/`. Single source of truth.
2. **Installed via `/apply-core`** — the existing single-command install mechanism.
   `/apply-core` already installs Canon Bootstrap scripts to `~/.degacore/scripts/`.
   The CLI gets added as a new component: compiled and placed at
   `~/.degacore/bin/canon-cli` (or similar), available on PATH.
3. **Agent-accessible** — the agent discovers and calls the CLI tools directly.
   The .md commands (skills/commands) teach the agent which CLI subcommands exist
   and what they return. The user speaks naturally, the agent locates the right
   tool, calls it, gets structured output, and presents it. Same pattern as
   the existing shell scripts but with typed JSON output.
