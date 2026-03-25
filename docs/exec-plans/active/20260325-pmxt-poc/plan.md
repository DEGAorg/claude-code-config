# Plan: POC — pmxt Polymarket Validation

**Status:** Draft
**Created:** 2026-03-25

## Requirements

- Validate `pmxtjs` (v2.22.1) TypeScript SDK against Polymarket as the exchange adapter for Canon MCP Server
- Test all P0 methods: `fetchMarkets`, `fetchPositions`, `fetchBalance`, `createOrder`, `fetchOHLCV`
- Test P1 methods if time permits: `fetchEvents`, `cancelOrder`, `fetchTrades`, `watchOrderBook`, `watchTrades`
- Document response shapes, auth requirements, quirks, and rate limits
- Produce a **go/no-go decision** on pmxt for Canon
- POC lives in `poc/pmxt-poc/` within this repo (TypeScript, Node 22, ESM)
- Source spec: `../../canon-docs/planning/poc-pmxt.md`

## Approach

### Key findings from investigation

- **Package name:** `pmxtjs` on npm (not `pmxt` — the spec has an outdated name)
- **Architecture:** Client SDK (`pmxtjs`) talks to a local sidecar server (`pmxt-core`) via HTTP. The sidecar wraps exchange-specific SDKs (@polymarket/clob-client, ethers, etc.)
- **Auto-start:** The SDK auto-starts the sidecar via `pmxt-ensure-server` from `pmxt-core`. Lock file at `~/.pmxt/server.lock`
- **Auth:** `PolymarketOptions` accepts `privateKey`, `proxyAddress`, `signatureType` — all optional. Read-only methods (fetchMarkets, fetchOHLCV) likely work without auth
- **Import:** `import { Polymarket } from "pmxtjs"` or `import pmxt from "pmxtjs"`
- **All P0+P1 methods exist** in the type definitions on `Exchange` base class

### Test strategy

1. **Read-only first (no auth):** fetchMarkets, fetchEvents, fetchOHLCV, fetchOrderBook — these should work without a private key
2. **Auth-required (wallet needed):** fetchPositions, fetchBalance, fetchTrades — need a Polymarket wallet address
3. **Write operations (last, careful):** createOrder with minimum amount, cancelOrder immediately after
4. **WebSocket methods:** watchOrderBook, watchTrades — test with short timeout

### Risk: sidecar server

pmxt-core is a substantial dependency (Express server, ethers, @polymarket/clob-client). If the sidecar fails to start or has compatibility issues, the entire POC fails. Step 2 explicitly validates the sidecar before testing any exchange methods.

## Files to touch

| File | Change |
|------|--------|
| `poc/pmxt-poc/package.json` | Node 22 ESM project with pmxtjs + pmxt-core deps |
| `poc/pmxt-poc/tsconfig.json` | Strict TypeScript config |
| `poc/pmxt-poc/.env.example` | Template for POLYMARKET_PRIVATE_KEY, PROXY_ADDRESS |
| `poc/pmxt-poc/src/test-read-only.ts` | P0 read-only: fetchMarkets, fetchOHLCV + P1 fetchEvents |
| `poc/pmxt-poc/src/test-auth.ts` | P0 auth-required: fetchPositions, fetchBalance, fetchTrades |
| `poc/pmxt-poc/src/test-orders.ts` | P0 write: createOrder + P1 cancelOrder |
| `poc/pmxt-poc/src/test-websocket.ts` | P1: watchOrderBook, watchTrades |
| `poc/pmxt-poc/src/run-all.ts` | Runner that executes tests in order with pass/fail summary |
| `poc/pmxt-poc/RESULTS.md` | Go/no-go decision with method-by-method results |
| `.gitignore` | Add `poc/pmxt-poc/node_modules/`, `poc/pmxt-poc/.env` |

## Risks and open questions

- **Sidecar startup:** pmxt-core may require global install or specific Node version. Mitigated by explicit validation step
- **Auth for read-only:** fetchPositions/fetchBalance require a wallet address, not necessarily a private key — need to test if a public address suffices
- **createOrder safety:** Must use smallest possible amount. Consider testing only with buildOrder (dry-run) if no testnet available
- **Rate limits:** Polymarket may rate-limit. Document any throttling encountered
- **KalshiDemo:** A `KalshiDemo` class exists in pmxtjs — could serve as a safe testnet alternative for order testing if Polymarket has no sandbox

## Progress log

- [x] Scaffold project: package.json, tsconfig.json, .env.example, .gitignore update
- [x] Validate sidecar: install deps, verify pmxt-core server starts and responds to health check (deps: 1)
- [x] Test read-only methods: fetchMarkets, fetchEvents, fetchOHLCV, fetchOrderBook — no auth needed (deps: 2)
- [x] Test auth methods: fetchPositions, fetchBalance, fetchMyTrades — requires wallet config (deps: 3)
- [x] Test write operations: buildOrder (dry-run), createOrder + cancelOrder if safe (deps: 4)
- [x] Test WebSocket methods: watchOrderBook, watchTrades with 10s timeout (deps: 3)
- [x] Write run-all.ts runner with structured pass/fail output (deps: 3, 4, 5, 6)
- [ ] Write RESULTS.md with go/no-go decision, response shapes, auth requirements, quirks (deps: 7)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Use `pmxtjs` not `pmxt` | `pmxt` (0.1.0 placeholder) | `pmxtjs` is the active package (v2.22.1, 108 releases, published 2 days ago). `pmxt` on npm is a 32KB placeholder with no deps |
| Split tests by auth level | Single test file | Isolates read-only validation from auth-dependent tests. Read-only passing alone is a partial go (see pass/fail criteria in spec) |
| Include buildOrder before createOrder | Jump straight to createOrder | buildOrder is a dry-run that returns the signed payload without submitting. Safer first step for write validation |
| Test in poc/ subdirectory | Separate repo | Keeps POC close to the harness config, easy to PR and review. poc/ is gitignored for node_modules |

## Completion criteria

- [ ] All P0 read-only methods tested with documented response shapes
- [ ] Auth requirements documented (which methods need private key vs public address vs nothing)
- [ ] createOrder tested or explicitly documented why it was skipped (no testnet / safety)
- [ ] RESULTS.md contains go/no-go decision with method-by-method pass/fail table
- [ ] All code runs with `npx tsx src/run-all.ts` from poc/pmxt-poc/
