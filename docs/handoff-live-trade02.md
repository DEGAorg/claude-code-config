# Handoff — TRADE-02 Live Execution

Single-purpose doc for a fresh session focused on getting trade-momentum
running live end-to-end, programmatic from start to finish (matching what
the prior POC managed by hand). Read top to bottom; don't skim.

---

## Goal

Run TRADE-02 in `--live` mode against real Polymarket markets, with the
strategy submitting GTC limit orders the agent can manage without human
intervention. Reproduce what the prior POC achieved, but as a single
programmatic flow agents can re-run.

**Acceptance:** `mkdir foo && cd foo && canon` → inside the TUI, type
`/canon-start`, pick `trade-momentum`, then *"run it live"* — and at least
one real order lands on the Polymarket order book without manual setup,
with `MAX_ORDERS=3` capping risk.

---

## Current state (as of 2026-05-03)

### What works (turnkey today, post-merge of PR #280)

- `/canon-start` is a **single global slash command** that bootstraps an
  empty dir into a runnable Canon strategy project.
- 6 strategy templates ship in `canon/templates/strategies/`: `arb-binary`,
  `arb-negrisk-buy`, `trade-momentum`, `fair-value`, `mm-premium`,
  `mint-01`. Index: `canon/templates/strategies/STRATEGY-INDEX.md`.
- TRADE-02 dry-run runs cleanly **without wallet creds**:
  - `client-polymarket.ts` read paths bypass the SDK auth wrapper via
    `callSidecar` (sidecar HTTP at `/api/polymarket/<method>`).
  - `live-positions.reconcile()` short-circuits to empty portfolio when
    `WALLET_PRIVATE_KEY` is unset.
- `MOMENTUM_QUERY` defaults to `"NBA"`, `MAX_ORDERS` defaults to `3`. Both
  surface in the START log line.
- Sidecar TIF preflight (`assertLiveCapabilities`) refuses to start
  `--live` if the pmxt sidecar lacks GTC time-in-force.
- `signatureType: 'gnosis-safe'` is the default in `getClient()` whenever
  a proxy address is configured (modern Polymarket accounts).

### What's known-broken or partial

- **Auto-discovery of proxy address is broken at the API end.**
  pmxt-core 2.22.1 calls `https://data-api.polymarket.com/profiles/<EOA>`
  which now returns 404. Polymarket changed the surface; pmxt-core
  hasn't caught up. Manual proxy entry is the only working path right
  now. Reference: `node_modules/.pnpm/pmxt-core@2.22.1.../dist/exchanges/polymarket/auth.js:90` (`discoverProxy()`).
- **`isAuthError()` filter is too narrow.** It matches `authentication |
  unauthorized | credentials` but pmxtjs's `fetchOpenOrders` occasionally
  rejects with `"response.data is not iterable"` (BadRequest wrapping a
  malformed response). Our short-circuit covers the wallet-NOT-set case;
  the wallet-IS-set case can still SCAN_ERROR on transient sidecar
  flakiness. Observed in last demo run on cycle 4 (cycles 3 and 5 were
  fine — runner recovers, doesn't crash). Fix: broaden filter to also
  catch `"is not iterable"`. ~5 min commit. Code at `canon/templates/live-positions.ts:34-46`.

### What's pending (separate work, not blocking live)

- `mint-01` and `mm-premium` — live executor wired, cycle loop pending
  (~2-3h each). Not on demo path.
- `IA-03 fair-value` — extension scaffold only; ships with neutral model
  (no signals fire). Not on demo path.
- Stale-token integration test (`canon/templates/__tests__/integration.test.ts:83`) — skipped, refresh fixture eventually.

---

## What you need from the user before live

1. **`WALLET_PROXY_ADDRESS`** — gnosis-safe proxy address for the funded
   wallet. **You must ask the user to grab this manually**: hover their
   profile in the top-right of polymarket.com (post-migration), copy the
   `0x...` address. pmxt-core's auto-discovery will not work; do not waste
   cycles trying to derive it from on-chain factories or the data-api.
   Document this clearly when you ask.
2. **Confirmation that the wallet was migrated.** The user did the
   ~7-signature Polymarket migration recently; their EOA
   (`0x7b2d23fd477bbC52D98620cD36e2EAa470e0fC8C`) now has a deployed
   gnosis-safe proxy holding USDC.e. If they're unsure, the profile URL
   loading with positions/history confirms it.

---

## What the prior POC did (and what we need to replicate)

The user's prior POC dirs from April 17–21:

- `~/demo-strategy/` (Apr 9)
- `~/nba-strategy/` (Mar 30)
- `~/dega/test-arb-bu/` (Apr 21)

Those POCs successfully:
- Generated a wallet
- Funded it (user-driven, on-chain)
- Did USDC.e approvals to the CTFExchange
- Submitted real CLOB orders via pmxtjs
- Saw fills on Polymarket

What we don't know about the POCs (worth checking the dirs):
- Whether they had `WALLET_PROXY_ADDRESS` set in env at the time. If yes,
  the user must have grabbed it manually (matching today's path).
- pmxtjs version they used (`~/demo-strategy/node_modules/.pnpm/pmxtjs@1.1.2`
  is the older 1.x line — the auth flow may have differed). Worth
  diffing 1.1.2 vs 2.22.1 to see if 1.x had a working auto-discovery.
- Whether the approvals happened via the strategy code or via a separate
  helper script.

**Don't try to "find" the proxy on-chain** unless the user says they
can't grab it from the profile page. We already tried etherscan, drpc,
data-api — all paths blocked or broken. The profile hover is the cheap
deterministic answer.

---

## Sequence to follow

### 0. Pre-flight (no code changes yet)

- Confirm latest fixes are on `main` (PR #280 merged).
- Confirm user's environment is current: `/core-update` (or fresh
  agentic install from
  `https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/INSTALL.md`).
- Confirm pmxt sidecar is running and advertises TIF: `curl
  -X POST -H "x-pmxt-access-token: $(jq -r .accessToken ~/.pmxt/server.lock)"
  -H 'Content-Type: application/json' -d '{"args":[]}' http://localhost:$(jq
  -r .port ~/.pmxt/server.lock)/api/polymarket/getCapabilities`. Expect
  `"supportsTif":true`.

### 1. Broaden the reconcile filter (recommended pre-live)

```ts
// canon/templates/live-positions.ts:34-46 — isAuthError()
const msg = err.message.toLowerCase();
return (
  msg.includes("authentication") ||
  msg.includes("unauthorized") ||
  msg.includes("credentials") ||
  msg.includes("is not iterable")  // ADD THIS
);
```

Add a unit test in `canon/templates/__tests__/live-positions.test.ts`
mirroring the existing auth-error test but with the new phrase. Commit
to develop, sync to main.

### 2. Make a fresh project

```bash
mkdir ~/dega/demo-live-final && cd ~/dega/demo-live-final
canon
```

Inside the TUI: `/canon-start` → pick `trade-momentum`.

### 3. Set live env in the project's `.env`

Ask the user for `WALLET_PROXY_ADDRESS`. Then write:

```
WALLET_PRIVATE_KEY=0x89be47f5fe5e33921a0328de26b0517917246c2426da56623ea99942c84b7744
WALLET_PROXY_ADDRESS=<from user>
# POLYGON_RPC_URL=https://polygon.drpc.org   # default OK; uncomment + override only if drpc flakes
```

(Wallet PK is the user's funded one. Address: `0x7b2d23fd477bbC52D98620cD36e2EAa470e0fC8C`.)

`canon-runner.sh:72-77` sources `.env` automatically — strategy inherits
both vars.

### 4. Smoke `fetchBalance` before --live

Don't go straight to `--live`. Run a tiny script first to confirm auth:

```bash
cat > _smoke.mjs <<'EOF'
import { fetchBalance } from "./client-polymarket.ts";
console.log(await fetchBalance());
EOF
pnpm exec tsx _smoke.mjs
trash _smoke.mjs
```

Expect: array with one entry showing `currency: "USDC"`, `available: <num>`.
If that works, auth chain is healthy.

If auth fails: verify `WALLET_PROXY_ADDRESS` is correct; check
`POLYMARKET_SIGNATURE_TYPE` if non-default needed (defaults to
`gnosis-safe` when proxy is set; `eoa` and `poly-proxy` are alternates).

### 5. Live run

In the TUI session: *"run it live"*. The agent runs `pnpm exec tsx
src/main.ts --live`. Expected START line:

```
START TRADE-02 scanner (live) query=NBA max_orders=3 poll=...ms
```

Cycles run; on signal, the executor submits a GTC limit buy on the YES
token at the entry price. `MAX_ORDERS=3` caps the run; further signals
log `MAX_ORDERS reached — skipping submit`.

### 6. Verify a real order landed

`fetchOpenOrders` from another shell, or check the wallet on
polymarket.com under "open orders." If at least one shows up, success.

---

## Reference paths

- Strategy templates: `canon/templates/strategies/`
- Strategy index + status: `canon/templates/strategies/STRATEGY-INDEX.md`
- Live executor + allowance: `canon/templates/live-executor.ts`,
  `canon/templates/usdc-allowance.ts`
- Polymarket client (read paths via callSidecar; auth path via SDK):
  `canon/templates/client-polymarket.ts`
- Reconcile + short-circuit: `canon/templates/live-positions.ts`
- Sidecar wire: `canon/templates/sidecar.ts`
- canon-start recipe: `canon/commands/canon-start.md` (also at
  `commands/canon-start.md` for global install)
- Scaffold script: `scripts/canon-scaffold.sh` (fetches from `develop`)

## Reference commits

- `f24d3140` — canon-start sed-rewrite for src/main.ts imports
- `41ecc409` — live-positions short-circuit when no wallet env
- `3670e16b` — skip stale integration test
- `c6305531` — `commands/canon-start.md` global install
- `6d8fb013` — original 4-strategy live wiring (PR #277)

---

## Don'ts

- Don't try to derive the proxy address programmatically. We tried
  etherscan, drpc, data-api, factory address lookups — none worked
  end-to-end. Hand-off the profile-hover step to the user. 30 seconds
  vs. 30 minutes of failed exploration.
- Don't downgrade pmxtjs to 1.x to chase whatever the POC used. The 2.x
  signatureType + manual proxy approach lands; 1.x carries different
  risks.
- Don't run `--live` without a successful `fetchBalance` smoke. If auth
  is broken you'll burn time debugging mid-flight while orders haven't
  fired.
- Don't enable the canon-cli auto-generated burner wallet for live
  (`canon-cli wallet ensure`). It creates a fresh unfunded EOA at
  `.canon/wallet.env`. Use the funded wallet from the user's existing
  `.env` only.

## Open questions worth asking the user up front

1. **Proxy address?** Hover polymarket.com profile, paste it.
2. **Wallet still funded?** Confirm USDC.e balance >$0 on the proxy.
   They can check at polymarket.com or via the smoke `fetchBalance`.
3. **Order size budget?** The default `bankroll: 10_000` × `maxExposure:
   0.10` = $1k per signal. With `MAX_ORDERS=3` that's up to $3k of
   working capital. Tunable via the strategy config or env override —
   confirm what they want.

## When live works

Mark MINT-01 + MM-PREMIUM cycle loops as the next priority — they're
the closest to landing as turnkey strategies (#5 and #6 of the index).
~2–3h each, mirror `mint-01/cycle.ts` pattern.
