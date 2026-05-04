# Canon Live Trading

End-to-end guide for taking a Canon strategy from validated dry-run to
live trading on Polymarket. The flow is two slash commands separated
by a deposit:

1. `/canon-start` — builds the project, runs the strategy in **dry-run**
   so you can confirm signals fire without risking funds.
2. `/canon-start --live` — collects a native-USDC deposit at your EOA,
   runs the gasless onboarding chain that pulls funds into the
   Polymarket Safe, and launches the strategy with `--live`.

Everything between the two commands is agent-driven. There is no
separate "configure wallet" step, no UI to click, and no manual chain
interaction. The user only needs to send native USDC to the printed
address.

---

## Prerequisites

- DEGA Core installed (`canon-cli` available on PATH). See
  [INSTALL.md](../INSTALL.md).
- Canon TUI or tmux for the dashboard view (optional but recommended).
- A Polygon mainnet wallet with **native USDC** to fund the strategy.
  Canon converts this to pUSD (Polymarket's collateral asset) via a
  single batched relayer-paid Safe transaction — the EOA never needs
  POL for gas.

> **Geo restrictions.** Polymarket's CLOB matcher hard-bans EOA
> addresses originating in the US, UK, France, Belgium, Singapore,
> Taiwan, Thailand, Australia, Poland, Ontario, plus OFAC sanctioned
> jurisdictions. The ban is enforced at order-submit time, so an
> onboarded wallet that is geo-banned will surface the rejection
> when the live runner places its first order, not at onboarding.

---

## Step 1 — Build the strategy

```text
cd /path/to/my-strategy
/canon-start
```

`/canon-start` (no flag) walks the standard build pipeline:

1. **Init** — copies the canon templates (strategies, runner, types,
   client, configs) into the project.
2. **Wallet ensure** — generates a project-local burner at
   `.canon/wallet.env` if one doesn't exist (mode `0600`, gitignored).
3. **Scaffold** — fetches per-agent commands and skills.
4. **Strategy** — asks (via `AskUserQuestion`) which strategy to use.
   Pick `trade-momentum`, `arb-binary`, or any other available
   strategy. The pre-built bundle is copied to `src/main.ts`.
5. **Develop** — runs `vitest`, `tsc --noEmit`, and lint. Fails fast
   on any errors.
6. **Run** — launches `canon-runner.sh` (no flag = dry-run) as a
   backgrounded process. The PID is printed.

When step 6 succeeds, the dashboard shows `phase=run, status=executing,
metric.mode=dry-run` and the strategy starts cycling its scan loop —
emitting `SCAN`, `NO_EDGE`, and (when conditions match) `SIGNAL` log
lines without placing real orders.

> **Stop the dry-run runner before going live.** The live transition
> handles this automatically (see step 2), but if you're running
> outside the canon-start flow you can stop it manually with
> `kill <pid>` (PID is in `.canon/execution/runner.pid`).

---

## Step 2 — Go live

```text
/canon-start --live
```

The agent recognizes the `--live` flag and skips straight to the live
transition. The deterministic spine is
[`scripts/canon-live-readiness.sh`](../scripts/canon-live-readiness.sh).

### What happens

1. **Hard barrier check.** The script refuses to proceed if
   `src/main.ts` doesn't exist — you must run `/canon-start` (no flag)
   first to build the strategy.
2. **Onboarded-state detection.** Calls `canon-cli onboard --status`.
   If `funderDeployed`, `approvalsReady`, `credsReady`, and
   `fundedCollateral > 0` are all true, skips deposit/onboard and
   goes straight to launching the live runner.
3. **Deposit prompt.** Prints your EOA address and instructions:

   ```
   ════════════════════════════════════════════════════════════
     Canon live mode — wallet onboarding required
   ════════════════════════════════════════════════════════════

     Send native USDC on Polygon to your EOA:
       0xAbc...

     Do NOT send to the Safe (0xDef...) — Canon will pull funds
     from the EOA into the Safe via a gasless permit.

     Polling every 10s, timeout 1800s.
   ```

4. **Polling.** Every 10 seconds (configurable —
   `CANON_LIVE_POLL_SECS`), the script calls `canon-cli balance` and
   checks the EOA's native USDC balance. Updates `.canon/state.json`
   with current `metric.detected_amount` and `metric.elapsed_secs`.
   Default timeout is 30 minutes (`CANON_LIVE_TIMEOUT_SECS`).
5. **Funds detected.** First non-zero balance triggers
   `status=funds-detected` and immediately advances to onboarding.
   No "are you sure?" prompt — Canon pulls the full detected amount
   into the Safe.
6. **Onboarding chain.** Runs `canon-cli onboard --execute --fund
   --venue polymarket`. This single command does everything:
   - Bootstraps Polymarket builder credentials (creates an API key
     scoped to the Safe via the CLOB) if `POLYMARKET_BUILDER_*`
     environment variables are unset.
   - Deploys the Safe via Polymarket's gasless relayer (one
     wallet-paid transaction's worth of work, but the relayer pays
     the gas).
   - Approves V1 + V2 spenders for both ERC-20 (pUSD) and ERC-1155
     (conditional tokens) — required for both classic and NegRisk
     markets.
   - Signs an EIP-2612 permit on native USDC to authorize the Safe
     to pull funds from the EOA without an EOA-side gas payment.
   - Submits a six-call batched Safe transaction:
     1. `permit` — register the off-chain signature on-chain.
     2. `transferFrom` — pull native USDC EOA → Safe.
     3. `approve(SwapRouter)` — let Uniswap spend native USDC.
     4. `exactInputSingle` — swap native USDC → USDC.e on Uniswap V3.
     5. `approve(Onramp)` — let Polymarket's onramp spend USDC.e.
     6. `wrap` — convert USDC.e → pUSD inside the Safe.
   - Persists `WALLET_PROXY_ADDRESS`, `POLYMARKET_BUILDER_API_KEY`,
     `POLYMARKET_BUILDER_SECRET`, and `POLYMARKET_BUILDER_PASSPHRASE`
     to `.canon/wallet.env` so subsequent runs (and the live runner)
     pick them up automatically.
7. **Verify.** Re-reads `canon-cli onboard --status`; refuses to
   proceed if any flag is still false or collateral is still zero.
8. **Stop dry-run runner.** If `.canon/execution/runner.pid` points
   at a live process, the script sends `SIGTERM`, waits up to 5
   seconds, then `SIGKILL`. This frees `canon-runner.sh`'s PID
   guard so the live runner can boot.
9. **Launch live runner.** Calls `canon-runner.sh --live`, which
   sources `.env` and `.canon/wallet.env` (so `WALLET_PROXY_ADDRESS`
   etc. reach `client-polymarket.ts:tradingCredentials()`) and
   spawns `tsx src/main.ts --live`. `assertLiveCapabilities` runs
   the shared `assertReadyForLive` gate (TIF check + onboarding
   gate + auth smoke) before the strategy enters its poll loop.

### Idempotency

`/canon-start --live` is safe to re-run:

- **Already onboarded** (Safe deployed, approvals set, creds in env,
  collateral > 0) → skips steps 3–7, just launches the live runner.
- **Polling timed out** → state stays at `phase=live, status=timeout`
  with the EOA address visible. Re-running resumes polling.
- **Live runner crashed** → re-run picks up where it left off,
  detects onboarded state, and launches a fresh runner.

### State machine

`.canon/state.json` exposes the full progression:

| `phase` | `status` | Meaning |
|---|---|---|
| `live` | `deposit-pending` | Waiting for native USDC at the EOA. |
| `live` | `funds-detected` | Balance > 0 observed; onboarding next. |
| `live` | `onboarding` | Running `canon-cli onboard --execute --fund`. |
| `live` | `ready` | Safe deployed + funded; about to launch runner. |
| `live` | `running` | Live runner is up; PID in `metric.runner_pid`. |
| `live` | `timeout` | No deposit detected within
  `CANON_LIVE_TIMEOUT_SECS`. Re-run to resume. |
| `live` | `error` | Hard failure; see the `error` field for details. |

The Canon TUI's plan-execution panel surfaces all of these.

---

## Stopping the live runner

```bash
kill "$(cat .canon/execution/runner.pid)"
```

The runner has a `cleanup` trap that flips `status=idle` (or
`status=error` on a non-zero exit) so the dashboard reflects the
stopped state immediately. Re-running `/canon-start --live` after a
stop relaunches the live runner without the deposit/onboard steps
(it's already onboarded).

---

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `error: src/main.ts not found` | Ran `/canon-start --live` before `/canon-start` | Run `/canon-start` first, then `/canon-start --live`. |
| `error: timeout — no deposit at <eoa> after Ns` | EOA didn't receive native USDC within window | Send native USDC to the printed EOA, re-run `/canon-start --live`. |
| `error: canon-cli onboard --execute --fund failed` | Polymarket relayer rejection — usually missing builder creds, malformed permit, or Cloudflare bot challenge | Check `canon-cli onboard --execute --fund --venue polymarket` output. Builder creds are auto-bootstrapped on first run; if the call fails, check `POLYMARKET_BUILDER_*` env vars and re-run. |
| `error: post-onboard verification failed` | Onboarding ran but one of `funderDeployed` / `approvalsReady` / `credsReady` / `fundedCollateral > 0` is still false | Read `canon-cli onboard --status --venue polymarket` output. Most often: relayer accepted the batch but a sub-tx reverted. Check the txHash on Polygonscan. |
| `error: live runner failed to start` | `canon-runner.sh` couldn't spawn `tsx src/main.ts --live` | Check `.canon/execution/runner.log` for the underlying error. Most common cause: missing `WALLET_PROXY_ADDRESS` in `.canon/wallet.env` (re-run onboard). |
| Live runner runs but every order rejects with "balance: 0" | `client-polymarket.ts:tradingCredentials` is signing with `funder=EOA` instead of `funder=Safe` | `WALLET_PROXY_ADDRESS` isn't in `process.env`. Verify `.canon/wallet.env` has the line and that `canon-runner.sh` sources it (it does in v0.0.0+ — check the script you have installed). |
| Strategy refuses to start with `pmxt sidecar does not advertise <TIF> time-in-force` | Sidecar version mismatch | Update `pmxtjs` to a version that returns `supportsTif: true`. |

---

## Geo + wallet bans

The CLOB matcher enforces geo restrictions and wallet bans at
order-submission time, not at signup. Symptoms in `.canon/execution/runner.log`:

- `'<addr>' address banned` — EOA on Polymarket's blocklist (recent
  orders or country flags).
- `country not allowed` — IP-based geo block, even if the EOA isn't
  banned.

Neither is recoverable by re-running. Generate a fresh wallet
(`canon-cli wallet ensure` after `trash .canon/wallet.env`) and try
again from a different IP or use a clean EOA.

---

## Reference

- Slash command: [`commands/canon-start.md`](../commands/canon-start.md)
  (user-global) and [`canon/commands/canon-start.md`](../canon/commands/canon-start.md)
  (project-local; copied into new projects by scaffold).
- Live-readiness spine: [`scripts/canon-live-readiness.sh`](../scripts/canon-live-readiness.sh)
- Runner: [`scripts/canon-runner.sh`](../scripts/canon-runner.sh)
- Onboarding adapter:
  [`canon/templates/polymarket-onboard.ts`](../canon/templates/polymarket-onboard.ts)
- Shared live-preflight gate:
  [`canon/templates/live-preflight.ts`](../canon/templates/live-preflight.ts)
- Live-verification handoff (May 2026):
  [`docs/handoff-live-trade02.md`](handoff-live-trade02.md)
- Polymarket CLOB / SDK quirks (Cloudflare bot UA, V2 spender split,
  Onramp paused-native, etc):
  [`canon/docs/polymarket-onboarding.md`](../canon/docs/polymarket-onboarding.md)
