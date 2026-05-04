# Security note — old POC wallet has unresolved issues

The wallet that has shipped in 7+ `.env` files across `~/dega/`,
`~/demo-strategy/`, `~/nba-strategy/`, etc. has three independent
problems. **Do not use it for live trading**, and consider rotating it
out entirely.

| Field | Value |
|---|---|
| Private key | `0x89be47f5fe5e33921a0328de26b0517917246c2426da56623ea99942c84b7744` |
| EOA | `0x7b2d23fd477bbC52D98620cD36e2EAa470e0fC8C` |
| Polymarket Safe | `0x08e4282014bd434b83999f119b9c94860596fc4e` |

## 1. Banned by Polymarket

The CLOB matcher rejects every order from this EOA with
`'0x7b2d23fd…' address banned` (HTTP 400). `getClosedOnlyMode()`
returns `closed_only:false` — this is a *hard* ban, not a "you can
close existing positions" restriction.

Verified live 2026-05-03 during the canon onboarding test. The full
onboarding chain (Safe deploy, V1+V2 approvals, API creds) succeeded;
only `postOrder` fails. A fresh EOA from the same machine works
without issue, so the ban is wallet-specific, not user-specific.

Cause unknown. Compliance reasons are typically opaque. Possible
triggers: prior interaction from a restricted IP, an OFAC-flagged
counterparty in this EOA's transaction history, or a manual flag.

**Implication:** the wallet is permanently unusable for live trading
on Polymarket. Even if compliance unflagged it tomorrow, we have no
visibility into that decision.

## 2. EIP-7702 delegation of unknown origin

`eth_getCode(0x7b2d23fd…)` returns 23 bytes starting with `0xef0100…`
— the EIP-7702 delegation designator, pointing at:

```
0x3ae1f70cf6da80955936f5599d103fcf62162d10
```

That means at some point the EOA's PK signed an EIP-7702 authorization
making this contract the EOA's "code". Until that authorization is
revoked, the contract can do anything the EOA could do — including
sweeping funds.

We didn't investigate what `0x3ae1f70cf6da80955936f5599d103fcf62162d10`
is. Worth checking before keeping any value at the EOA. Likely
candidates:

- A MetaMask Smart Account (EIP-7702 setup signed during a wallet UX upgrade).
- An MEV-protection contract (some agg / RPC providers prompt for this).
- An account-abstraction session key for an app the user signed into.
- Something hostile.

**To revoke:** sign a new EIP-7702 authorization with the delegated
contract address `0x0000000000000000000000000000000000000000` and
include it in any tx. MetaMask and similar wallets expose this via
"reset smart account" or equivalent.

## 3. Private key leaked across many local files

```
$ grep -rl "0x89be47f5" ~ 2>/dev/null
~/demo-strategy/.env
~/nba-strategy/.env
~/dega/test-arb-bu/.env
~/dega/test-arb4/.env
~/dega/test-arb3/.env
~/dega/test-arb2/.env
~/dega/old-nba-strategy/.env
~/dega/dega-connect-demo/.env
~/dega/nba-strategy/.env
~/dega/dega-sdk-demo/.env
~/dega/test-arb/.env
~/dega/test-trade/.env
~/dega/test-trade2/.env
… (and likely more)
```

For a wallet that never holds large value this is just hygiene; for
one that has been a Polymarket counterparty (i.e. Polymarket has it on
file) the leakage compounds the EIP-7702 + ban concerns. If you keep
using this PK for any live system, anyone with access to any of those
files can sign as you.

## 4. Unexplained transfer 2026-05-03

Two hours before the canon live test, ~$1.7k of POL appeared at:

```
0xeeeee90971B6264C53175D3Af6840a8dD5dc7b6C
```

You didn't recognize this address and don't hold its private key.
Direction (was it from your EOA or to it?) was never confirmed —
worth pulling the polygonscan history to find out:

```
https://polygonscan.com/address/0xeeeee90971B6264C53175D3Af6840a8dD5dc7b6C
```

If the funds came from the original EOA, the EIP-7702 delegation
contract or some session key may have moved them. If they came from a
CEX or another wallet you control, this is just a memory gap and
nothing's wrong.

## Recommendation

1. Generate a fresh PK for live trading. Don't reuse this one.
2. Sweep any value still parked at `0x7b2d23fd…` or its Safe
   `0x08e4…` to a fresh wallet — but do it knowing the EIP-7702
   delegation contract may also be able to move funds, so race conditions
   are possible. Use a single high-priority tx.
3. Investigate `0x3ae1f70cf6da80955936f5599d103fcf62162d10` to
   understand what authorization is in place. If it's a contract
   you don't recognize, treat it as hostile.
4. Pull polygonscan history for `0xeeeee…7b6C` to close the loop on
   the 2026-05-03 transfer.
5. Delete the `0x89be…744` PK from all the `.env` files above (and
   wherever else `grep` finds it). Track in
   [`docs/tech-debt.md`](tech-debt.md) until done.
