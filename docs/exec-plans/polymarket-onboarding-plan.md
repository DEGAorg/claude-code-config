# Plan — Programmatic Polymarket Onboarding

Replace the manual polymarket.com migration with a library + CLI command
that takes a fresh EOA from "key in hand" to "trading on the CLOB" without
human intervention beyond sending funds.

Reference doc: [`canon/docs/polymarket-onboarding.md`](../../canon/docs/polymarket-onboarding.md)

Branch: `feat/trade-02-live-execution` (continues current work).

---

## Goal

After this plan ships, `canon-cli onboard --execute` against a freshly
generated EOA, on a wallet with collateral on Polygon, leaves the user able
to run `tsx src/main.ts --live` and place a real GTC limit order without
any browser interaction.

## Acceptance criteria

Each is a shell command that exits 0 on success.

1. `pnpm test canon/templates/__tests__/onboarding.test.ts` — unit tests pass.
2. `pnpm test canon/templates/__tests__/onboarding-adapter.test.ts` — adapter
   contract tests pass.
3. `canon-cli onboard --status` — reports `{ deployed: bool, approved: bool,
   credsReady: bool, fundedCollateral: number }` for the configured EOA, in
   under 5s.
4. `canon-cli onboard --execute` — drives an unboarded EOA to fully
   onboarded; idempotent (running twice returns instantly the second time).
5. `tsx canon/templates/__tests__/smoke-onboarding.ts` — integration smoke
   that, given a funded EOA env, completes onboarding and submits a 5-share
   GTC limit at $0.01 (then cancels). Exits 0; prints the order id.
6. `pnpm exec tsc --noEmit` — typecheck clean.
7. `pnpm exec vitest run` — full suite green (excluding existing skipped
   integration tests).

## Non-goals

- Generic multi-venue onboarding. (The interface is venue-agnostic, but only
  the Polymarket adapter ships in this plan.)
- A UI. The TUI work in DEGAorg/canon-tui consumes this CLI.
- Funds onramp. `swapToUsdce` exists; bridging it into onboard is a follow-up.
- Removing `proxy-discovery.ts`. Keep it as a fallback for non-onboarded
  wallets; remove in a separate cleanup once onboard is live.

---

## Reusable abstractions

Two new venue-agnostic interfaces, one Polymarket adapter, one CLI driver.
Mirrors the existing `AllowanceClient` / live-executor pattern.

### `OnboardClient` (interface)

```ts
// canon/templates/types/OnboardClient.ts
export interface OnboardStatus {
  /** True when the funder contract (Safe / proxy / EOA itself) exists. */
  funderDeployed: boolean;
  /** True when every spender required for trading has sufficient allowance. */
  approvalsReady: boolean;
  /** True when CLOB API credentials can be derived from the signer. */
  credsReady: boolean;
  /** Collateral balance on the funder, in human units. */
  fundedCollateral: number;
  /** The address that holds collateral and signs orders' funder field. */
  funderAddress: string;
}

export interface OnboardClient {
  /** Pure / cheap lookup. Never mutates state. */
  status(): Promise<OnboardStatus>;
  /** Deploy funder if not deployed. No-op when already deployed. */
  ensureFunder(): Promise<{ deployed: boolean; txHash?: string }>;
  /** Set every spender approval. No-op for already-approved spenders. */
  ensureApprovals(): Promise<{ approved: boolean; txHash?: string }>;
  /** Derive (or create) CLOB API creds. Idempotent. */
  ensureCreds(): Promise<{ key: string; secret: string; passphrase: string }>;
}
```

### `MarketVenueOnboard` (registry hook — future-proofing)

```ts
// canon/templates/types/MarketVenueOnboard.ts
export interface MarketVenueOnboard {
  readonly venue: "polymarket" | "kalshi" | string;
  readonly chainId: number;
  build(privateKey: string): OnboardClient;
}
```

We register one entry today (polymarket). Kalshi etc. plug in later without
touching the CLI driver.

### `PolymarketOnboard` (adapter)

```ts
// canon/templates/polymarket-onboard.ts
export const polymarketOnboard: MarketVenueOnboard = {
  venue: "polymarket",
  chainId: 137,
  build(privateKey: string): OnboardClient { /* … */ },
};
```

Internally wraps `@polymarket/builder-relayer-client` + `@polymarket/clob-client-v2`.
All Polymarket specifics live here; the CLI never imports those packages.

### CLI driver

`canon-cli onboard [--status|--execute] [--venue polymarket]` — defaults to
`polymarket`, looks up the adapter from a registry, runs `status()` or the
`ensureFunder → ensureApprovals → ensureCreds` chain.

---

## Progress log

(With `(deps: N)` annotations per the orch contract.)

- [ ] **1. Add SDKs + types skeleton**
   Touch: `canon/templates/package.json`, `canon/templates/types/OnboardClient.ts`, `canon/templates/types/MarketVenueOnboard.ts`.
   Add `@polymarket/builder-relayer-client` and `@polymarket/clob-client-v2`
   as explicit deps (clob-client-v2 currently transitive). Define the two
   interfaces above. No implementation yet.
   Verify: `pnpm exec tsc --noEmit` clean; `grep -c "interface OnboardClient" canon/templates/types/OnboardClient.ts` returns 1.

- [ ] **2. Write tests for `polymarket-onboard.ts` (TDD)** (deps: 1)
   Touch: `canon/templates/__tests__/onboarding.test.ts`.
   Cover: status() short-circuits when nothing deployed; ensureFunder skips
   when getDeployed=true; ensureApprovals skips per-spender when allowance
   high; ensureCreds returns derive result when present, falls back to
   create when derive throws "incomplete"; failure paths (relayer 4xx,
   creds incomplete, getContractConfig invalid). Mocks `RelayClient` and
   `ClobClient`.
   Verify: `pnpm exec vitest run __tests__/onboarding.test.ts` shows the
   tests fail (no impl yet).

- [ ] **3. Implement `polymarket-onboard.ts`** (deps: 2)
   Touch: `canon/templates/polymarket-onboard.ts`.
   Wraps the SDKs. Keeps spender list keyed off `getContractConfig(chainId)`
   plus a hard-checked override for the CLOB-quoted spenders if the SDK
   list drifts. Reads collateral token from clob-client-v2 config (don't
   hard-code USDC.e vs pUSD). Returns the adapter object.
   Verify: `pnpm exec vitest run __tests__/onboarding.test.ts` green.

- [ ] **4. Wire into `assertLiveCapabilities`** (deps: 3)
   Touch: `canon/templates/strategies/trade-momentum/entry.ts` (and the
   four sibling strategies).
   Replace the current `ensurePolymarketProxy` HTML scrape with an
   `assertReadyToTrade()` that runs `polymarketOnboard.build(pk).status()`
   and throws with an actionable message if any flag is false ("send X
   collateral to <safeAddr>" / "run canon-cli onboard --execute").
   Verify: `pnpm exec vitest run strategies/trade-momentum/__tests__/entry.test.ts` green.

- [ ] **5. CLI command** (deps: 3)
   Touch: `canon/cli/commands/onboard.ts` (extend if exists; else create),
   `canon/cli/commands/index.ts`.
   Subcommands: `--status` (JSON) and `--execute` (drives the chain). Reads
   PK from existing wallet store. No new deps; uses the adapter.
   Verify: `canon-cli onboard --status --venue polymarket` returns valid
   JSON for an unfunded test wallet.

- [ ] **6. Adapter contract test** (deps: 5)
   Touch: `canon/templates/__tests__/onboarding-adapter.test.ts`.
   Generic test that any `MarketVenueOnboard` adapter must satisfy:
   idempotent `ensureFunder`, `ensureApprovals`, `ensureCreds`; `status()`
   reflects state changes. Run against `polymarketOnboard` with mocked
   relayer. This locks the contract for future Kalshi etc.
   Verify: `pnpm exec vitest run __tests__/onboarding-adapter.test.ts` green.

- [ ] **7. Live smoke** (deps: 5)
   Touch: `canon/templates/__tests__/smoke-onboarding.ts`.
   Reads PK + funded EOA from env; runs full onboarding; submits 5-share
   GTC @ $0.01; cancels; prints order id. Skipped by default; `RUN_LIVE=1`
   env opts in. Not part of CI.
   Verify (manual, with a funded wallet): `RUN_LIVE=1 pnpm exec tsx __tests__/smoke-onboarding.ts` exits 0.

- [ ] **8. Doc + memory updates** (deps: 7)
   Touch: `canon/docs/polymarket-onboarding.md` (cross-link from the plan),
   memory note for "onboarding is now agent-driven, no UI step."
   Verify: `grep -q polymarket-onboard.ts canon/docs/polymarket-onboarding.md`.

---

## File budget

Per-item file count (max 3 per item, per the global guard):

| Item | Files |
|---|---|
| 1 | 3 (package.json + 2 type files) |
| 2 | 1 |
| 3 | 1 |
| 4 | 2 (entry.ts + at most one shared helper) |
| 5 | 2 (commands/onboard.ts + index registration) |
| 6 | 1 |
| 7 | 1 |
| 8 | 2 (doc + memory) |

Total new/changed files: ~13. No item exceeds 3.

## Risks

- **Relayer 4xx behaviour is undocumented.** Mitigation: bound the
  ensureFunder retry loop (≤3 attempts, 5s backoff), surface the relayer's
  raw error in the thrown message.
- **CLOB-quoted spenders drift from SDK config.** Mitigation: at runtime,
  cross-check `getContractConfig(chainId)` against the spenders the
  ClobClient hands us; warn loudly on mismatch instead of silently using
  stale data.
- **Collateral token migration mid-flight (USDC.e → pUSD).** Mitigation:
  read the active collateral from `clob-client-v2`'s config object, never
  from a templates-side constant.
- **Onboarding signature flow changes.** Mitigation: pin SDK versions
  exactly (no `^`), add a weekly upstream-check cron later.

## Out of scope follow-ups

- Bridge `swapToUsdce` (or pUSD equivalent) into `canon-cli onboard
  --execute` so a wallet with only POL/USDT can fully self-onboard.
- Remove `proxy-discovery.ts` once onboard is shipped and the strategies
  no longer need an HTML-scrape fallback.
- Multi-venue: implement a `kalshiOnboard` adapter against the same
  `MarketVenueOnboard` contract.
