/**
 * MINT-04 Market Making Premium — Project Entry Point
 *
 * Wires the real Polymarket client into the mm-premium strategy:
 *   - `--live`     → submits real CLOB GTC limit sell orders via
 *                    `createLiveExecutor`. The YES sell leg of each
 *                    cycle flows through the production live executor.
 *   - default      → dry-run (production safety: no flag never trades).
 *
 * A complete MINT-04 cycle is:
 *   1. `splitPosition($cycleCapital)` — mint matched YES + NO pairs.
 *   2. Post YES sell-limit at midpoint + offsetC.
 *   3. Post NO  sell-limit at (1 − midpoint) + offsetC.
 *   4. 24h reconcile / kill remaining.
 *
 * Steps 1 + 3 + 4 are not yet wired here — they require a cycle loop
 * mirroring `strategies/mint-01/cycle.ts`. The current bootstrap covers
 * the live executor + allowance + sidecar preflight pieces shared with
 * the rest of the live-capable templates; the cycle loop is the
 * follow-up. The exposed `createEntryDeps` is the production seam
 * exercised by unit tests.
 */

import { pathToFileURL } from "node:url";

import { appendEntry } from "../../execution-log.js";
import type { ExecutionLogEntry } from "../../execution-log.js";
import {
  fetchBinaryMarketSnapshots,
  getCapabilities,
} from "../../client-polymarket.js";
import { createLiveExecutor } from "../../live-executor.js";
import type {
  AllowanceClient,
  ResolvedOrder,
} from "../../live-executor.js";
import { createLivePositions } from "../../live-positions.js";
import {
  DEFAULT_ALLOWANCE_SPENDER,
  USDC_E_ADDRESS,
} from "../../polygon-addresses.js";
import type {
  ExecutorDeps,
  PositionDeps,
} from "../../runner.js";
import { createUsdcAllowanceClient } from "../../usdc-allowance.js";
import type { TradeSignal } from "../../types/TradeSignal.js";
import type { WalletStore } from "../../wallet-store.js";

import { DEFAULT_MM_PREMIUM_CONFIG } from "./config.js";
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
}

/** Live executor + positions + scan adapters wired for the runner. */
export interface EntryDeps {
  scan: ScanDeps;
  executor: ExecutorDeps;
  positions: PositionDeps;
}

/** Parse `process.argv` into entry flags. `--live` opts in to live execution. */
export function parseEntryFlags(argv: readonly string[]): EntryFlags {
  if (argv.includes("--live")) return { dryRun: false };
  return { dryRun: true };
}

/**
 * Resolve a mint-premium signal to (tokenIds, price).
 *
 * The current strategy emits a single `sell_yes` signal per viable
 * cycle; the live executor sells YES at midpoint + offsetC. TIF is GTC
 * (resting limit, urgency `opportunistic`). The NO leg + splitPosition
 * mint are handled by the (pending) cycle loop, mirroring
 * `mint-01/cycle.ts`.
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
  allowance?: AllowanceClient;
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
  return { scan, executor, positions };
}

/**
 * `--live` start-up safety gate.
 *
 * Refuses to start when the running pmxt sidecar does not advertise
 * `supportsTif`. MINT-04 uses GTC limit orders for the premium sell
 * legs; degrading would convert resting quotes into aggressive takers.
 */
export async function assertLiveCapabilities(): Promise<void> {
  const caps = await getCapabilities();
  if (!caps.supportsTif) {
    throw new Error(
      "MINT-04 --live: pmxt sidecar does not advertise GTC time-in-force " +
        "support; refusing to run.",
    );
  }
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
    spenderAddress: DEFAULT_ALLOWANCE_SPENDER,
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

async function loadCanonWalletStore(): Promise<WalletStore> {
  const specifier = "../../../cli/wallet-store.js";
  const mod = (await import(/* @vite-ignore */ specifier)) as {
    FileWalletStore: new () => WalletStore;
  };
  return new mod.FileWalletStore();
}

async function main(): Promise<void> {
  const flags = parseEntryFlags(process.argv);
  const pollIntervalMs = Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

  if (!flags.dryRun) {
    await assertLiveCapabilities();
  }

  const wallet: WalletStore | undefined = flags.dryRun
    ? undefined
    : await loadCanonWalletStore();
  const allowance =
    wallet !== undefined ? await buildLiveAllowanceClient(wallet) : undefined;
  const { scan, executor, positions } = createEntryDeps(
    flags,
    allowance !== undefined ? { allowance } : {},
  );

  const runnerConfig: MintPremiumRunnerConfig = {
    strategy: DEFAULT_MM_PREMIUM_CONFIG,
    runner: {
      pollIntervalMs,
      dryRun: flags.dryRun,
      baseDir: ".canon/execution",
      statePath: ".canon/state.json",
    },
    maxConsecutiveLosses: MAX_CONSECUTIVE_LOSSES,
  };

  const runner = createMintPremiumRunner(runnerConfig, {
    scan,
    executor,
    positions,
    log: (entry: ExecutionLogEntry) =>
      appendEntry(".canon/execution", entry),
  });

  process.stdout.write(
    `START MINT-04 scanner (${flags.dryRun ? "dry-run" : "live"}) ` +
      `poll=${String(pollIntervalMs)}ms\n`,
  );

  try {
    await runner.start();
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stdout.write(`SCAN_ERROR ${msg}\n`);
    process.exitCode = 1;
  }
}

const entryArg = process.argv[1];
const isMain =
  entryArg !== undefined &&
  import.meta.url === pathToFileURL(entryArg).href;

if (isMain) {
  void main();
}
