/**
 * MINT-04 Market Making Premium — Cycle Orchestrator.
 *
 * One MINT-04 cycle composes the tier-selecting signal evaluator
 * (`evaluateMintPremiumOpportunity`) with the shared `planTwoLegs` /
 * `withinDriftBand` helpers and the injected I/O surface:
 *
 *   scan → evaluate snapshots → pick highest-volume viable →
 *   splitPosition → submit YES + NO legs at midpoint ± offsetC →
 *   fill-poll loop → cancel remaining on timeout, stop-loss, or
 *   partial-leg failure.
 *
 * Offset is per-cycle (not config-level) — `evaluateMintPremiumOpportunity`
 * picks one of `offsetAggressiveC` / `offsetDefaultC` / `offsetDefensiveC`
 * based on the snapshot's volume + trade-activity bracket, and the chosen
 * offset is latched for the duration of the cycle.
 *
 * When no snapshot is viable the cycle exits early with a `NO_EDGE`
 * advisory in the execution log — no on-chain or CLOB activity.
 */

import type { ExecutionLogEntry } from "../../execution-log.js";
import {
  planTwoLegs,
  withinDriftBand,
} from "../../mint-cycle-helpers.js";
import type { OrderResponse } from "../../client-polymarket.js";
import type { TradeSignal } from "../../types/TradeSignal.js";

import type { MintPremiumConfig } from "./config.js";
import {
  evaluateMintPremiumOpportunity,
  type MintPremiumSnapshot,
  type MintPremiumSignal,
} from "./signal.js";

const AUTOMATION_ID = "mm-premium";

/** USDC.e has 6 decimals; `splitPosition` consumes raw token units. */
const USDC_E_DECIMALS_SCALE = 1_000_000n;

const TERMINAL_ORDER_STATUSES: ReadonlySet<string> = new Set([
  "filled",
  "cancelled",
]);

/** Outcome of an `executor.submit` call (mirrors `LiveExecutor.SubmitOutcome`). */
export interface SubmitOutcome {
  id: string;
  status: string;
}

/** Outcome of an `executor.cancel` call. */
export interface CancelOutcome {
  id: string;
  status: string;
}

/** CTF mint surface needed by the cycle orchestrator. */
export interface MmPremiumMintClient {
  splitPosition: (args: {
    conditionId: string;
    amount: bigint;
  }) => Promise<{ txHash: string }>;
  mergePositions: (args: {
    conditionId: string;
    amount: bigint;
  }) => Promise<{ txHash: string }>;
}

/** CLOB executor surface needed by the cycle orchestrator. */
export interface MmPremiumExecutor {
  submit: (signal: TradeSignal) => Promise<SubmitOutcome>;
  cancel: (orderId: string) => Promise<CancelOutcome>;
}

/** Scan surface needed by the cycle orchestrator. */
export interface MmPremiumScan {
  fetchSnapshots: () => Promise<MintPremiumSnapshot[]>;
}

/** Dependencies consumed by `runMmPremiumCycle`. All I/O flows through these. */
export interface RunMmPremiumCycleDeps {
  config: MintPremiumConfig;
  scan: MmPremiumScan;
  mintClient: MmPremiumMintClient;
  executor: MmPremiumExecutor;
  /** Read current status for an order (used by the fill-poll loop). */
  fetchOrderStatus: (orderId: string) => Promise<OrderResponse>;
  /** Read current YES midpoint for the market (used for stop-loss). */
  fetchMidpoint: (conditionId: string) => Promise<number>;
  /** Sink for structured execution log entries. */
  log: (entry: ExecutionLogEntry) => void;
  /** Monotonic clock (ms). Injected so tests can fast-forward. */
  now: () => number;
  /** Cooperative pause between poll iterations. Injected for the same reason. */
  sleep: (ms: number) => Promise<void>;
}

/** Terminal status of a single MINT-04 cycle. */
export type MmPremiumCycleStatus =
  | "no_edge"
  | "filled"
  | "reconciled"
  | "stop_loss"
  | "partial_failure";

/** Summary of one cycle, returned by `runMmPremiumCycle` (consumers may ignore). */
export interface MmPremiumCycleResult {
  status: MmPremiumCycleStatus;
  conditionId?: string;
  yesOrderId?: string;
  noOrderId?: string;
}

interface ViableChoice {
  snapshot: MintPremiumSnapshot;
  signal: MintPremiumSignal;
  volume: number;
}

function volumeOf(snap: MintPremiumSnapshot): number {
  return snap.volume_24h ?? snap.volume24h ?? 0;
}

/**
 * Pick the highest-volume viable snapshot.
 *
 * Each snapshot is run through `evaluateMintPremiumOpportunity`; non-viable
 * ones are dropped. Among the survivors, the one with the highest 24h
 * volume wins (the offset tier is whatever the evaluator latched).
 */
function pickViableSnapshot(
  snapshots: readonly MintPremiumSnapshot[],
  config: MintPremiumConfig,
): ViableChoice | null {
  let best: ViableChoice | null = null;
  for (const snapshot of snapshots) {
    if (!snapshot.yesTokenId || !snapshot.noTokenId) continue;
    if (snapshot.midpoint <= 0 || snapshot.midpoint >= 1) continue;
    const signal = evaluateMintPremiumOpportunity(snapshot, config);
    if (!signal.viable) continue;
    const volume = volumeOf(snapshot);
    if (best === null || volume > best.volume) {
      best = { snapshot, signal, volume };
    }
  }
  return best;
}

interface BuiltSignals {
  yesSignal: TradeSignal;
  noSignal: TradeSignal;
}

function buildLegSignals(
  snapshot: MintPremiumSnapshot,
  yesPrice: number,
  noPrice: number,
  size: number,
  offsetC: number,
): BuiltSignals {
  const yesTokenId = snapshot.yesTokenId as string;
  const noTokenId = snapshot.noTokenId as string;
  const market: TradeSignal["market"] = {
    platform: "polymarket",
    market_id: snapshot.conditionId,
    question: snapshot.question,
  };
  const baseMetadata: Record<string, unknown> = {
    yesTokenId,
    noTokenId,
    yesPrice,
    noPrice,
    entryMidpoint: snapshot.midpoint,
    offsetC,
    timeInForce: "GTC",
  };
  const timestamp = new Date();

  const yesSignal: TradeSignal = {
    automation_id: AUTOMATION_ID,
    timestamp,
    market,
    direction: "sell_yes",
    size,
    confidence: 1,
    urgency: "normal",
    metadata: { ...baseMetadata, leg: "yes" },
  };
  const noSignal: TradeSignal = {
    automation_id: AUTOMATION_ID,
    timestamp,
    market: { ...market },
    direction: "sell_no",
    size,
    confidence: 1,
    urgency: "normal",
    metadata: { ...baseMetadata, leg: "no" },
  };
  return { yesSignal, noSignal };
}

function logEntry(
  log: (entry: ExecutionLogEntry) => void,
  type: ExecutionLogEntry["type"],
  marketId: string,
  data: Record<string, unknown>,
): void {
  log({
    timestamp: new Date().toISOString(),
    type,
    automation_id: AUTOMATION_ID,
    market_id: marketId,
    data,
  });
}

/**
 * Run one MINT-04 mint-premium cycle end-to-end.
 *
 * The pipeline:
 *
 *   1. `scan.fetchSnapshots()` → `evaluateMintPremiumOpportunity` filters
 *      to viable markets and latches each one's offset tier. The
 *      highest-volume viable snapshot wins. If no snapshot is viable the
 *      cycle exits with `status: "no_edge"` and a `NO_EDGE` advisory in
 *      the execution log.
 *   2. `planTwoLegs(midpoint, offsetC, cycleCapital)` derives
 *      `{yesPrice, noPrice, size}`.
 *   3. `mintClient.splitPosition({conditionId, amount: cycleCapital * 1e6})`
 *      converts $cycleCapital USDC.e into a matched YES + NO pair. A
 *      `mint_set` log entry is emitted on success.
 *   4. Both legs are submitted sequentially as sell-limit orders. On a
 *      partial-leg failure (one leg posts, the other throws) the placed
 *      leg is cancelled and `mintClient.mergePositions` is called with the
 *      same args used by `splitPosition` to return the collateral. The
 *      cycle exits with `status: "partial_failure"` without entering the
 *      fill-poll loop.
 *   5. With both legs live a `cycle_start` log entry is emitted and the
 *      fill-poll loop begins:
 *        - poll status for every open leg (`fetchOrderStatus`)
 *        - log `cycle_fill` for legs that reach a terminal state and
 *          remove them from the open set
 *        - check stop-loss via `fetchMidpoint` + `withinDriftBand`; on a
 *          drift past `stopLossDrift`, cancel every remaining leg, emit
 *          `cycle_stop_loss`, and exit with `status: "stop_loss"`
 *        - check the cycle deadline (`now() - start > maxCycleDurationMs`);
 *          on timeout cancel every remaining leg, emit `cycle_reconcile`,
 *          and exit with `status: "reconciled"`
 *        - otherwise `await sleep(fillPollIntervalMs)` and repeat
 *      The loop exits with `status: "filled"` when both legs reach a
 *      terminal status without timeout or stop-loss.
 *
 * The second overload accepts an untyped `unknown` deps argument so
 * vitest `Mock<Procedure | Constructable>` mocks remain callable from
 * tests without weakening the strict production `RunMmPremiumCycleDeps`
 * shape that `entry.ts` consumes.
 */
export function runMmPremiumCycle(
  deps: RunMmPremiumCycleDeps,
): Promise<MmPremiumCycleResult>;
export function runMmPremiumCycle(
  deps: unknown,
): Promise<MmPremiumCycleResult>;
export async function runMmPremiumCycle(
  deps: unknown,
): Promise<MmPremiumCycleResult> {
  return runMmPremiumCycleImpl(deps as RunMmPremiumCycleDeps);
}

async function runMmPremiumCycleImpl(
  deps: RunMmPremiumCycleDeps,
): Promise<MmPremiumCycleResult> {
  const {
    config,
    scan,
    mintClient,
    executor,
    fetchOrderStatus,
    fetchMidpoint,
    log,
    now,
    sleep,
  } = deps;
  const pollIntervalMs = config.fillPollIntervalMs;

  const snapshots = await scan.fetchSnapshots();
  const choice = pickViableSnapshot(snapshots, config);
  if (choice === null) {
    logEntry(log, "error", "", {
      reason: "NO_EDGE",
      advisory:
        "no viable MINT-04 snapshot in scan; skipping cycle (NO_EDGE).",
      snapshotsConsidered: snapshots.length,
    });
    return { status: "no_edge" };
  }
  const { snapshot, signal } = choice;
  const conditionId = snapshot.conditionId;
  const offsetC = signal.offsetC;
  const legs = planTwoLegs(snapshot.midpoint, offsetC, config.cycleCapital);

  const splitArgs = {
    conditionId,
    amount: BigInt(config.cycleCapital) * USDC_E_DECIMALS_SCALE,
  };
  const { yesSignal, noSignal } = buildLegSignals(
    snapshot,
    legs.yesPrice,
    legs.noPrice,
    legs.size,
    offsetC,
  );

  await mintClient.splitPosition(splitArgs);
  logEntry(log, "mint_set", conditionId, {
    amount: splitArgs.amount.toString(),
    entryMidpoint: snapshot.midpoint,
    offsetC,
    txTarget: "splitPosition",
  });

  let yesOrderId: string | undefined;
  let noOrderId: string | undefined;
  try {
    const yesOutcome = await executor.submit(yesSignal);
    yesOrderId = yesOutcome.id;
    const noOutcome = await executor.submit(noSignal);
    noOrderId = noOutcome.id;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (yesOrderId !== undefined) {
      await executor.cancel(yesOrderId);
    }
    if (noOrderId !== undefined) {
      await executor.cancel(noOrderId);
    }
    await mintClient.mergePositions(splitArgs);
    logEntry(log, "error", conditionId, {
      stage: "cycle_submit",
      error: message,
      yesOrderId: yesOrderId ?? null,
      noOrderId: noOrderId ?? null,
      merged: true,
    });
    return {
      status: "partial_failure",
      conditionId,
      ...(yesOrderId !== undefined ? { yesOrderId } : {}),
      ...(noOrderId !== undefined ? { noOrderId } : {}),
    };
  }

  logEntry(log, "cycle_start", conditionId, {
    yesOrderId,
    noOrderId,
    yesPrice: legs.yesPrice,
    noPrice: legs.noPrice,
    entryMidpoint: snapshot.midpoint,
    offsetC,
    timeInForce: "GTC",
  });

  const openOrders = new Map<string, "yes" | "no">();
  openOrders.set(yesOrderId as string, "yes");
  openOrders.set(noOrderId as string, "no");
  const startTime = now();

  for (;;) {
    for (const orderId of [...openOrders.keys()]) {
      const status = await fetchOrderStatus(orderId);
      if (TERMINAL_ORDER_STATUSES.has(status.status)) {
        const leg = openOrders.get(orderId) as "yes" | "no";
        openOrders.delete(orderId);
        logEntry(log, "cycle_fill", conditionId, {
          orderId,
          leg,
          status: status.status,
          filled: status.filled,
          remaining: status.remaining,
        });
      }
    }

    if (openOrders.size === 0) {
      return {
        status: "filled",
        conditionId,
        yesOrderId,
        noOrderId,
      };
    }

    const currentMidpoint = await fetchMidpoint(conditionId);
    if (
      !withinDriftBand(snapshot.midpoint, currentMidpoint, config.stopLossDrift)
    ) {
      const cancelledOrderIds = [...openOrders.keys()];
      for (const orderId of cancelledOrderIds) {
        await executor.cancel(orderId);
      }
      logEntry(log, "cycle_stop_loss", conditionId, {
        entryMidpoint: snapshot.midpoint,
        currentMidpoint,
        drift: Math.abs(currentMidpoint - snapshot.midpoint),
        threshold: config.stopLossDrift,
        cancelledOrderIds,
      });
      return {
        status: "stop_loss",
        conditionId,
        yesOrderId,
        noOrderId,
      };
    }

    if (now() - startTime > config.maxCycleDurationMs) {
      const cancelledOrderIds = [...openOrders.keys()];
      for (const orderId of cancelledOrderIds) {
        await executor.cancel(orderId);
      }
      logEntry(log, "cycle_reconcile", conditionId, {
        deadlineMs: config.maxCycleDurationMs,
        cancelledOrderIds,
      });
      return {
        status: "reconciled",
        conditionId,
        yesOrderId,
        noOrderId,
      };
    }

    await sleep(pollIntervalMs);
  }
}
