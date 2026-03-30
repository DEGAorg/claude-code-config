# Plan: POC — Polymarket Data API for Third-Party Account Tracking

**Status:** Draft
**Created:** 2026-03-26

## Requirements

- Validate all Polymarket Data API endpoints needed for third-party wallet tracking (no auth required)
- Test `GET /positions`, `/closed-positions`, `/activity`, `/value`, `/trades` on `data-api.polymarket.com`
- Test `GET /public-profile` on `gamma-api.polymarket.com`
- Document response shapes, pagination behavior, rate limits, and quirks
- Produce structured pass/fail output matching pmxt-poc conventions
- Write RESULTS.md with GO/NO-GO decision and Canon integration recommendations
- Location: `poc/data-api-poc/` (sibling to `poc/pmxt-poc/`)

## Approach

Pure HTTP POC — no SDK, just `fetch()` against the public APIs. Each test file validates one endpoint, logs the response shape, and checks for expected fields. A runner script (`run-all.ts`) executes all tests sequentially and produces a summary table.

Use a known active Polymarket wallet address for testing. The POC will discover one dynamically by fetching a popular market's trades and extracting a wallet from the response.

Tech stack matches pmxt-poc: Node 22, TypeScript 5.8.2, ESM, tsx runner.

## Files to touch

| File | Change |
|------|--------|
| `poc/data-api-poc/package.json` | Create — Node 22 ESM project, tsx + typescript devDeps only |
| `poc/data-api-poc/tsconfig.json` | Create — strict config matching pmxt-poc |
| `poc/data-api-poc/src/common.ts` | Create — shared fetch wrapper, types, test wallet discovery |
| `poc/data-api-poc/src/test-positions.ts` | Create — GET /positions, pagination, filtering by market/event |
| `poc/data-api-poc/src/test-closed-positions.ts` | Create — GET /closed-positions, sorting, pagination |
| `poc/data-api-poc/src/test-activity.ts` | Create — GET /activity, type filtering, date ranges |
| `poc/data-api-poc/src/test-value.ts` | Create — GET /value, market filtering |
| `poc/data-api-poc/src/test-trades.ts` | Create — GET /trades, side filtering, pagination |
| `poc/data-api-poc/src/test-profile.ts` | Create — GET /public-profile (gamma-api), field validation |
| `poc/data-api-poc/src/run-all.ts` | Create — runner with structured pass/fail summary |
| `poc/data-api-poc/RESULTS.md` | Create — findings, response shapes, recommendations |

## Risks and open questions

- Rate limits on Data API are undocumented — POC will discover them empirically (add delays between requests)
- Need a test wallet address with known positions — will discover from /trades on a popular market
- 401 errors listed in docs despite "no auth" claim — may indicate some endpoints need API key for high volume

## Progress log

- [ ] Scaffold project: package.json, tsconfig.json, npm install
- [ ] Write common.ts — shared fetch wrapper, response types, test wallet discovery from /trades (deps: 1)
- [ ] Write test-positions.ts — GET /positions with pagination, market filter, sorting (deps: 2)
- [ ] Write test-closed-positions.ts — GET /closed-positions with sorting and pagination (deps: 2)
- [ ] Write test-activity.ts — GET /activity with type filtering and date range (deps: 2)
- [ ] Write test-value.ts — GET /value with optional market filter (deps: 2)
- [ ] Write test-trades.ts — GET /trades with user, side, pagination (deps: 2)
- [ ] Write test-profile.ts — GET /public-profile on gamma-api (deps: 2)
- [ ] Write run-all.ts — sequential runner with structured pass/fail summary table (deps: 3, 4, 5, 6, 7, 8)
- [ ] Run full suite, fix failures, write RESULTS.md with response shapes and Canon recommendations (deps: 9)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Pure fetch, no SDK | Use pmxtjs for Data API | pmxt wraps CLOB, not Data API. Direct fetch is simpler and avoids the auth requirement pmxt imposes |
| Discover test wallet dynamically | Hardcode a known address | More robust — addresses can become inactive. Fetching a recent trader from /trades ensures valid data |
| Sequential plan | Parallel test files | Each test builds on common.ts patterns and learnings. Items 3-8 can run in parallel after common.ts is done |

## Completion criteria

- [ ] All 6 Data API endpoints return 200 with expected response shapes
- [ ] Gamma profile endpoint returns 200 with expected fields
- [ ] run-all.ts produces clean pass/fail summary with 0 exit code
- [ ] RESULTS.md documents all response shapes, pagination behavior, quirks, and Canon recommendations
- [ ] No hardcoded wallet addresses — test wallet discovered dynamically
