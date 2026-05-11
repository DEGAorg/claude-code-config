/**
 * MINT-04 Market Making Premium — Project Entry Point
 *
 * Wires the real Polymarket client + CTF mint adapter into the
 * mm-premium strategy:
 *   - `--live`     → runs one full MINT-04 cycle via `runMmPremiumCycle`:
 *                    scan → tiered-offset selection → splitPosition →
 *                    dual leg sell-limit at midpoint ± offsetC → 24h
 *                    reconcile (or stop-loss exit).
 *   - default      → dry-run (production safety: no flag never trades).
 *                    Keeps using the shared scanner runner from `main.ts`,
 *                    which emits a single `sell_yes` advisory per viable
 *                    market without minting or posting orders.
 *
 * The dry-run path and the live cycle share `createEntryDeps` for live-
 * executor + scan wiring; only the live path adds the mint plumbing
 * (`mintClient`, CTF allowance) and the cycle-loop adapters
 * (`fetchOrderStatus`, `fetchMidpoint`, `now`, `sleep`).
 */

import { pathToFileURL } from "node:url";

import {
  formatBankrollBanner,
  resolveBankroll,
} from "../../bankroll.js";
import { appendEntry } from "../../execution-log.js";
import type { ExecutionLogEntry } from "../../execution-log.js";
import {
  fetchBinaryMarketSnapshots,
  fetchMarketPrice,
  fetchOpenOrders,
} from "../../client-polymarket.js";
import type { OrderResponse } from "../../client-polymarket.js";
import { createCtfMintClient } from "../../ctf-mint.js";
import type { CtfMintClient } from "../../ctf-mint.js";
import { assertReadyForLive } from "../../live-preflight.js";
import { createLiveExecutor } from "../../live-executor.js";
import type {
  AllowanceClient,
  LiveExecutor,
  ResolvedOrder,
} from "../../live-executor.js";
import { createLivePositions } from "../../live-positions.js";
import {
  CONDITIONAL_TOKENS_ADDRESS,
  CTF_EXCHANGE_ADDRESS,
  USDC_E_ADDRESS,
} from "../../polygon-addresses.js";
import type { PositionDeps } from "../../runner.js";
import { createUsdcAllowanceClient } from "../../usdc-allowance.js";
import type { TradeSignal } from "../../types/TradeSignal.js";
import { FileWalletStore } from "../../wallet-store.js";
import type { WalletStore } from "../../wallet-store.js";

import { DEFAULT_MM_PREMIUM_CONFIG } from "./config.js";
import { runMmPremiumCycle } from "./cycle.js";
import type { RunMmPremiumCycleDeps } from "./cycle.js";
import { createMintPremiumRunner } from "./main.js";
import type { MintPremiumRunnerConfig } from "./main.js";
import type { ScanDeps } from "./scan.js";
import type { MintPremiumSnapshot } from "./signal.js";

/** Approval is refreshed when current allowance drops below this floor. */
const USDC_ALLOWANCE_THRESHOLD = 100_000_000_000n; // 100k USDC (6 decimals)
/** When refreshing, allowance is set to this target. */
const USDC_ALLOWANCE_TARGET = 1_000_000_000_000n; // 1M USDC
/** Circuit breaker threshold — halts after this many consecutive losses. */
const MAX_CONSECUTIVE_LOSSES = 3;
/** Fallback price when the signal does not carry a midpoint. */
const FALLBACK_PRICE = 0.5;

/** Parsed CLI flags for the mm-premium entry point. */
export interface EntryFlags {
  /** When true, the runner logs signals but does not submit orders. */
  dryRun: boolean;
  /**
   * Optional `--bankroll <amount>` override. Persisted to
   * `.canon/bankroll.json` when present; subsequent runs without the
   * flag read the stored value back.
   */
  bankroll?: number | undefined;
}

/** Live executor + positions + scan adapters wired for the runner. */
export interface EntryDeps {
  scan: ScanDeps;
  executor: LiveExecutor;
  positions: PositionDeps;
  /**
   * CTF mint adapter for `splitPosition` / `mergePositions`. Present
   * only when `options.mintClient` is supplied; `main()` builds it from
   * the `WalletStore` via `buildLiveMintClient` in `--live`.
   */
  mintClient?: CtfMintClient;
  /**
   * USDC→ConditionalTokens allowance client (distinct from the CTF
   * Exchange allowance threaded into the executor). Present only when
   * `options.ctfAllowance` is supplied.
   */
  ctfAllowance?: AllowanceClient;
}

/**
 * Parse `process.argv` into entry flags. `--live` opts in to live
 * execution; `--bankroll <amount>` sets and persists the bankroll
 * (positive USD number); anything else (including no flag) is dry-run.
 */
export function parseEntryFlags(argv: readonly string[]): EntryFlags {
  const dryRun = !argv.includes("--live");

  const flagIndex = argv.indexOf("--bankroll");
  if (flagIndex === -1) {
    return { dryRun };
  }
  const raw = argv[flagIndex + 1];
  if (raw === undefined) {
    throw new Error("--bankroll requires a positive USD amount");
  }
  const amount = Number(raw);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error(`--bankroll must be a positive number, got "${raw}"`);
  }
  return { dryRun, bankroll: amount };
}

/**
 * Resolve a mint-premium signal to (tokenIds, price).
 *
 * Both legs route through the same executor; `direction` picks which
 * side of the pair the order targets (`sell_yes` → YES at midpoint +
 * offsetC, `sell_no` → NO at (1 − midpoint) + offsetC). TIF is GTC.
 */
function resolveMmPremiumOrder(signal: TradeSignal): ResolvedOrder {
  const meta = signal.metadata;
  const yesTokenIdRaw = meta["yesTokenId"];
  const noTokenIdRaw = meta["noTokenId"];
  const midpointRaw = meta["midpoint"];
  const offsetCRaw = meta["offsetC"];

  const yesTokenId =
    typeof yesTokenIdRaw === "string" && yesTokenIdRaw.length > 0
      ? yesTokenIdRaw
      : `${signal.market.market_id}:yes`;
  const noTokenId =
    typeof noTokenIdRaw === "string" && noTokenIdRaw.length > 0
      ? noTokenIdRaw
      : `${signal.market.market_id}:no`;
  const midpoint =
    typeof midpointRaw === "number" ? midpointRaw : FALLBACK_PRICE;
  const offsetC = typeof offsetCRaw === "number" ? offsetCRaw : 0;

  const isNoLeg =
    signal.direction === "sell_no" || signal.direction === "buy_no";
  const yesPrice = midpoint + offsetC;
  const noPrice = 1 - midpoint + offsetC;
  const price = isNoLeg ? Math.min(0.99, noPrice) : Math.min(0.99, yesPrice);

  return {
    tokenIds: { yes: yesTokenId, no: noTokenId },
    price,
    timeInForce: "GTC",
  };
}

/** Optional dependencies for `createEntryDeps`. */
export interface CreateEntryDepsOptions {
  /** Inject a USDC→CTFExchange `AllowanceClient` for the sell-limit legs. */
  allowance?: AllowanceClient;
  /**
   * Inject a USDC→ConditionalTokens `AllowanceClient`. The Gnosis CTF
   * contract is a distinct spender from the CTF Exchange (it pulls USDC
   * during `splitPosition`), so a second allowance row is required.
   */
  ctfAllowance?: AllowanceClient;
  /** Inject a CTF mint adapter (real one built by `buildLiveMintClient`). */
  mintClient?: CtfMintClient;
  /** Search query for binary-market snapshots (defaults to empty). */
  query?: string;
}

/** Build live executor + positions + scan adapters for the runner. */
export function createEntryDeps(
  flags: EntryFlags,
  options: CreateEntryDepsOptions = {},
): EntryDeps {
  void flags;
  const executor = createLiveExecutor({
    resolveOrder: resolveMmPremiumOrder,
    ...(options.allowance !== undefined ? { allowance: options.allowance } : {}),
    allowanceThreshold: USDC_ALLOWANCE_THRESHOLD,
    allowanceTarget: USDC_ALLOWANCE_TARGET,
  });
  const positions = createLivePositions();
  const query = options.query ?? "";
  const FAR_FUTURE_MS = 365 * 24 * 60 * 60 * 1000;
  const scan: ScanDeps = {
    fetchSnapshots: async (): Promise<MintPremiumSnapshot[]> => {
      const snapshots = await fetchBinaryMarketSnapshots(query);
      return snapshots.map((s) => ({
        conditionId: s.conditionId,
        question: s.question,
        midpoint: s.yesPrice,
        timeToCloseMs: s.timeToCloseMs ?? FAR_FUTURE_MS,
        volume24h: s.volume24h,
        yesTokenId: s.yesTokenId,
        noTokenId: s.noTokenId,
      }));
    },
  };
  return {
    scan,
    executor,
    positions,
    ...(options.mintClient !== undefined ? { mintClient: options.mintClient } : {}),
    ...(options.ctfAllowance !== undefined
      ? { ctfAllowance: options.ctfAllowance }
      : {}),
  };
}

/**
 * `--live` start-up safety gate.
 *
 * Delegates to the shared `assertReadyForLive` helper. MINT-04 uses GTC
 * limit orders for the premium sell legs; degrading would convert
 * resting quotes into aggressive takers.
 */
export async function assertLiveCapabilities(): Promise<void> {
  await assertReadyForLive({
    strategyName: "MINT-04",
    requiredTif: "GTC",
  });
}

/** Build a live USDC allowance client from an injected `WalletStore`. */
export async function buildLiveAllowanceClient(
  wallet: WalletStore,
): Promise<AllowanceClient | undefined> {
  if (!wallet.hasWallet()) return undefined;

  let ownerAddress: string;
  try {
    ownerAddress = await wallet.getAddress();
  } catch {
    return undefined;
  }

  const rpcUrl =
    process.env["POLYGON_RPC_URL"] ?? "https://polygon.drpc.org";

  return createUsdcAllowanceClient({
    ownerAddress,
    spenderAddress: CTF_EXCHANGE_ADDRESS,
    usdcAddress: USDC_E_ADDRESS,
    getProvider: async () => {
      const { providers } = await import("ethers");
      return new providers.JsonRpcProvider(rpcUrl);
    },
    getSigner: async () => {
      const { Wallet, providers } = await import("ethers");
      return new Wallet(
        wallet.getPrivateKey(),
        new providers.JsonRpcProvider(rpcUrl),
      );
    },
  });
}

/**
 * Build a USDC allowance client whose spender is the Gnosis
 * ConditionalTokens contract.
 *
 * Mirrors `buildLiveAllowanceClient` exactly, but swaps the spender to
 * `CONDITIONAL_TOKENS_ADDRESS`. MINT-04 needs both rows: the CTF Exchange
 * allowance lets the sell-limit legs settle, while the ConditionalTokens
 * allowance lets `splitPosition` pull USDC.e from the wallet.
 */
export async function buildCtfAllowanceClient(
  wallet: WalletStore,
): Promise<AllowanceClient | undefined> {
  if (!wallet.hasWallet()) return undefined;

  let ownerAddress: string;
  try {
    ownerAddress = await wallet.getAddress();
  } catch {
    return undefined;
  }

  const rpcUrl =
    process.env["POLYGON_RPC_URL"] ?? "https://polygon.drpc.org";

  return createUsdcAllowanceClient({
    ownerAddress,
    spenderAddress: CONDITIONAL_TOKENS_ADDRESS,
    usdcAddress: USDC_E_ADDRESS,
    getProvider: async () => {
      const { providers } = await import("ethers");
      return new providers.JsonRpcProvider(rpcUrl);
    },
    getSigner: async () => {
      const { Wallet, providers } = await import("ethers");
      return new Wallet(
        wallet.getPrivateKey(),
        new providers.JsonRpcProvider(rpcUrl),
      );
    },
  });
}

/**
 * Build a live `CtfMintClient` from an injected `WalletStore`.
 *
 * Returns `undefined` when the store has no wallet or when resolving the
 * address fails — `main()` then skips the mint plumbing rather than
 * crashing the strategy boot. Construction is lazy: the inner
 * `getSigner` / `getProvider` hooks are only invoked when
 * `splitPosition` / `mergePositions` actually fires.
 */
export async function buildLiveMintClient(
  wallet: WalletStore,
): Promise<CtfMintClient | undefined> {
  if (!wallet.hasWallet()) return undefined;

  try {
    await wallet.getAddress();
  } catch {
    return undefined;
  }

  const rpcUrl =
    process.env["POLYGON_RPC_URL"] ?? "https://polygon.drpc.org";

  return createCtfMintClient({
    conditionalTokensAddress: CONDITIONAL_TOKENS_ADDRESS,
    collateralAddress: USDC_E_ADDRESS,
    getProvider: async () => {
      const { providers } = await import("ethers");
      return new providers.JsonRpcProvider(rpcUrl);
    },
    getSigner: async () => {
      const { Wallet, providers } = await import("ethers");
      return new Wallet(
        wallet.getPrivateKey(),
        new providers.JsonRpcProvider(rpcUrl),
      );
    },
  });
}

/**
 * Build the `RunMmPremiumCycleDeps` consumed by `runMmPremiumCycle` from
 * a live `EntryDeps` plus the resolved strategy config.
 *
 * Wires the venue-neutral fetchers exported by `client-polymarket` into
 * the `fetchOrderStatus` / `fetchMidpoint` adapters the cycle expects:
 *
 *   - `fetchOrderStatus(id)` — polls `fetchOpenOrders()` for the live id;
 *     if the order is no longer in the open set the orchestrator treats
 *     it as `filled` (sidecar drops cancelled/filled orders from the open
 *     listing). Cancelled legs surface via the same path because
 *     `executor.cancel` removes them from `fetchOpenOrders`.
 *   - `fetchMidpoint(conditionId)` — reads the YES-side price as the
 *     midpoint signal, matching the scan adapter's `yesPrice → midpoint`
 *     mapping in `scan.ts`.
 *
 * Sleep uses `setTimeout` and `now` uses `Date.now` so the cycle's 24h
 * deadline math runs against real wall-clock time.
 */
function buildLiveCycleDeps(args: {
  executor: LiveExecutor;
  mintClient: CtfMintClient;
  scan: ScanDeps;
  config: RunMmPremiumCycleDeps["config"];
}): RunMmPremiumCycleDeps {
  return {
    config: args.config,
    scan: args.scan,
    mintClient: args.mintClient,
    executor: args.executor,
    fetchOrderStatus: async (orderId: string): Promise<OrderResponse> => {
      const open = await fetchOpenOrders();
      const found = open.find((o) => o.id === orderId);
      if (found !== undefined) return found;
      return {
        id: orderId,
        marketId: "",
        outcomeId: "",
        side: "sell",
        type: "limit",
        amount: 0,
        price: 0,
        status: "filled",
        filled: 0,
        remaining: 0,
      };
    },
    fetchMidpoint: async (conditionId: string): Promise<number> => {
      const price = await fetchMarketPrice(conditionId);
      return price.yes;
    },
    log: (entry: ExecutionLogEntry) => appendEntry(".", entry),
    now: () => Date.now(),
    sleep: (ms: number) =>
      new Promise<void>((resolve) => {
        setTimeout(resolve, ms);
      }),
  };
}

/** Options accepted by `main()`. Tests inject `argv` + a `wallet`. */
export interface MainOptions {
  /** Override the argv used for flag parsing (defaults to `process.argv`). */
  argv?: readonly string[];
  /** Override the wallet store. Tests inject a fake; live runs use `FileWalletStore`. */
  wallet?: WalletStore;
}

export async function main(opts: MainOptions = {}): Promise<void> {
  const argv = opts.argv ?? process.argv;
  const flags = parseEntryFlags(argv);
  const pollIntervalMs = Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

  if (!flags.dryRun) {
    await assertLiveCapabilities();
  }

  const wallet: WalletStore | undefined = flags.dryRun
    ? undefined
    : (opts.wallet ?? new FileWalletStore());
  const allowance =
    wallet !== undefined ? await buildLiveAllowanceClient(wallet) : undefined;
  const ctfAllowance =
    wallet !== undefined ? await buildCtfAllowanceClient(wallet) : undefined;
  const mintClient =
    wallet !== undefined ? await buildLiveMintClient(wallet) : undefined;

  const deps = createEntryDeps(flags, {
    ...(allowance !== undefined ? { allowance } : {}),
    ...(ctfAllowance !== undefined ? { ctfAllowance } : {}),
    ...(mintClient !== undefined ? { mintClient } : {}),
  });

  const bankroll = await resolveBankroll({
    override: flags.bankroll,
    dryRun: flags.dryRun,
    dryRunDefault: DEFAULT_MM_PREMIUM_CONFIG.bankroll,
    fetchPortfolio: () => deps.positions.reconcile(),
  });
  process.stdout.write(`${formatBankrollBanner(bankroll)}\n`);

  const config = { ...DEFAULT_MM_PREMIUM_CONFIG, bankroll: bankroll.amount };

  process.stdout.write(
    `START MINT-04 ${flags.dryRun ? "scanner (dry-run)" : "cycle (live)"} ` +
      `poll=${String(pollIntervalMs)}ms\n`,
  );

  if (flags.dryRun) {
    const runnerConfig: MintPremiumRunnerConfig = {
      strategy: config,
      runner: {
        pollIntervalMs,
        dryRun: true,
        baseDir: ".",
        statePath: ".canon/state.json",
      },
      maxConsecutiveLosses: MAX_CONSECUTIVE_LOSSES,
    };
    const runner = createMintPremiumRunner(runnerConfig, {
      scan: deps.scan,
      executor: deps.executor,
      positions: deps.positions,
      log: (entry: ExecutionLogEntry) => appendEntry(".", entry),
    });
    try {
      await runner.start();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      process.stdout.write(`SCAN_ERROR ${msg}\n`);
      process.exitCode = 1;
    }
    return;
  }

  if (deps.mintClient === undefined) {
    throw new Error(
      "MINT-04: --live requires a wallet at .canon/wallet.env " +
        "(run `canon-cli wallet ensure`).",
    );
  }

  await runMmPremiumCycle(
    buildLiveCycleDeps({
      executor: deps.executor,
      mintClient: deps.mintClient,
      scan: deps.scan,
      config,
    }),
  );
}

const entryArg = process.argv[1];
const isMain =
  entryArg !== undefined &&
  import.meta.url === pathToFileURL(entryArg).href;

if (isMain) {
  void main();
}
