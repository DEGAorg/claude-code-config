/**
 * MINT-01 Simple Mint Cycle — Pure helpers + orchestrator.
 *
 * Pure helpers (deterministic, no I/O):
 *
 *   1. `selectMarket`   — filter + rank candidate markets against the
 *                          MINT-01 config thresholds (volume, open interest,
 *                          time-to-close); pick the most liquid survivor.
 *   2. `planLegs`       — given a YES midpoint and the configured premium
 *                          offset, derive the two sell-limit prices and the
 *                          size (token units) for each leg.
 *   3. `shouldStopLoss` — given entry vs current YES midpoint and the drift
 *                          threshold, decide whether to cancel both legs.
 *
 * Orchestrator (composes the helpers with injected I/O):
 *
 *   4. `runCycle`       — runs one MINT-01 cycle end-to-end:
 *                            scan → selectMarket → splitPosition →
 *                            submit YES + NO legs → fill-poll loop →
 *                            cancel remaining on timeout, stop-loss, or
 *                            partial-leg failure.
 *
 * `entry.ts` (Item 7) wires the live deps; tests inject fakes.
 */

import type { ExecutionLogEntry } from "../../execution-log.js";
import {
  planTwoLegs,
  withinDriftBand,
} from "../../mint-cycle-helpers.js";
import type { OrderResponse } from "../../client-polymarket.js";
import type { TradeSignal } from "../../types/TradeSignal.js";

import type { Mint01Config } from "./config.js";

/**
 * Candidate market input to `selectMarket`.
 *
 * Field names support snake_case (per C2 source spec) and camelCase (per
 * canon scanner conventions), matching the dual-shape pattern in
 * `mm-premium/signal.ts`.
 */
export interface MarketCandidate {
  /** Polymarket condition ID. */
  conditionId: string;
  /** Human-readable market question. */
  question: string;
  /** YES outcome midpoint price in [0, 1]. */
  midpoint: number;
  /** Milliseconds until market close. */
  timeToCloseMs: number;
  /** 24h quote volume in USD (snake_case variant). */
  volume_24h?: number;
  /** 24h quote volume in USD (camelCase variant). */
  volume24h?: number;
  /** Open interest in USD (snake_case variant). */
  open_interest?: number;
  /** Open interest in USD (camelCase variant). */
  openInterest?: number;
  /** CLOB token ID for the YES outcome. */
  yesTokenId?: string;
  /** CLOB token ID for the NO outcome. */
  noTokenId?: string;
}

/** A market that passed `selectMarket` filters, with ranking signal preserved. */
export interface MarketChoice {
  /** The candidate that won the rank. */
  candidate: MarketCandidate;
  /** Resolved 24h volume (USD) — the value used to rank survivors. */
  volume24h: number;
  /** Resolved open interest (USD). */
  openInterest: number;
}

/** Two-leg plan derived from a YES midpoint and the premium offset. */
export interface CycleLegs {
  /** Sell-limit price for the YES leg (= yesMidpoint + premium). */
  yesPrice: number;
  /** Sell-limit price for the NO leg  (= (1 − yesMidpoint) + premium). */
  noPrice: number;
  /** Size of each leg in outcome-token units (1 USDC = 1 minted pair). */
  size: number;
}

function volumeOf(c: MarketCandidate): number {
  return c.volume_24h ?? c.volume24h ?? 0;
}

function openInterestOf(c: MarketCandidate): number {
  return c.open_interest ?? c.openInterest ?? 0;
}

/**
 * Filter candidates by MINT-01 thresholds and rank by 24h volume.
 *
 * A candidate qualifies when ALL of the following hold:
 *   - `volume_24h           ≥ config.minVolume24h`
 *   - `open_interest        ≥ config.minOpenInterest`
 *   - `timeToCloseMs        ≥ config.minTimeToCloseMs`
 *   - `midpoint`             is in (0, 1)  — degenerate prices reject
 *   - `yesTokenId` and `noTokenId` are both present (CLOB-shaped strings)
 *
 * Returns the highest-volume survivor, or `null` if no candidate passes.
 */
export function selectMarket(
  candidates: MarketCandidate[],
  config: Mint01Config,
): MarketChoice | null {
  let best: MarketChoice | null = null;
  for (const candidate of candidates) {
    const volume24h = volumeOf(candidate);
    const openInterest = openInterestOf(candidate);
    if (volume24h < config.minVolume24h) continue;
    if (openInterest < config.minOpenInterest) continue;
    if (candidate.timeToCloseMs < config.minTimeToCloseMs) continue;
    if (candidate.midpoint <= 0 || candidate.midpoint >= 1) continue;
    if (!candidate.yesTokenId || !candidate.noTokenId) continue;

    if (best === null || volume24h > best.volume24h) {
      best = { candidate, volume24h, openInterest };
    }
  }
  return best;
}

/**
 * Plan the two sell legs for a MINT-01 cycle.
 *
 * Thin adapter over the shared `planTwoLegs` helper that binds the offset
 * to `config.premiumOffset` and the size to `config.cycleCapital`. Because
 * `splitPosition($cycleCapital)` mints `cycleCapital` matched YES + NO
 * pairs (each pair backed by $1 USDC), leg size equals `cycleCapital`.
 *
 * Throws when `yesMidpoint` is outside (0, 1) or when the premium would
 * push either leg price above $1 (an unfillable above-cap quote).
 */
export function planLegs(
  yesMidpoint: number,
  config: Mint01Config,
): CycleLegs {
  return planTwoLegs(yesMidpoint, config.premiumOffset, config.cycleCapital);
}

/**
 * Decide whether the cycle should exit on a stop-loss trigger.
 *
 * Returns `true` when the YES midpoint has drifted strictly more than
 * `config.stopLossDrift` dollars from the entry midpoint in either
 * direction. Negation of the shared `withinDriftBand` (which is inclusive
 * at the boundary). Caller is responsible for cancelling both legs and
 * unwinding via resolution.
 */
export function shouldStopLoss(
  entryMidpoint: number,
  currentMidpoint: number,
  config: Mint01Config,
): boolean {
  return !withinDriftBand(entryMidpoint, currentMidpoint, config.stopLossDrift);
}

// ---------------------------------------------------------------------------
// Cycle orchestrator
// ---------------------------------------------------------------------------

/** USDC.e has 6 decimals; `splitPosition` consumes raw token units. */
const USDC_E_DECIMALS_SCALE = 1_000_000n;
/** Default time between fill-poll iterations. */
const DEFAULT_FILL_POLL_INTERVAL_MS = 60_000;

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
export interface CycleMintClient {
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
export interface CycleExecutor {
  submit: (signal: TradeSignal) => Promise<SubmitOutcome>;
  cancel: (orderId: string) => Promise<CancelOutcome>;
}

/** Scan surface needed by the cycle orchestrator. */
export interface CycleScan {
  fetchSnapshots: () => Promise<MarketCandidate[]>;
}

/** Dependencies consumed by `runCycle`. All I/O flows through these. */
export interface RunCycleDeps {
  config: Mint01Config;
  scan: CycleScan;
  mintClient: CycleMintClient;
  executor: CycleExecutor;
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
  /**
   * Override the fill-poll interval (ms). Falls back to a 60s default that
   * matches the plan's "60s fill-poll interval" default.
   */
  fillPollIntervalMs?: number;
}

/** Terminal status of a single MINT-01 cycle. */
export type CycleStatus =
  | "no_candidate"
  | "filled"
  | "reconciled"
  | "stop_loss"
  | "partial_failure";

/** Summary of one cycle, returned by `runCycle` (consumers may ignore it). */
export interface CycleResult {
  status: CycleStatus;
  conditionId?: string;
  yesOrderId?: string;
  noOrderId?: string;
}

interface BuiltSignals {
  yesSignal: TradeSignal;
  noSignal: TradeSignal;
}

function buildLegSignals(
  candidate: MarketCandidate,
  legs: CycleLegs,
  config: Mint01Config,
): BuiltSignals {
  const yesTokenId = candidate.yesTokenId as string;
  const noTokenId = candidate.noTokenId as string;
  const market: TradeSignal["market"] = {
    platform: "polymarket",
    market_id: candidate.conditionId,
    question: candidate.question,
  };
  const baseMetadata: Record<string, unknown> = {
    yesTokenId,
    noTokenId,
    yesPrice: legs.yesPrice,
    noPrice: legs.noPrice,
    entryMidpoint: candidate.midpoint,
    timeInForce: config.timeInForce,
  };
  const timestamp = new Date();

  const yesSignal: TradeSignal = {
    automation_id: "mint-01",
    timestamp,
    market,
    direction: "sell_yes",
    size: legs.size,
    confidence: 1,
    urgency: "normal",
    metadata: { ...baseMetadata, leg: "yes" },
  };
  const noSignal: TradeSignal = {
    automation_id: "mint-01",
    timestamp,
    market: { ...market },
    direction: "sell_no",
    size: legs.size,
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
    automation_id: "mint-01",
    market_id: marketId,
    data,
  });
}

/**
 * Run one MINT-01 cycle end-to-end.
 *
 * The pipeline composes the pure helpers with the injected I/O surface:
 *
 *   1. `scan.fetchSnapshots()` → `selectMarket` picks the highest-volume
 *      candidate. If no candidate qualifies the cycle exits with
 *      `status: "no_candidate"` and no on-chain or CLOB activity.
 *   2. `planLegs(midpoint, config)` derives `{yesPrice, noPrice, size}`.
 *   3. `mintClient.splitPosition({conditionId, amount: cycleCapital * 1e6})`
 *      converts $cycleCapital USDC.e into a matched YES + NO pair. A
 *      `mint_set` log entry is emitted on success.
 *   4. Both legs are submitted sequentially as sell-limit orders. On a
 *      partial-leg failure (one leg posts, the other throws) the orchestrator
 *      cancels the posted leg and calls `mintClient.mergePositions` with the
 *      same args used by `splitPosition` to return the collateral, then exits
 *      with `status: "partial_failure"`.
 *   5. With both legs live a `cycle_start` log entry is emitted and the
 *      fill-poll loop begins:
 *        - poll status for every open leg (`fetchOrderStatus`)
 *        - log `cycle_fill` for legs that reach a terminal state and remove
 *          them from the open set
 *        - check stop-loss via `fetchMidpoint` + `shouldStopLoss`; on a
 *          drift past `stopLossDrift`, cancel every remaining leg, emit a
 *          `cycle_stop_loss` log entry, and exit with `status: "stop_loss"`
 *        - check the cycle deadline (`now() - start > maxCycleDurationMs`);
 *          on timeout cancel every remaining leg, emit `cycle_reconcile`,
 *          and exit with `status: "reconciled"`
 *        - otherwise `await sleep(fillPollIntervalMs)` and repeat
 *      The loop exits with `status: "filled"` when both legs reach a
 *      terminal status without timeout or stop-loss.
 *
 * The second overload accepts an untyped `unknown` deps argument so
 * vitest `Mock<Procedure | Constructable>` mocks (vitest 4.x widens the
 * Mock generic and loses the call signature on the Constructable branch)
 * remain callable from tests without weakening the strict production
 * `RunCycleDeps` shape that `entry.ts` consumes.
 */
export function runCycle(deps: RunCycleDeps): Promise<CycleResult>;
export function runCycle(deps: unknown): Promise<CycleResult>;
export async function runCycle(deps: unknown): Promise<CycleResult> {
  return runCycleImpl(deps as RunCycleDeps);
}

async function runCycleImpl(deps: RunCycleDeps): Promise<CycleResult> {
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
  const pollIntervalMs =
    deps.fillPollIntervalMs ?? DEFAULT_FILL_POLL_INTERVAL_MS;

  const candidates = await scan.fetchSnapshots();
  const choice = selectMarket(candidates, config);
  if (choice === null) {
    return { status: "no_candidate" };
  }
  const { candidate } = choice;
  const legs = planLegs(candidate.midpoint, config);
  const conditionId = candidate.conditionId;

  const splitArgs = {
    conditionId,
    amount: BigInt(config.cycleCapital) * USDC_E_DECIMALS_SCALE,
  };
  const { yesSignal, noSignal } = buildLegSignals(candidate, legs, config);

  await mintClient.splitPosition(splitArgs);
  logEntry(log, "mint_set", conditionId, {
    amount: splitArgs.amount.toString(),
    entryMidpoint: candidate.midpoint,
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
    entryMidpoint: candidate.midpoint,
    timeInForce: config.timeInForce,
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
    if (shouldStopLoss(candidate.midpoint, currentMidpoint, config)) {
      for (const orderId of openOrders.keys()) {
        await executor.cancel(orderId);
      }
      logEntry(log, "cycle_stop_loss", conditionId, {
        entryMidpoint: candidate.midpoint,
        currentMidpoint,
        drift: Math.abs(currentMidpoint - candidate.midpoint),
        threshold: config.stopLossDrift,
        cancelledOrderIds: [...openOrders.keys()],
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
