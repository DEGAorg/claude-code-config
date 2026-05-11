/**
 * MINT-01 Simple Mint Cycle — Project Entry Point
 *
 * Bootstrap module that wires the live Polymarket client and CTF mint
 * adapter into the MINT-01 strategy:
 *
 *   - `--live`     → submits real CLOB sell limits via `createLiveExecutor`
 *                    and mints YES + NO pairs via `ctf-mint.splitPosition`.
 *   - `--dry-run`  → exercises the full pipeline without sending orders or
 *                    on-chain transactions.
 *   - default      → dry-run (production safety: no flag never trades).
 *
 * Mirrors the ARB-01 bootstrap shape (`parseEntryFlags`, `createEntryDeps`,
 * `assertLiveCapabilities`, `buildLiveAllowanceClient`) so the same
 * `WalletStore` injection pattern carries over with no new top-level
 * adapters. Reviewer hooks called from production:
 *
 *   - `selectMarket`  / `planLegs`  — exposed pure helpers from `cycle.ts`,
 *     re-invoked here as `detectMint01Candidate` to produce a CLOB-shaped
 *     pair of TradeSignals (one sell_yes, one sell_no).
 *   - `signalToOrderParams` — reused from `order-executor.ts` via the
 *     shared `live-executor` to keep the integration trace single-source.
 */
import { pathToFileURL } from "node:url";

import {
  fetchBinaryMarketSnapshots,
  fetchMarketPrice,
  fetchOpenOrders,
} from "../../client-polymarket.js";
import type { OrderResponse } from "../../client-polymarket.js";
import { createCtfMintClient } from "../../ctf-mint.js";
import type { CtfMintClient } from "../../ctf-mint.js";
import { appendEntry } from "../../execution-log.js";
import type { ExecutionLogEntry } from "../../execution-log.js";
import { assertReadyForLive } from "../../live-preflight.js";
import { createLiveExecutor } from "../../live-executor.js";
import type {
  AllowanceClient,
  LiveExecutor,
  ResolvedOrder,
} from "../../live-executor.js";
import {
  CONDITIONAL_TOKENS_ADDRESS,
  CTF_EXCHANGE_ADDRESS,
  USDC_E_ADDRESS,
} from "../../polygon-addresses.js";
import { createUsdcAllowanceClient } from "../../usdc-allowance.js";
import type { TradeSignal } from "../../types/TradeSignal.js";
import { FileWalletStore } from "../../wallet-store.js";
import type { WalletStore } from "../../wallet-store.js";

import { DEFAULT_MINT_01_CONFIG } from "./config.js";
import type { Mint01Config } from "./config.js";
import {
  planLegs,
  runCycle,
  selectMarket,
} from "./cycle.js";
import type {
  CycleLegs,
  MarketCandidate,
  MarketChoice,
  RunCycleDeps,
} from "./cycle.js";
import { fetchSnapshots } from "./scan.js";

/** Allowance is refreshed when the cached value drops below this floor. */
const USDC_ALLOWANCE_THRESHOLD = 100_000_000_000n; // 100k USDC.e (6 decimals)
/** When refreshing, allowance is set to this target. */
const USDC_ALLOWANCE_TARGET = 1_000_000_000_000n; // 1M USDC.e

/** Parsed CLI flags for the MINT-01 entry point. */
export interface EntryFlags {
  /** When true, the bootstrap exercises the wiring without submitting. */
  dryRun: boolean;
}

/**
 * Parse `process.argv` into entry flags.
 *
 * `--live` flips to live execution. Anything else (including `--dry-run` or
 * no flag) keeps the safe dry-run default.
 */
export function parseEntryFlags(argv: readonly string[]): EntryFlags {
  if (argv.includes("--live")) return { dryRun: false };
  return { dryRun: true };
}

/**
 * Detect a MINT-01 candidate and emit the two-leg sell-limit signal pair.
 *
 * Composes `selectMarket → planLegs → TradeSignal[]` so the integration
 * trace flows entirely through exposed pure helpers. Returns `null` when
 * no candidate passes the filter gate.
 */
export interface Mint01Candidate {
  /** Market that won the rank in `selectMarket`. */
  choice: MarketChoice;
  /** Legs derived from `planLegs(choice.candidate.midpoint, config)`. */
  legs: CycleLegs;
  /** Two TradeSignals: `[sell_yes, sell_no]` ready for the executor. */
  signals: [TradeSignal, TradeSignal];
}

export function detectMint01Candidate(
  candidates: MarketCandidate[],
  config: Mint01Config = DEFAULT_MINT_01_CONFIG,
): Mint01Candidate | null {
  const choice = selectMarket(candidates, config);
  if (choice === null) return null;
  const legs = planLegs(choice.candidate.midpoint, config);

  // selectMarket guarantees both token ids are present.
  const yesTokenId = choice.candidate.yesTokenId as string;
  const noTokenId = choice.candidate.noTokenId as string;

  const now = new Date();
  const market: TradeSignal["market"] = {
    platform: "polymarket",
    market_id: choice.candidate.conditionId,
    question: choice.candidate.question,
  };
  const baseMetadata: Record<string, unknown> = {
    yesTokenId,
    noTokenId,
    yesPrice: legs.yesPrice,
    noPrice: legs.noPrice,
    entryMidpoint: choice.candidate.midpoint,
    timeInForce: config.timeInForce,
  };

  const yesSignal: TradeSignal = {
    automation_id: "mint-01",
    timestamp: now,
    market,
    direction: "sell_yes",
    size: legs.size,
    confidence: 1,
    urgency: "normal",
    metadata: { ...baseMetadata, leg: "yes" },
  };
  const noSignal: TradeSignal = {
    automation_id: "mint-01",
    timestamp: now,
    market: { ...market },
    direction: "sell_no",
    size: legs.size,
    confidence: 1,
    urgency: "normal",
    metadata: { ...baseMetadata, leg: "no" },
  };

  return { choice, legs, signals: [yesSignal, noSignal] };
}

/**
 * Resolve a MINT-01 TradeSignal to the `(tokenIds, price, tif)` triple the
 * live executor needs. Reads token ids and the per-leg price out of the
 * signal metadata produced by `detectMint01Candidate`.
 */
export function resolveMint01Order(signal: TradeSignal): ResolvedOrder {
  const meta = signal.metadata;
  const yesTokenId = meta["yesTokenId"];
  const noTokenId = meta["noTokenId"];
  if (typeof yesTokenId !== "string" || yesTokenId.length === 0) {
    throw new Error("mint-01: signal.metadata.yesTokenId missing");
  }
  if (typeof noTokenId !== "string" || noTokenId.length === 0) {
    throw new Error("mint-01: signal.metadata.noTokenId missing");
  }

  const isYesLeg = signal.direction === "sell_yes";
  const priceKey = isYesLeg ? "yesPrice" : "noPrice";
  const priceRaw = meta[priceKey];
  if (typeof priceRaw !== "number") {
    throw new Error(`mint-01: signal.metadata.${priceKey} must be a number`);
  }
  const tifRaw = meta["timeInForce"];
  const timeInForce: "GTC" | "FOK" =
    tifRaw === "FOK" ? "FOK" : "GTC";

  return {
    tokenIds: { yes: yesTokenId, no: noTokenId },
    price: priceRaw,
    timeInForce,
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
}

/** Live deps returned by `createEntryDeps`. */
export interface EntryDeps {
  executor: LiveExecutor;
  /**
   * CTF mint adapter for `splitPosition` / `mergePositions`. Present only
   * when `options.mintClient` is supplied; `main()` builds it from the
   * `WalletStore` via `buildLiveMintClient`.
   */
  mintClient?: CtfMintClient;
  /**
   * USDC→ConditionalTokens allowance client (distinct from the CTF Exchange
   * allowance threaded into the executor). Present only when
   * `options.ctfAllowance` is supplied.
   */
  ctfAllowance?: AllowanceClient;
}

/**
 * Build the live executor + mint plumbing consumed by the MINT-01 cycle.
 *
 * Both legs are resolved by `resolveMint01Order` (same module), so the
 * executor produces CLOB-shaped order params for either `sell_yes` or
 * `sell_no` based on `signal.direction`. When `options.allowance` is
 * provided, the executor consults it before each submit and tops up
 * to `USDC_ALLOWANCE_TARGET` when below `USDC_ALLOWANCE_THRESHOLD`.
 *
 * `mintClient` and `ctfAllowance` mirror the `allowance` injection
 * pattern: both are passthrough seams populated by `main()` in live mode
 * and by tests with fakes. They are exposed verbatim on the returned
 * `EntryDeps` so `runCycle` can consume the live `CtfMintClient` and the
 * caller can run the CTF allowance top-up independently.
 */
export function createEntryDeps(
  flags: EntryFlags,
  options: CreateEntryDepsOptions = {},
): EntryDeps {
  void flags;
  const executor = createLiveExecutor({
    resolveOrder: resolveMint01Order,
    ...(options.allowance !== undefined ? { allowance: options.allowance } : {}),
    allowanceThreshold: USDC_ALLOWANCE_THRESHOLD,
    allowanceTarget: USDC_ALLOWANCE_TARGET,
  });
  return {
    executor,
    ...(options.mintClient !== undefined ? { mintClient: options.mintClient } : {}),
    ...(options.ctfAllowance !== undefined
      ? { ctfAllowance: options.ctfAllowance }
      : {}),
  };
}

/**
 * `--live` start-up safety gate.
 *
 * MINT-01 places GTC sell limits — strictly speaking, GTC works on any
 * sidecar — but the same `supportsTif` check applies because the
 * executor forwards `timeInForce` regardless. A sidecar that drops `tif`
 * would silently default to whatever the exchange default is, breaking
 * the per-leg semantics this strategy depends on.
 */
export async function assertLiveCapabilities(): Promise<void> {
  await assertReadyForLive({
    strategyName: "MINT-01",
    requiredTif: "GTC",
    tifReason: "See docs/reviews/261-open-questions.md (Q-5).",
  });
}

/**
 * Build a live USDC allowance client from an injected `WalletStore`.
 *
 * Mirrors the ARB-01 bootstrap edge: the templates layer never imports
 * `canon/cli` at compile time; the `WalletStore` is supplied by `main()`
 * at runtime. Returns `undefined` when the store has no wallet or when
 * resolving the address fails — `main()` then skips allowance plumbing.
 */
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
 * `CONDITIONAL_TOKENS_ADDRESS`. MINT-01 needs both rows: the CTF Exchange
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
 * Build the `RunCycleDeps` consumed by `runCycle` from a live `EntryDeps`.
 *
 * Wires the venue-neutral fetchers exported by `client-polymarket` into
 * the `fetchOrderStatus` / `fetchMidpoint` adapters `runCycle` expects:
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
 * deadline math runs against real wall-clock time. The strategy config
 * is the pinned `DEFAULT_MINT_01_CONFIG`.
 */
export function buildLiveCycleDeps(deps: {
  executor: LiveExecutor;
  mintClient: CtfMintClient;
}): RunCycleDeps {
  return {
    config: DEFAULT_MINT_01_CONFIG,
    scan: {
      fetchSnapshots: () => fetchSnapshots({ fetchBinaryMarketSnapshots }),
    },
    mintClient: deps.mintClient,
    executor: deps.executor,
    fetchOrderStatus: async (orderId: string): Promise<OrderResponse> => {
      const open = await fetchOpenOrders();
      const found = open.find((o) => o.id === orderId);
      if (found !== undefined) return found;
      // Order has fallen out of the open set: the CLOB sidecar drops
      // cancelled and filled orders from `fetchOpenOrders`, so a missing
      // id is terminal. Reporting it as "filled" lets the orchestrator
      // settle the leg without an extra HTTP round-trip.
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

  if (!flags.dryRun) {
    await assertLiveCapabilities();
  }

  const wallet: WalletStore | undefined = flags.dryRun
    ? undefined
    : (opts.wallet ?? new FileWalletStore());
  const allowance =
    wallet !== undefined
      ? await buildLiveAllowanceClient(wallet)
      : undefined;
  const ctfAllowance =
    wallet !== undefined
      ? await buildCtfAllowanceClient(wallet)
      : undefined;
  const mintClient =
    wallet !== undefined ? await buildLiveMintClient(wallet) : undefined;

  const deps = createEntryDeps(flags, {
    ...(allowance !== undefined ? { allowance } : {}),
    ...(ctfAllowance !== undefined ? { ctfAllowance } : {}),
    ...(mintClient !== undefined ? { mintClient } : {}),
  });

  process.stdout.write(
    `START MINT-01 cycle (${flags.dryRun ? "dry-run" : "live"})\n`,
  );

  if (flags.dryRun) return;

  if (deps.mintClient === undefined) {
    throw new Error(
      "MINT-01: --live requires a wallet at .canon/wallet.env " +
        "(run `canon-cli wallet ensure`).",
    );
  }

  await runCycle(
    buildLiveCycleDeps({ executor: deps.executor, mintClient: deps.mintClient }),
  );
}

const entryArg = process.argv[1];
const isMain =
  entryArg !== undefined &&
  import.meta.url === pathToFileURL(entryArg).href;

if (isMain) {
  void main();
}
