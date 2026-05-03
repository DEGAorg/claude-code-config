# Polymarket Onboarding — Programmatic Flow

How to take a fresh EOA from "key in hand" to "trading on the CLOB" without
touching polymarket.com. This is the contract canon's onboard automation
implements.

Last verified against `@polymarket/builder-relayer-client@0.0.9` and
`@polymarket/clob-client-v2@^1.0.0` on Polygon mainnet (chain 137), May 2026.

---

## TL;DR

1. **Derive** the Safe proxy address from the EOA (deterministic, no chain call).
2. **Deploy** the Safe via Polymarket's gasless relayer (one signature).
3. **Approve** the CLOB contracts to move the Safe's collateral and outcome
   tokens (single batched Safe transaction).
4. **Authenticate** with the CLOB by deriving API credentials from the EOA
   signature (no on-chain action).
5. **Trade.**

The user's only responsibility: send collateral to the Safe address. Steps 1–5
are agent-driven.

---

## Implementation in canon

This flow is implemented as the venue-agnostic `OnboardClient` interface plus
a single Polymarket adapter:

| Layer | Path |
|---|---|
| Interface | [`canon/templates/types/OnboardClient.ts`](../templates/types/OnboardClient.ts) |
| Registry hook | [`canon/templates/types/MarketVenueOnboard.ts`](../templates/types/MarketVenueOnboard.ts) |
| Adapter (this flow) | [`canon/templates/polymarket-onboard.ts`](../templates/polymarket-onboard.ts) |
| CLI driver | [`canon/cli/commands/onboard.ts`](../cli/commands/onboard.ts) |
| Adapter unit tests | [`canon/templates/__tests__/onboarding.test.ts`](../templates/__tests__/onboarding.test.ts) |
| Cross-adapter contract test | [`canon/templates/__tests__/onboarding-adapter.test.ts`](../templates/__tests__/onboarding-adapter.test.ts) |
| Live smoke (`RUN_LIVE=1`) | [`canon/templates/__tests__/smoke-onboarding.ts`](../templates/__tests__/smoke-onboarding.ts) |

Operator entry points:

- `canon-cli onboard --status --venue polymarket` — read-only JSON dump of
  `funderDeployed` / `approvalsReady` / `credsReady` / `fundedCollateral` /
  `funderAddress`.
- `canon-cli onboard --execute --venue polymarket` — drives
  `ensureFunder → ensureApprovals → ensureCreds`. Idempotent; second run is a
  near-no-op.

Strategy `assertLiveCapabilities` (in
`canon/templates/strategies/trade-momentum/entry.ts`) calls
`polymarketOnboard.build(pk).status()` and throws an actionable message
(e.g. "send collateral to <funderAddress>" / "run `canon-cli onboard
--execute`") when any flag is false — replacing the previous
`ensurePolymarketProxy` HTML-scrape.

Adding another venue (Kalshi, etc.) means writing one adapter against the
same `MarketVenueOnboard` contract. The CLI driver and the contract test
suite stay unchanged.

---

## Concepts

| Term | Meaning |
|---|---|
| EOA | The signing wallet. Holds the private key. Pays no gas in the standard flow. |
| Safe (proxy) | Gnosis-Safe contract that holds the user's collateral and outcome tokens. The CLOB sees the Safe as the *funder*; the EOA is the *signer*. |
| Collateral | The ERC-20 the CLOB settles in. Polymarket recently moved from USDC.e to pUSD — verify the active token via `@polymarket/clob-client-v2` config at runtime. |
| Outcome tokens | ERC-1155 conditional tokens issued by the CTF; tracked per market outcome. |
| Builder relayer | Polymarket-operated meta-tx service that submits Safe deployments and Safe txs gaslessly. |

## Signature types

The CLOB exposes three. The onboarding flow we automate produces a Safe — so
we always use type 2.

| `signatureType` | When |
|---|---|
| `0` (eoa) | EOA holds collateral directly. No proxy. |
| `1` (poly-proxy) | Legacy email/Magic-style proxy. |
| `2` (gnosis-safe) | Modern Safe proxy. **What this flow produces.** |

---

## Polygon contract addresses

Pull the live config at runtime via `getContractConfig(137)` — values below are
snapshots for reference, not for hard-coding.

| Contract | Address |
|---|---|
| SafeFactory | `0xaacFeEa03eb1561C4e67d661e40682Bd20E3541b` |
| SafeMultisend | `0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761` |
| CTF Exchange | `0xE111180000d2663C0091e4f400237545B87B996B` |
| NegRisk CTF Exchange | `0xe2222d279d744050d28e00520010520000310F59` |
| NegRisk Adapter | `0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296` |
| Conditional Tokens (CTF) | `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045` |
| pUSD (collateral) | `0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB` |

Relayer endpoints:

- Production: `https://relayer-v2.polymarket.com/`
- Staging: `https://relayer-v2-staging.polymarket.dev/` (chain 80002, Amoy)

---

## The flow, step by step

### 1. Derive the Safe address

```ts
import { Wallet } from "ethers";
import {
  deriveSafe,
  getContractConfig,
} from "@polymarket/builder-relayer-client";

const eoa = new Wallet(privateKey).address;
const config = getContractConfig(137);
const safeAddress = deriveSafe(eoa, config.SafeContracts.SafeFactory);
```

`deriveSafe` is pure — same input, same output, no network. Deterministic
predicts the Safe's address before deployment, so the user can prefund it.

### 2. Deploy the Safe (idempotent)

```ts
import { RelayClient } from "@polymarket/builder-relayer-client";

const relay = new RelayClient(
  "https://relayer-v2.polymarket.com",
  137,
  new Wallet(privateKey),
);

if (!(await relay.getDeployed(safeAddress))) {
  const res = await relay.deploy();
  await res.wait(); // tx mined; Safe now exists at safeAddress
}
```

Gasless. The relayer pays. `deploy()` is safe to call only when
`getDeployed()` returns false — guard accordingly.

### 3. Batch approvals

The Safe must approve every CLOB contract that will pull collateral or move
outcome tokens. Two ABIs:

- ERC-20 `approve(spender, MAX_UINT256)` for collateral → CTFExchange,
  NegRiskCTFExchange, NegRiskAdapter, CTF.
- ERC-1155 `setApprovalForAll(spender, true)` for the CTF → CTFExchange,
  NegRiskCTFExchange, NegRiskAdapter.

```ts
import { encodeFunctionData, erc20Abi } from "viem";
import type { SafeTransaction } from "@polymarket/builder-relayer-client";

const txs: SafeTransaction[] = [];

for (const spender of erc20Spenders) {
  txs.push({
    to: collateralAddress,
    operation: 0, // Call
    data: encodeFunctionData({
      abi: erc20Abi,
      functionName: "approve",
      args: [spender, MAX_UINT256],
    }),
    value: "0",
  });
}

for (const spender of erc1155Spenders) {
  txs.push({
    to: ctfAddress,
    operation: 0,
    data: encodeFunctionData({
      abi: erc1155Abi,
      functionName: "setApprovalForAll",
      args: [spender, true],
    }),
    value: "0",
  });
}

await relay.execute(txs, "canon: initial CLOB approvals");
```

Run once per Safe. After this, allowance reads return `MaxUint256` and the
live executor's allowance check is a no-op.

### 4. Derive CLOB API credentials

```ts
import { ClobClient } from "@polymarket/clob-client-v2";

const tempClient = new ClobClient({
  host: "https://clob.polymarket.com",
  chain: 137,
  signer: new Wallet(privateKey),
});
const creds = await tempClient.createOrDeriveApiKey();

const clob = new ClobClient({
  host: "https://clob.polymarket.com",
  chain: 137,
  signer: new Wallet(privateKey),
  creds,
  signatureType: 2,        // gnosis-safe
  funderAddress: safeAddress,
});
```

`createOrDeriveApiKey` is L1-signature-based. It first tries `deriveApiKey()`
(works if creds already exist for this EOA on the CLOB) and only creates new
ones if the derive fails. Idempotent.

### 5. Trade

`clob.postOrder(...)` takes signed CLOB orders. From canon's perspective this
is delegated to pmxt-core, which already wraps `clob-client-v2` and handles
the order EIP-712 signing.

---

## Funding

The Safe's collateral balance is what the CLOB matcher checks before
accepting an order. Two paths:

- **Direct deposit:** transfer the collateral token directly to
  `safeAddress`. No signature; just a transfer. Works the moment the Safe
  is deployed.
- **Onramp + swap:** if the user only has POL / native USDC / USDT, canon's
  existing `swapToUsdce` (Uniswap v3) can convert on the EOA, then a Safe
  transaction moves the funds from EOA to Safe.

Out of scope for the onboarding SDK; in scope for `canon-cli onboard`.

---

## Idempotency contract

Every step is safe to re-run:

| Step | Skip condition |
|---|---|
| Derive Safe | always pure |
| Deploy | `getDeployed(safeAddress) === true` |
| Approvals | per-spender allowance ≥ threshold (read on-chain) |
| API creds | `tempClient.deriveApiKey()` returns valid creds |

A canon "ready to trade" check is the AND of: Safe deployed, all approvals
present, valid creds derivable, EOA owns the Safe.

---

## Failure modes worth catching

- **Relayer 4xx on `deploy()`** — usually a stale nonce or a duplicate. Retry
  after `getDeployed()` flips true; if it doesn't flip within ~30s, escalate.
- **`createOrDeriveApiKey` returns incomplete creds** — the EOA was never
  registered with the CLOB; falls through to `createApiKey`. Always check
  `creds.key && creds.secret && creds.passphrase`.
- **Approvals tx mined but allowance still 0** — happens when the wrong
  spender list is used (e.g. legacy CTFExchange address). Re-read
  `getContractConfig(137)` and the CLOB's quoted spenders; don't hard-code.
- **Collateral migration** — Polymarket moved from USDC.e to pUSD; check the
  CLOB's quoted collateral at startup, not via env constants.

---

## Sources

- [Polymarket safe-wallet-integration](https://github.com/Polymarket/safe-wallet-integration)
- [@polymarket/builder-relayer-client (npm)](https://www.npmjs.com/package/@polymarket/builder-relayer-client)
- [Polymarket relayer-client docs](https://docs.polymarket.com/developers/builders/relayer-client)
- [Polymarket CLOB quickstart](https://docs.polymarket.com/developers/CLOB/quickstart)
- [Magic + Safe builder example](https://github.com/Polymarket/magic-safe-builder-example)
- [Turnkey + Safe builder example](https://github.com/Polymarket/turnkey-safe-builder-example)
- [Polymarket contract addresses](https://docs.polymarket.com/resources/contracts)
