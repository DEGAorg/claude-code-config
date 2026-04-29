/**
 * ARB-01 Binary Arbitrage — Project Entry Point
 *
 * Wires the real Polymarket client into the arb-binary strategy:
 *   - `--live`     → submits real CLOB orders via `createLiveExecutor`.
 *   - `--dry-run`  → runs the full pipeline (scan, signal, risk) but the
 *                    runner skips order submission.
 *   - default      → dry-run (production safety: no flag never trades).
 *
 * The bootstrap exposes pure factories (`parseEntryFlags`, `createEntryRisk`,
 * `createEntryDeps`) so unit tests can exercise the wiring without starting
 * the poll loop. `runner.start()` only fires when the file is the process
 * entry point.
 */

import { pathToFileURL } from "node:url";

import { appendEntry } from "../../execution-log.js";
import {
  fetchOrderBook,
  searchMarkets,
} from "../../client-polymarket.js";
import { createLiveExecutor } from "../../live-executor.js";
import type { ResolvedOrder } from "../../live-executor.js";
import { createLivePositions } from "../../live-positions.js";
import { createRunner } from "../../runner.js";
import type { ExecutorDeps, PositionDeps } from "../../runner.js";
import type { ExecutionLogEntry } from "../../execution-log.js";
import type { TradeSignal } from "../../types/TradeSignal.js";

import { DEFAULT_ARB_BINARY_CONFIG } from "./config.js";
import type { ArbBinaryRisk } from "./risk.js";
import { createRiskChecker } from "./risk.js";
import { scanMarkets } from "./scan.js";
import { detectSignals } from "./signal.js";

/** Approval is refreshed when current allowance drops below this floor. */
const USDC_ALLOWANCE_THRESHOLD = 100_000_000_000n; // 100k USDC (6 decimals)
/** When refreshing, allowance is set to this target. */
const USDC_ALLOWANCE_TARGET = 1_000_000_000_000n; // 1M USDC
/** Circuit breaker threshold — halts after this many consecutive losses. */
const MAX_CONSECUTIVE_LOSSES = 3;
/** Fallback price when the signal does not carry an order-book ask. */
const FALLBACK_PRICE = 0.5;

/** Parsed CLI flags for the arb-binary entry point. */
export interface EntryFlags {
  /** When true, the runner logs signals but does not submit orders. */
  dryRun: boolean;
}

/** Live executor + positions adapters wired for the runner. */
export interface EntryDeps {
  executor: ExecutorDeps;
  positions: PositionDeps;
}

/**
 * Parse `process.argv` into entry flags.
 *
 * `--live` flips to live execution. Anything else (including `--dry-run` or
 * no flag at all) keeps the safe dry-run default.
 */
export function parseEntryFlags(argv: readonly string[]): EntryFlags {
  if (argv.includes("--live")) return { dryRun: false };
  return { dryRun: true };
}

/** Build the ARB-01 risk checker with the production circuit-breaker. */
export function createEntryRisk(): ArbBinaryRisk {
  return createRiskChecker({
    bankroll: DEFAULT_ARB_BINARY_CONFIG.bankroll,
    kellyFraction: DEFAULT_ARB_BINARY_CONFIG.kellyFraction,
    maxExposure: DEFAULT_ARB_BINARY_CONFIG.maxExposure,
    maxConsecutiveLosses: MAX_CONSECUTIVE_LOSSES,
  });
}

/**
 * Resolve a TradeSignal to the (tokenIds, price) pair the live executor needs.
 *
 * The scan layer attaches yesAsk/noAsk and the YES/NO CLOB token IDs to the
 * signal metadata. The fallback path keeps unit tests and ad-hoc replays
 * functional when metadata is partial.
 */
function resolveArbBinaryOrder(signal: TradeSignal): ResolvedOrder {
  const meta = signal.metadata;
  const yesTokenIdRaw = meta["yesTokenId"];
  const noTokenIdRaw = meta["noTokenId"];
  const yesAskRaw = meta["yesAsk"];
  const noAskRaw = meta["noAsk"];

  const yesTokenId =
    typeof yesTokenIdRaw === "string" && yesTokenIdRaw.length > 0
      ? yesTokenIdRaw
      : `${signal.market.market_id}:yes`;
  const noTokenId =
    typeof noTokenIdRaw === "string" && noTokenIdRaw.length > 0
      ? noTokenIdRaw
      : `${signal.market.market_id}:no`;
  const yesAsk = typeof yesAskRaw === "number" ? yesAskRaw : FALLBACK_PRICE;
  const noAsk = typeof noAskRaw === "number" ? noAskRaw : FALLBACK_PRICE;

  const isYesLeg =
    signal.direction === "buy_yes" || signal.direction === "sell_yes";

  return {
    tokenIds: { yes: yesTokenId, no: noTokenId },
    price: isYesLeg ? yesAsk : noAsk,
  };
}

/**
 * Build the live executor + position adapters consumed by the runner.
 *
 * Both adapters are always live — the runner gates `executor.submit` on
 * `config.dryRun`, so dry-run still exercises the wiring without sending
 * orders.
 */
export function createEntryDeps(flags: EntryFlags): EntryDeps {
  void flags;
  const executor = createLiveExecutor({
    resolveOrder: resolveArbBinaryOrder,
    allowanceThreshold: USDC_ALLOWANCE_THRESHOLD,
    allowanceTarget: USDC_ALLOWANCE_TARGET,
  });
  const positions = createLivePositions();
  return { executor, positions };
}

async function main(): Promise<void> {
  const flags = parseEntryFlags(process.argv);
  const pollIntervalMs = Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

  const risk = createEntryRisk();
  const { executor, positions } = createEntryDeps(flags);

  const strategy = async (): Promise<TradeSignal[]> => {
    const marketData = await scanMarkets(DEFAULT_ARB_BINARY_CONFIG, {
      searchMarkets,
      fetchOrderBook,
    });
    return detectSignals(marketData, DEFAULT_ARB_BINARY_CONFIG);
  };

  const runner = createRunner(
    {
      pollIntervalMs,
      dryRun: flags.dryRun,
      baseDir: ".canon/execution",
      statePath: ".canon/state.json",
    },
    {
      strategy,
      risk,
      executor,
      positions,
      log: (entry: ExecutionLogEntry) =>
        appendEntry(".canon/execution", entry),
    },
  );

  process.stdout.write(
    `START ARB-01 scanner (${flags.dryRun ? "dry-run" : "live"}) ` +
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
