/**
 * TRADE-02 Momentum Trading — Project Entry Point
 *
 * Wires the real Polymarket client into the trade-momentum strategy:
 *   - `--live`     → submits real CLOB GTC limit orders via `createLiveExecutor`.
 *   - default      → dry-run (production safety: no flag never trades).
 *
 * The bootstrap exposes pure factories (`parseEntryFlags`, `createEntryDeps`,
 * `assertLiveCapabilities`, `buildLiveAllowanceClient`) so unit tests can
 * exercise the wiring without starting the poll loop.
 *
 * `topWalletShare` is not surfaced by the pmxt SDK; the manipulation
 * guard reads 0 until an on-chain indexer is wired (Phase 2/3).
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

import { DEFAULT_TRADE_MOMENTUM_CONFIG } from "./config.js";
import { createTradeMomentumRunner } from "./main.js";
import type { TradeMomentumRunnerConfig } from "./main.js";
import type { ScanDeps, TradeMomentumSnapshot } from "./scan.js";

/** Approval is refreshed when current allowance drops below this floor. */
const USDC_ALLOWANCE_THRESHOLD = 100_000_000_000n; // 100k USDC (6 decimals)
/** When refreshing, allowance is set to this target. */
const USDC_ALLOWANCE_TARGET = 1_000_000_000_000n; // 1M USDC
/** Circuit breaker threshold — halts after this many consecutive losses. */
const MAX_CONSECUTIVE_LOSSES = 3;
/** Fallback price when the signal does not carry an entry price. */
const FALLBACK_PRICE = 0.5;

/** Parsed CLI flags for the trade-momentum entry point. */
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

/**
 * Parse `process.argv` into entry flags. `--live` opts in to live
 * execution; anything else (including no flag) is dry-run.
 */
export function parseEntryFlags(argv: readonly string[]): EntryFlags {
  if (argv.includes("--live")) return { dryRun: false };
  return { dryRun: true };
}

/**
 * Resolve a momentum signal to (tokenIds, price). TRADE-02 always buys
 * YES on a single binary market; the limit price is the snapshot
 * midpoint at signal time. Time-in-force is GTC (resting limit) — the
 * urgency is `normal`, not `immediate`.
 */
function resolveMomentumOrder(signal: TradeSignal): ResolvedOrder {
  const meta = signal.metadata;
  const yesTokenIdRaw = meta["yesTokenId"];
  const noTokenIdRaw = meta["noTokenId"];
  const entryPriceRaw = meta["entryPrice"];

  const yesTokenId =
    typeof yesTokenIdRaw === "string" && yesTokenIdRaw.length > 0
      ? yesTokenIdRaw
      : `${signal.market.market_id}:yes`;
  const noTokenId =
    typeof noTokenIdRaw === "string" && noTokenIdRaw.length > 0
      ? noTokenIdRaw
      : `${signal.market.market_id}:no`;
  const price =
    typeof entryPriceRaw === "number" ? entryPriceRaw : FALLBACK_PRICE;

  return {
    tokenIds: { yes: yesTokenId, no: noTokenId },
    price,
    timeInForce: "GTC",
  };
}

/** Map a binary-market snapshot to the trade-momentum scan input. */
function toMomentumSnapshot(s: {
  conditionId: string;
  question: string;
  yesTokenId: string;
  noTokenId: string;
  yesPrice: number;
  volume24h: number;
  openInterest: number;
  timeToCloseMs?: number;
  timestampMs: number;
}): TradeMomentumSnapshot {
  // pmxt SDK does not surface `topWalletShare`; strategies that depend
  // on the manipulation guard must layer an on-chain indexer.
  const FAR_FUTURE_MS = 365 * 24 * 60 * 60 * 1000;
  return {
    conditionId: s.conditionId,
    question: s.question,
    yesTokenId: s.yesTokenId,
    noTokenId: s.noTokenId,
    midpoint: s.yesPrice,
    volume: s.volume24h,
    openInterest: s.openInterest,
    topWalletShare: 0,
    timeToCloseMs: s.timeToCloseMs ?? FAR_FUTURE_MS,
    timestampMs: s.timestampMs,
  };
}

/** Optional dependencies for `createEntryDeps`. */
export interface CreateEntryDepsOptions {
  allowance?: AllowanceClient;
  /** Override the search query (defaults to `config.category` or empty). */
  query?: string;
}

/** Build live executor + positions + scan adapters for the runner. */
export function createEntryDeps(
  flags: EntryFlags,
  options: CreateEntryDepsOptions = {},
): EntryDeps {
  void flags;
  const executor = createLiveExecutor({
    resolveOrder: resolveMomentumOrder,
    ...(options.allowance !== undefined ? { allowance: options.allowance } : {}),
    allowanceThreshold: USDC_ALLOWANCE_THRESHOLD,
    allowanceTarget: USDC_ALLOWANCE_TARGET,
  });
  const positions = createLivePositions();
  const query =
    options.query ?? DEFAULT_TRADE_MOMENTUM_CONFIG.category ?? "";
  const scan: ScanDeps = {
    fetchSnapshots: async (): Promise<TradeMomentumSnapshot[]> => {
      const snapshots = await fetchBinaryMarketSnapshots(query);
      return snapshots.map(toMomentumSnapshot);
    },
  };
  return { scan, executor, positions };
}

/**
 * `--live` start-up safety gate.
 *
 * Refuses to start when the running pmxt sidecar does not advertise
 * `supportsTif`. TRADE-02 uses GTC limit orders; degrading to a market
 * order would convert a passive entry into an aggressive taker.
 */
export async function assertLiveCapabilities(): Promise<void> {
  const caps = await getCapabilities();
  if (!caps.supportsTif) {
    throw new Error(
      "TRADE-02 --live: pmxt sidecar does not advertise GTC time-in-force " +
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
  // MOMENTUM_QUERY defaults to "NBA" — empty queries return the entire
  // Polymarket market index (>60s) and were observed to hang the runner.
  // Operators must pin a category for live or dry-run to be usable.
  const queryEnv = process.env["MOMENTUM_QUERY"];
  const query =
    queryEnv !== undefined && queryEnv.length > 0 ? queryEnv : "NBA";
  const { scan, executor, positions } = createEntryDeps(flags, {
    ...(allowance !== undefined ? { allowance } : {}),
    query,
  });

  // Hard cap on submitted orders per process run — bounds blast radius
  // when --live is set without operator hand-holding. Default 3.
  const maxOrders = Number(process.env["MAX_ORDERS"]) || 3;
  let submittedCount = 0;

  const runnerConfig: TradeMomentumRunnerConfig = {
    strategy: DEFAULT_TRADE_MOMENTUM_CONFIG,
    runner: {
      pollIntervalMs,
      dryRun: flags.dryRun,
      baseDir: ".canon/execution",
      statePath: ".canon/state.json",
    },
    maxConsecutiveLosses: MAX_CONSECUTIVE_LOSSES,
  };

  // Wrap executor.submit to enforce the per-run max-orders cap.
  const cappedExecutor: ExecutorDeps = {
    submit: async (signal) => {
      if (submittedCount >= maxOrders) {
        process.stdout.write(
          `MAX_ORDERS reached (${String(maxOrders)}) — skipping submit\n`,
        );
        return { id: "max-orders-skipped", status: "rejected" };
      }
      submittedCount += 1;
      return executor.submit(signal);
    },
  };

  const runner = createTradeMomentumRunner(runnerConfig, {
    scan,
    executor: cappedExecutor,
    positions,
    log: (entry: ExecutionLogEntry) =>
      appendEntry(".canon/execution", entry),
  });

  process.stdout.write(
    `START TRADE-02 scanner (${flags.dryRun ? "dry-run" : "live"}) ` +
      `query=${query} max_orders=${String(maxOrders)} ` +
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
