# Plan: Extend pmxt POC with Polymarket Data API for Third-Party Account Tracking

**Status:** Draft
**Created:** 2026-03-26

## Requirements

- Add Data API endpoint tests to the existing `poc/pmxt-poc/` project
- Validate all public endpoints needed for third-party wallet tracking (no auth, no private key)
- Test `GET /positions`, `/closed-positions`, `/activity`, `/value`, `/trades` on `data-api.polymarket.com`
- Test `GET /public-profile` on `gamma-api.polymarket.com`
- Document response shapes, pagination behavior, rate limits, and quirks
- Update `run-all.ts` to include the new test suites
- Update `RESULTS.md` with Data API findings and Canon integration recommendations

## Approach

Add new test files to the existing `poc/pmxt-poc/src/` directory. Use pure `fetch()` for Data API calls (no SDK needed — these are public REST endpoints). Discover a test wallet dynamically by fetching recent trades from a popular market. Follow existing test file conventions (TestResult interface, structured summary output, exit codes).

No new dependencies needed — Node 22 has native `fetch()`.

## Files to touch

| File | Change |
|------|--------|
| `poc/pmxt-poc/src/data-api-common.ts` | Create — shared fetch wrapper, types, test wallet discovery |
| `poc/pmxt-poc/src/test-data-api-positions.ts` | Create — GET /positions and /closed-positions |
| `poc/pmxt-poc/src/test-data-api-activity.ts` | Create — GET /activity and /value |
| `poc/pmxt-poc/src/test-data-api-trades.ts` | Create — GET /trades with filtering |
| `poc/pmxt-poc/src/test-data-api-profile.ts` | Create — GET /public-profile on gamma-api |
| `poc/pmxt-poc/src/run-all.ts` | Update — add new suites to SUITES array |
| `poc/pmxt-poc/RESULTS.md` | Update — add Data API section with response shapes and recommendations |

## Risks and open questions

- Rate limits on Data API are undocumented — add 500ms delays between requests to be safe
- Need a test wallet with known positions — discover dynamically from /trades on an active market

## Progress log

- [ ] Create data-api-common.ts — shared types, fetch wrapper with error handling, test wallet discovery from /trades
- [ ] Create test-data-api-positions.ts — GET /positions (pagination, market filter, sorting) and GET /closed-positions (deps: 1)
- [ ] Create test-data-api-activity.ts — GET /activity (type filtering, date range) and GET /value (deps: 1)
- [ ] Create test-data-api-trades.ts — GET /trades (user filter, side filter, pagination) (deps: 1)
- [ ] Create test-data-api-profile.ts — GET /public-profile on gamma-api (deps: 1)
- [ ] Update run-all.ts — add Data API suites to SUITES array, run full suite, fix any failures (deps: 2, 3, 4, 5)
- [ ] Update RESULTS.md — add Data API section with response shapes, pagination, quirks, and Canon recommendations (deps: 6)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Extend existing pmxt-poc | Separate data-api-poc directory | Keeps all Polymarket validation in one place, reuses project config and runner |
| Pure fetch, no SDK | Use an HTTP client lib like ky or got | Data API is simple REST, native fetch is sufficient, zero new deps |
| Discover test wallet dynamically | Hardcode a known address | More robust — addresses go inactive. Fetching a recent trader from /trades ensures valid data |
| Group related endpoints per test file | One file per endpoint | Positions+closed-positions and activity+value are closely related, reduces file count |

## Completion criteria

- [ ] All 6 Data API endpoints (positions, closed-positions, activity, value, trades, profile) return 200 with expected response shapes
- [ ] run-all.ts includes Data API suites and produces clean pass/fail summary with 0 exit code
- [ ] RESULTS.md updated with Data API response shapes, pagination behavior, quirks, and Canon integration recommendations
- [ ] No hardcoded wallet addresses — test wallet discovered dynamically
