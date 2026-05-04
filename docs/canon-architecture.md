# Canon Architecture

Map of the moving pieces behind `/canon-start` and `/canon-start --live`,
written for contributors who need to debug, extend, or port the flow.

For end-user instructions, see [Canon Quickstart](canon-quickstart.md)
and [Canon Live Trading](canon-live-trading.md).

---

## Three-layer model

```
┌─────────────────────────────────────────────────────────────────┐
│  Slash command (markdown, agent-readable)                        │
│  commands/canon-start.md       — user-global                     │
│  canon/commands/canon-start.md — project-local (scaffold copy)   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼  (agent invokes bash blocks)
┌─────────────────────────────────────────────────────────────────┐
│  Deterministic shell scripts                                      │
│  scripts/canon-scaffold.sh        — phase init                    │
│  scripts/canon-runner.sh          — strategy launcher             │
│  scripts/canon-live-readiness.sh  — phase 8 (live transition)     │
│  scripts/agent-shim.sh            — provider-agnostic CLI flags   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼  (canon-cli + canon-templates)
┌─────────────────────────────────────────────────────────────────┐
│  TypeScript runtime (canon-cli + canon-templates)                 │
│  canon/cli/canon-cli.ts                  — agent-callable CLI    │
│  canon/cli/wallet-store.ts               — .canon/wallet.env I/O │
│  canon/templates/polymarket-onboard.ts   — venue adapter         │
│  canon/templates/live-preflight.ts       — TIF + onboarding gate │
│  canon/templates/strategies/<name>/      — strategy bundles      │
└─────────────────────────────────────────────────────────────────┘
```

Each layer is independently testable. The agent layer reads the
markdown and invokes the bash. The bash invokes typed code. Failures
surface up the stack with the lower-layer error message attached.

---

## Slash command resolution

Two `canon-start.md` files coexist:

- **`commands/canon-start.md`** — top-level. Promoted to "user-global"
  via `/apply-core`, which copies it to `~/.claude/commands/canon-start.md`.
  Used when `/canon-start` runs in a directory where no project-local
  override exists.
- **`canon/commands/canon-start.md`** — canon-side. Pulled by
  `canon-scaffold.sh` into a new project's `.claude/commands/` during
  the init phase. Used inside a scaffolded project (project-local
  takes precedence over user-global).

Both files document the same flow but differ in details (e.g. the
canon-side version has explicit import-rewrite logic for the
strategy-bundle copy step). When updating live-mode behavior, edit
**both files**.

For dev/test installs that symlink `~/.degacore/canon/commands` to the
working tree's `canon/commands/`, `canon-scaffold.sh:fetch()` does a
local-first lookup so the scaffolded project gets the symlinked file
instead of the GitHub `main` version.

---

## Phase model

`/canon-start` walks phases linearly. Each phase reads the project
state, performs its job, writes `.canon/state.json` (via
`scripts/terminal-ui-write.sh`), then either continues or exits.

| # | Phase | Trigger | Output |
|---|---|---|---|
| 1 | `init` | `.canon/` missing | `canon-scaffold.sh` copies templates + fetches commands/agents/skills |
| 2 | (detect) | always | Inspects filesystem; writes `phase=<next>` |
| 3 | `init` (continued) | from #2 if `.canon/` missing | `pnpm install` + `canon-cli wallet ensure` |
| 4 | `scaffold` | scaffold files missing | `canon-scaffold.sh --force` |
| 5 | `strategy` | no strategy spec | `AskUserQuestion` → copy bundle to `src/main.ts` |
| 6 | `develop` | tests/lint/tsc fail | run them; fix; iterate |
| 7 | `run` | everything green | launch `canon-runner.sh` (dry-run) |
| 8 | `live` | `--live` flag | run `canon-live-readiness.sh` |

Phase 8 is the only one outside the linear pipeline — it's a separate
**transition** invoked via `/canon-start --live`, requires phase 7 to
have already completed (i.e. `src/main.ts` exists).

---

## State machine

`.canon/state.json` is the single source of truth for the dashboard.
Schema (relevant keys):

```jsonc
{
  "phase": "init|scaffold|strategy|develop|run|live",
  "status": "running|paused|idle|error|deposit-pending|funds-detected|onboarding|ready|timeout",
  "error": null | "string",
  "metrics": {
    "mode": "dry-run|live",
    "eoa": "0x...",          // live phase only
    "safe": "0x...",         // live phase only
    "detected_amount": 1.5,  // live phase only
    "elapsed_secs": 42,      // live phase only
    "runner_pid": 12345
  },
  "logs": [ /* ring buffer, last 50 entries */ ]
}
```

Live-phase status transitions:

```
deposit-pending ─[balance > 0]─▶ funds-detected
       │
       └─[timeout]─▶ timeout (terminal; re-run resumes)

funds-detected ───▶ onboarding ───▶ ready ───▶ running
                       │
                       └─[failure]─▶ error (terminal)
```

`status=timeout` is intentionally terminal-but-resumable: re-running
`/canon-start --live` reads the same EOA address (deterministic from
`.canon/wallet.env`) and resumes polling.

---

## Wallet state lifecycle

`.canon/wallet.env` is mode-0600, gitignored, and accumulates
provisioned values as onboarding progresses. The script that owns
each line:

| Line | Written by | Read by |
|---|---|---|
| `WALLET_PRIVATE_KEY=0x…` | `canon-cli wallet ensure` | `FileWalletStore.getPrivateKey()`, `canon-runner.sh` (sourced) |
| `WALLET_PROXY_ADDRESS=0x…` | `canon-cli onboard --execute` (via `persistFunderAddress`) | `client-polymarket.ts:tradingCredentials()`, `canon-runner.sh` (sourced) |
| `POLYMARKET_BUILDER_API_KEY=…` | `canon-cli onboard --execute` (via `ensureBuilderCreds`) | `polymarket-onboard.ts:loadBuilderConfig()`, relayer auth |
| `POLYMARKET_BUILDER_SECRET=…` | same | same |
| `POLYMARKET_BUILDER_PASSPHRASE=…` | same | same |

`canon-runner.sh` sources `.env` first, then `.canon/wallet.env`, so
canon-managed env values beat any stale `.env` shadow.

`canon/cli/auth.ts:requireAuth` calls `hydrateWalletEnv()` at every
write-command entry, which loads `.canon/wallet.env` into
`process.env` (without overriding values already set). This makes
the CLI work standalone without `canon-runner.sh` sourcing.

---

## Onboarding chain

`canon-cli onboard --execute --fund` runs in this order. Failure at
any step exits non-zero; subsequent steps don't run.

1. **`ensureBuilderCreds(pk)`** (only if `POLYMARKET_BUILDER_*` env
   vars are missing). Two-step CLOB dance:
   1. Create `ClobClient` pinned to the Safe funder
      (`signatureType=POLY_GNOSIS_SAFE`, `funderAddress=Safe`).
   2. `createOrDeriveApiKey()` → trading creds.
   3. Re-init `ClobClient` with creds attached.
   4. `createBuilderApiKey()` → builder creds (key/secret/passphrase).
   Persisted to `.canon/wallet.env`.

2. **`ensureFunder()`**. Polymarket relayer-paid Safe deploy, gated
   on `relay.getDeployed(safeAddress)` for idempotency. The Safe
   address is deterministic from `deriveSafe(eoa, factory)` so this
   step is safe to re-run.

3. **`persistFunderAddress`** writes `WALLET_PROXY_ADDRESS=<safe>` to
   `.canon/wallet.env`. Done immediately after `ensureFunder` so any
   later step can read it from the persisted env.

4. **`ensureApprovals()`**. Single batched Safe transaction that sets
   `MaxUint256` allowance for every required spender — both V1
   (`exchange`, `negRiskExchange`, `negRiskAdapter`,
   `conditionalTokens`) and V2 (`exchangeV2`, `negRiskExchangeV2`).
   ERC-20 spenders covered for collateral; ERC-1155 operators covered
   for outcome tokens. V2 is critical: NegRisk markets fail silently
   without their V2 approvals.

5. **`ensureCreds()`**. Smoke-test that the CLOB recognizes the
   wallet. Returns full L2 creds; doesn't persist them (pmxt-core
   re-derives at runtime).

6. **`ensureFunded(amount?)`** (only when `--fund` is set). Six-call
   batched Safe transaction:
   1. `permit` — register the EIP-2612 off-chain signature.
   2. `transferFrom` — pull native USDC EOA → Safe.
   3. `approve(SwapRouter)` — Uniswap V3 spends native USDC.
   4. `exactInputSingle` — swap native USDC → USDC.e at the cheapest
      fee tier (auto-quotes via QuoterV2 across `[100, 500, 3000]`).
   5. `approve(Onramp)` — Polymarket onramp spends USDC.e.
   6. `wrap` — convert USDC.e → pUSD inside the Safe.

   0.5% slippage tolerance on the Uniswap leg. Quote attempted at
   each fee tier in order; throws if no pool returns a quote.

---

## Live-runner flow

`canon-runner.sh --live` does the following before `tsx src/main.ts --live`:

1. Guards: must be in a Canon project root (`src/main.ts` exists).
2. Guards: no other runner already running (PID file check).
3. Sources `.env`, then `.canon/wallet.env` — populates `process.env`.
4. Writes initial dashboard state (`metric.mode=live`).
5. Installs `cleanup` trap (kills child, removes PID file, writes
   final dashboard state on exit/signal).
6. Forwards `INT`/`TERM` to the child for graceful stop.
7. Spawns `pnpm exec tsx src/main.ts --live` in the background.

Once `tsx` is running, `canon-runner.sh` tails the log via a FIFO and
parses tagged output (`SCAN`, `NO_EDGE`, `SIGNAL`, `SCAN_ERROR`,
`STOP`) to update dashboard metrics in real time. A watcher process
polls runner liveness and kills the tail when the runner dies, so
the parsing loop gets EOF instead of blocking forever.

Inside `tsx`, the strategy entry point (e.g. `trade-momentum/entry.ts`)
calls `assertLiveCapabilities()` which delegates to the shared
`assertReadyForLive()` from `canon/templates/live-preflight.ts`:

1. **TIF gate** — refuses to start if the pmxt sidecar doesn't
   advertise the strategy's required time-in-force (`GTC` for
   passive entries, `FOK` for arbs).
2. **Onboarding gate** — calls
   `polymarketOnboard.build(pk).status()` and refuses if
   `funderDeployed`/`approvalsReady`/`credsReady` is false or
   collateral is zero.
3. **Auth smoke** (optional, strategy-provided) — for trade-momentum,
   calls `fetchBalance()` to confirm the L2 creds work.

If any gate fails, the strategy logs an actionable error and exits
non-zero. `canon-runner.sh`'s cleanup trap flips the dashboard to
`status=error`.

---

## Watchdog (orch + canon)

For the orchestrator (separate from canon-runner — used by `/plan`
and `/fix-issue`), `scripts/orch-engine.sh` installs an EXIT/INT/TERM
trap that writes `status=failed` if the engine dies ungracefully. A
heartbeat reaper (`orch_state_reap_stale` in `scripts/orch-state.sh`,
invoked by `orch-run.sh` at startup) sweeps any preexisting
`state.json` whose heartbeat is older than `ORCH_STALE_HEARTBEAT_SECS`
(default 120s) and flips them to `status=aborted`.

Both ensure canon-tui's plan-execution panel never renders "● LIVE"
for a corpse.

---

## Adding a new venue

The venue interface is `OnboardClient` in
[`canon/templates/types/OnboardClient.ts`](../canon/templates/types/OnboardClient.ts).
Every adapter implements:

- `status()` — read-only state snapshot.
- `ensureFunder()` — deploy the funding contract (Safe / proxy / EOA).
- `ensureApprovals()` — set spender allowances.
- `ensureCreds()` — derive/create CLOB API creds.
- `ensureFunded(amount?)` — gasless EOA → funder transfer + collateral
  conversion.

A `MarketVenueOnboard` registry hook in
[`canon/templates/types/MarketVenueOnboard.ts`](../canon/templates/types/MarketVenueOnboard.ts)
declares `{ venue, chainId, build(pk) }`. The CLI picks the adapter
via `--venue <name>`.

The contract test
[`canon/templates/__tests__/onboarding-adapter.test.ts`](../canon/templates/__tests__/onboarding-adapter.test.ts)
runs against any adapter — adding Kalshi means writing a Kalshi
harness and adding one `runAdapterContract(...)` call.

---

## Where to look when something breaks

| Symptom | First place to look |
|---|---|
| `/canon-start --live` doesn't recognize the flag | `~/.claude/commands/canon-start.md` (user-global) and `<project>/.claude/commands/canon-start.md` (project-local) — both must have the live-mode short-circuit |
| Live runner placing orders with `funder=EOA` | `WALLET_PROXY_ADDRESS` not in `process.env` — check `.canon/wallet.env` and confirm `canon-runner.sh` sources it |
| Onboarding hangs on relayer 401 | `POLYMARKET_BUILDER_*` env unset; bootstrap must run. Check `canon-cli onboard --execute --fund --venue polymarket` output |
| Cloudflare 403 on every CLOB call | `clob-axios-defaults.ts` UA override didn't load before SDK import — verify `import "./clob-axios-defaults.js"` is the first import in `polymarket-onboard.ts` |
| TUI shows "● LIVE" for a dead engine | Watchdog isn't reaping — check `orch_state_reap_stale` runs at `orch-run.sh` startup and the engine's EXIT/INT/TERM trap is installed |
| Strategy refuses live with `assertReadyForLive` error | One of the four onboarding flags is false; run `canon-cli onboard --status --venue polymarket` |
