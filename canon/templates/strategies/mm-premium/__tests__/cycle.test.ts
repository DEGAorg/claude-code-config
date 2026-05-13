/**
 * Tests for the MINT-04 cycle orchestrator (`runMmPremiumCycle`).
 *
 * The orchestrator composes `evaluateMintPremiumOpportunity` (tier-selected
 * offset + viability gate) and the shared `planTwoLegs` / `withinDriftBand`
 * helpers with the injected I/O surface:
 *
 *   scan → evaluate snapshots → splitPosition →
 *   submit YES + NO legs (using snapshot's tier-selected offsetC) →
 *   fill-poll loop → cancel remaining on timeout OR stop-loss OR
 *   partial-leg failure
 *
 * Every test injects the deps and asserts on call shape — no real network,
 * no real chain. The pre-hydrated dependency injection mirrors the pattern
 * used by `strategies/mint-01/__tests__/cycle-orchestrator.test.ts`.
 *
 * The contract this file pins (to be satisfied by item 2):
 *
 *   ```ts
 *   runMmPremiumCycle(deps: RunMmPremiumCycleDeps): Promise<MmPremiumCycleResult>
 *   ```
 *
 *   - Scan emits N snapshots → `evaluateMintPremiumOpportunity` filters to
 *     viable ones → the highest-volume viable snapshot is selected.
 *   - `splitPosition({conditionId, amount: cycleCapital * 1e6})` fires once.
 *   - Both legs submit with `midpoint + offsetC` (YES) and
 *     `(1 − midpoint) + offsetC` (NO) using the snapshot's tier-selected
 *     offset (1.0¢ / 0.75¢ / 0.5¢).
 *   - Fill-poll runs → on timeout each unfilled leg is cancelled → log
 *     emits `mint_set`, `cycle_start`, `cycle_reconcile`.
 *   - On midpoint drift > `stopLossDrift`: both legs are cancelled and the
 *     log emits `cycle_stop_loss`.
 *   - On partial-leg submit failure (e.g. NO throws after YES succeeds):
 *     YES is cancelled and `mintClient.mergePositions` is called to unwind
 *     the minted pair.
 *   - When no snapshot is viable, the cycle exits early with a `NO_EDGE`
 *     advisory and no mint/submit/cancel is performed.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

import { runMmPremiumCycle } from "../cycle.js";
import {
  DEFAULT_MM_PREMIUM_CONFIG,
  type MintPremiumConfig,
} from "../config.js";
import type { MintPremiumSnapshot } from "../signal.js";
import type { OrderResponse } from "../../../client-polymarket.js";
import type { TradeSignal } from "../../../types/TradeSignal.js";

// ---------------------------------------------------------------------------
// Test factories
// ---------------------------------------------------------------------------

const YES_TOKEN_ID =
  "12345678901234567890123456789012345678901234567890123456789012345";
const NO_TOKEN_ID =
  "98765432109876543210987654321098765432109876543210987654321098765";

const YES_ORDER_ID = "ord-yes-001";
const NO_ORDER_ID = "ord-no-001";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

function makeConfig(
  overrides?: Partial<MintPremiumConfig>,
): MintPremiumConfig {
  return {
    ...DEFAULT_MM_PREMIUM_CONFIG,
    // Override cycleCapital back to the spec target ($1,000) for tests:
    // the default ships at $5 (safe smoke size) which fails the hurdle
    // gate inside `evaluateMintPremiumOpportunity` and would short-circuit
    // every test that relies on a viable signal.
    cycleCapital: 1_000,
    stopLossDrift: 0.05,
    fillPollIntervalMs: 60_000,
    maxCycleDurationMs: ONE_DAY_MS,
    ...overrides,
  } as MintPremiumConfig;
}

/**
 * Default snapshot sits comfortably in the +0.75c tier: mid-volume
 * (~$30k), 15 trades/h, 1c spread. `evaluateMintPremiumOpportunity`
 * returns `{viable: true, offsetC: 0.0075}` for this shape.
 */
function makeSnapshot(
  overrides?: Partial<MintPremiumSnapshot>,
): MintPremiumSnapshot {
  return {
    conditionId: "0xcond-001",
    question: "Will the Lakers win?",
    midpoint: 0.5,
    timeToCloseMs: 7 * ONE_DAY_MS,
    volume_24h: 30_000,
    trade_count_1h: 15,
    bid_ask_spread: 0.01,
    yesTokenId: YES_TOKEN_ID,
    noTokenId: NO_TOKEN_ID,
    ...overrides,
  };
}

function openOrder(id: string, tokenId: string): OrderResponse {
  return {
    id,
    marketId: "0xcond-001",
    outcomeId: tokenId,
    side: "sell",
    type: "limit",
    amount: 1_000,
    price: 0.5075,
    status: "submitted",
    filled: 0,
    remaining: 1_000,
  };
}

interface LogEntryLike {
  type: string;
  automation_id: string;
  market_id: string;
  timestamp: string;
  data: Record<string, unknown>;
}

interface CycleDeps {
  config: MintPremiumConfig;
  scan: { fetchSnapshots: ReturnType<typeof vi.fn> };
  mintClient: {
    splitPosition: ReturnType<typeof vi.fn>;
    mergePositions: ReturnType<typeof vi.fn>;
  };
  executor: {
    submit: ReturnType<typeof vi.fn>;
    cancel: ReturnType<typeof vi.fn>;
  };
  fetchOrderStatus: ReturnType<typeof vi.fn>;
  fetchMidpoint: ReturnType<typeof vi.fn>;
  log: ReturnType<typeof vi.fn>;
  now: ReturnType<typeof vi.fn>;
  sleep: ReturnType<typeof vi.fn>;
}

/**
 * Build a "timeout-on-first-poll" `now` mock.
 *
 * Call 1 returns `0` (cycle start). Every subsequent call returns
 * `maxCycleDurationMs + 1`, so the very first deadline check triggers a
 * timeout. The deps are simple enough that the orchestrator never sees
 * real wall-clock time — `sleep` is also a stub that resolves immediately.
 */
function timeoutOnFirstPoll(
  maxCycleDurationMs: number,
): ReturnType<typeof vi.fn> {
  let call = 0;
  return vi.fn(() => {
    const t = call === 0 ? 0 : maxCycleDurationMs + 1;
    call += 1;
    return t;
  });
}

/**
 * Default deps: viable scan with one mid-volume snapshot, both legs submit
 * cleanly, both orders stay "submitted" (non-terminal) so the timeout path
 * is exercised, midpoint stays flat so stop-loss does not trigger.
 */
function makeDeps(overrides?: {
  config?: MintPremiumConfig;
  snapshots?: MintPremiumSnapshot[];
  midpoint?: number;
  submitYes?: () => Promise<{ id: string; status: string }>;
  submitNo?: () => Promise<{ id: string; status: string }>;
}): CycleDeps {
  const config = overrides?.config ?? makeConfig();
  const snapshots = overrides?.snapshots ?? [makeSnapshot()];

  const submitYes =
    overrides?.submitYes ??
    (async () => ({ id: YES_ORDER_ID, status: "submitted" }));
  const submitNo =
    overrides?.submitNo ??
    (async () => ({ id: NO_ORDER_ID, status: "submitted" }));

  const submitFn = vi.fn(async (signal: TradeSignal) => {
    if (signal.direction === "sell_yes") return submitYes();
    if (signal.direction === "sell_no") return submitNo();
    throw new Error(`unexpected direction ${signal.direction}`);
  });

  const fetchOrderStatus = vi.fn(async (orderId: string) =>
    openOrder(orderId, orderId === YES_ORDER_ID ? YES_TOKEN_ID : NO_TOKEN_ID),
  );

  return {
    config,
    scan: { fetchSnapshots: vi.fn(async () => snapshots) },
    mintClient: {
      splitPosition: vi.fn(async () => ({ txHash: "0xmint" })),
      mergePositions: vi.fn(async () => ({ txHash: "0xmerge" })),
    },
    executor: {
      submit: submitFn,
      cancel: vi.fn(async (id: string) => ({ id, status: "cancelled" })),
    },
    fetchOrderStatus,
    fetchMidpoint: vi.fn(async () => overrides?.midpoint ?? 0.5),
    log: vi.fn(),
    now: timeoutOnFirstPoll(config.maxCycleDurationMs),
    sleep: vi.fn(async () => {}),
  };
}

function logTypes(log: ReturnType<typeof vi.fn>): string[] {
  return log.mock.calls.map(([entry]) => (entry as LogEntryLike).type);
}

function logEntries(log: ReturnType<typeof vi.fn>): LogEntryLike[] {
  return log.mock.calls.map(([entry]) => entry as LogEntryLike);
}

// ---------------------------------------------------------------------------
// Happy path: viable scan → mint → two legs → fill-poll → timeout reconcile
// ---------------------------------------------------------------------------

describe("runMmPremiumCycle — happy path (timeout reconcile)", () => {
  let deps: CycleDeps;

  beforeEach(() => {
    deps = makeDeps();
  });

  it("calls scan.fetchSnapshots exactly once", async () => {
    await runMmPremiumCycle(deps);
    expect(deps.scan.fetchSnapshots).toHaveBeenCalledTimes(1);
  });

  it("picks the highest-volume viable snapshot for splitPosition", async () => {
    // Three viable mid-volume snapshots — top by volume should win.
    deps = makeDeps({
      snapshots: [
        makeSnapshot({ conditionId: "0xlow", volume_24h: 12_000 }),
        makeSnapshot({ conditionId: "0xhigh", volume_24h: 80_000 }),
        makeSnapshot({ conditionId: "0xmid", volume_24h: 30_000 }),
      ],
    });

    await runMmPremiumCycle(deps);

    expect(deps.mintClient.splitPosition).toHaveBeenCalledTimes(1);
    const [args] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(args.conditionId).toBe("0xhigh");
  });

  it("skips non-viable snapshots and picks the highest-volume viable one", async () => {
    // The non-viable $5k snapshot would top volume only if accepted; it must
    // be skipped (MINT-02 advisory) so the $40k snapshot wins.
    deps = makeDeps({
      snapshots: [
        makeSnapshot({ conditionId: "0xbelow-floor", volume_24h: 5_000 }),
        makeSnapshot({ conditionId: "0xviable", volume_24h: 40_000 }),
      ],
    });

    await runMmPremiumCycle(deps);

    expect(deps.mintClient.splitPosition).toHaveBeenCalledTimes(1);
    const [args] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(args.conditionId).toBe("0xviable");
  });

  it("calls splitPosition with amount = cycleCapital * 10^6 (USDC.e 6 decimals)", async () => {
    deps = makeDeps({ config: makeConfig({ cycleCapital: 1_000 }) });
    await runMmPremiumCycle(deps);

    const [args] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(args.amount).toBe(1_000_000_000n);
  });

  it("scales the splitPosition amount with cycleCapital override", async () => {
    deps = makeDeps({ config: makeConfig({ cycleCapital: 2_500 }) });
    await runMmPremiumCycle(deps);

    const [args] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(args.amount).toBe(2_500_000_000n);
  });

  it("submits two legs (YES + NO) with the right tokenIds and tier-selected prices", async () => {
    await runMmPremiumCycle(deps);

    expect(deps.executor.submit).toHaveBeenCalledTimes(2);

    const calls = deps.executor.submit.mock.calls.map(
      ([signal]) => signal as TradeSignal,
    );
    const yesCall = calls.find((c) => c.direction === "sell_yes");
    const noCall = calls.find((c) => c.direction === "sell_no");

    expect(yesCall).toBeDefined();
    expect(noCall).toBeDefined();

    // Default snapshot lands in the mid-volume bracket → +0.75c offset.
    // YES price = 0.5 + 0.0075 = 0.5075; NO price = (1 - 0.5) + 0.0075 = 0.5075.
    expect(yesCall?.metadata["yesTokenId"]).toBe(YES_TOKEN_ID);
    expect(yesCall?.metadata["noTokenId"]).toBe(NO_TOKEN_ID);
    expect(yesCall?.metadata["yesPrice"]).toBeCloseTo(0.5075, 6);

    expect(noCall?.metadata["yesTokenId"]).toBe(YES_TOKEN_ID);
    expect(noCall?.metadata["noTokenId"]).toBe(NO_TOKEN_ID);
    expect(noCall?.metadata["noPrice"]).toBeCloseTo(0.5075, 6);
  });

  it("uses the aggressive +1.0c offset for high-volume snapshots", async () => {
    // Volume > $50k bracket → +1.0c offset.
    deps = makeDeps({
      snapshots: [
        makeSnapshot({
          midpoint: 0.4,
          volume_24h: 75_000,
          trade_count_1h: 40,
          bid_ask_spread: 0.008,
        }),
      ],
    });

    await runMmPremiumCycle(deps);

    const calls = deps.executor.submit.mock.calls.map(
      ([signal]) => signal as TradeSignal,
    );
    const yesCall = calls.find((c) => c.direction === "sell_yes");
    const noCall = calls.find((c) => c.direction === "sell_no");

    // YES = 0.4 + 0.01 = 0.41; NO = 0.6 + 0.01 = 0.61.
    expect(yesCall?.metadata["yesPrice"]).toBeCloseTo(0.41, 6);
    expect(noCall?.metadata["noPrice"]).toBeCloseTo(0.61, 6);
  });

  it("uses the defensive +0.5c offset when trade activity is low", async () => {
    // High volume but only 2 trades/h → defensive +0.5c offset.
    deps = makeDeps({
      snapshots: [
        makeSnapshot({
          midpoint: 0.5,
          volume_24h: 75_000,
          trade_count_1h: 2,
          bid_ask_spread: 0.008,
        }),
      ],
    });

    await runMmPremiumCycle(deps);

    const calls = deps.executor.submit.mock.calls.map(
      ([signal]) => signal as TradeSignal,
    );
    const yesCall = calls.find((c) => c.direction === "sell_yes");
    const noCall = calls.find((c) => c.direction === "sell_no");

    // YES = 0.5 + 0.005 = 0.505; NO = 0.5 + 0.005 = 0.505.
    expect(yesCall?.metadata["yesPrice"]).toBeCloseTo(0.505, 6);
    expect(noCall?.metadata["noPrice"]).toBeCloseTo(0.505, 6);
  });

  it("polls order status for both legs (fill-poll runs)", async () => {
    await runMmPremiumCycle(deps);

    expect(deps.fetchOrderStatus).toHaveBeenCalled();
    const polledIds = new Set(
      deps.fetchOrderStatus.mock.calls.map(([id]) => id as string),
    );
    expect(polledIds.has(YES_ORDER_ID)).toBe(true);
    expect(polledIds.has(NO_ORDER_ID)).toBe(true);
  });

  it("cancels both unfilled legs when the cycle deadline expires", async () => {
    await runMmPremiumCycle(deps);

    expect(deps.executor.cancel).toHaveBeenCalledTimes(2);
    const cancelledIds = new Set(
      deps.executor.cancel.mock.calls.map(([id]) => id as string),
    );
    expect(cancelledIds.has(YES_ORDER_ID)).toBe(true);
    expect(cancelledIds.has(NO_ORDER_ID)).toBe(true);
  });

  it("emits mint_set, cycle_start, and cycle_reconcile events", async () => {
    await runMmPremiumCycle(deps);

    const types = logTypes(deps.log);
    expect(types).toContain("mint_set");
    expect(types).toContain("cycle_start");
    expect(types).toContain("cycle_reconcile");
  });

  it("calls splitPosition AFTER scan and BEFORE the first submit (call order)", async () => {
    await runMmPremiumCycle(deps);

    const scanOrder = deps.scan.fetchSnapshots.mock.invocationCallOrder[0];
    const splitOrder =
      deps.mintClient.splitPosition.mock.invocationCallOrder[0];
    const firstSubmitOrder = deps.executor.submit.mock.invocationCallOrder[0];
    const firstCancelOrder = deps.executor.cancel.mock.invocationCallOrder[0];

    expect(scanOrder).toBeLessThan(splitOrder!);
    expect(splitOrder).toBeLessThan(firstSubmitOrder!);
    expect(firstSubmitOrder).toBeLessThan(firstCancelOrder!);
  });
});

// ---------------------------------------------------------------------------
// No viable snapshot → NO_EDGE advisory, no mint
// ---------------------------------------------------------------------------

describe("runMmPremiumCycle — no viable snapshot", () => {
  it("exits early with NO_EDGE advisory when scan returns no viable markets", async () => {
    // All snapshots fail one of the gates:
    //   - sub-floor volume → MINT-02 advisory, !viable
    //   - confluence failure → !viable
    const deps = makeDeps({
      snapshots: [
        makeSnapshot({
          conditionId: "0xtoo-low",
          volume_24h: 5_000,
          trade_count_1h: 1,
          bid_ask_spread: 0.05,
        }),
        makeSnapshot({
          conditionId: "0xno-confluence",
          volume_24h: 18_000,
          trade_count_1h: 5,
          bid_ask_spread: 0.02,
        }),
      ],
    });

    await runMmPremiumCycle(deps);

    expect(deps.mintClient.splitPosition).not.toHaveBeenCalled();
    expect(deps.executor.submit).not.toHaveBeenCalled();
    expect(deps.executor.cancel).not.toHaveBeenCalled();
    expect(deps.fetchOrderStatus).not.toHaveBeenCalled();

    // A NO_EDGE advisory must be surfaced in the execution log.
    const entries = logEntries(deps.log);
    const noEdge = entries.find((e) =>
      JSON.stringify(e).toUpperCase().includes("NO_EDGE"),
    );
    expect(noEdge).toBeDefined();
  });

  it("does not mint or submit when scan returns an empty list", async () => {
    const deps = makeDeps({ snapshots: [] });

    await runMmPremiumCycle(deps);

    expect(deps.mintClient.splitPosition).not.toHaveBeenCalled();
    expect(deps.executor.submit).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Stop-loss — midpoint drifts past `stopLossDrift`
// ---------------------------------------------------------------------------

describe("runMmPremiumCycle — stop-loss", () => {
  it("cancels both legs and logs cycle_stop_loss on upward drift past threshold", async () => {
    // Entry midpoint is 0.5 (snapshot default); stopLossDrift is 0.05.
    // Reading midpoint as 0.6 puts drift at 0.10 → past threshold.
    const deps = makeDeps({ midpoint: 0.6 });

    await runMmPremiumCycle(deps);

    expect(deps.executor.cancel).toHaveBeenCalledTimes(2);
    const cancelledIds = new Set(
      deps.executor.cancel.mock.calls.map(([id]) => id as string),
    );
    expect(cancelledIds.has(YES_ORDER_ID)).toBe(true);
    expect(cancelledIds.has(NO_ORDER_ID)).toBe(true);

    expect(logTypes(deps.log)).toContain("cycle_stop_loss");
  });

  it("triggers stop-loss on a downward midpoint drift past threshold", async () => {
    const deps = makeDeps({ midpoint: 0.4 });

    await runMmPremiumCycle(deps);

    expect(deps.executor.cancel).toHaveBeenCalledTimes(2);
    expect(logTypes(deps.log)).toContain("cycle_stop_loss");
  });

  it("does NOT log cycle_reconcile when stop-loss exits the cycle", async () => {
    const deps = makeDeps({ midpoint: 0.6 });

    await runMmPremiumCycle(deps);

    expect(logTypes(deps.log)).not.toContain("cycle_reconcile");
  });
});

// ---------------------------------------------------------------------------
// Partial-leg failure — NO submit throws after YES succeeds
// ---------------------------------------------------------------------------

describe("runMmPremiumCycle — partial-leg failure unwind", () => {
  it("cancels YES and calls mergePositions when the NO leg submit throws", async () => {
    const deps = makeDeps({
      submitNo: async () => {
        throw new Error("NO leg rejected by exchange");
      },
    });

    await runMmPremiumCycle(deps);

    // YES submitted successfully, NO threw. Both submits attempted.
    expect(deps.executor.submit).toHaveBeenCalledTimes(2);

    // YES must be cancelled to free its collateral half.
    const cancelledIds = deps.executor.cancel.mock.calls.map(
      ([id]) => id as string,
    );
    expect(cancelledIds).toContain(YES_ORDER_ID);
    // NO never created an order, so it cannot be cancelled.
    expect(cancelledIds).not.toContain(NO_ORDER_ID);

    // mergePositions unwinds the matched pair minted by splitPosition.
    expect(deps.mintClient.mergePositions).toHaveBeenCalledTimes(1);
    const [mergeArgs] = deps.mintClient.mergePositions.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    const [splitArgs] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(mergeArgs.conditionId).toBe(splitArgs.conditionId);
    expect(mergeArgs.amount).toBe(splitArgs.amount);
  });

  it("does not enter the fill-poll loop after the partial-failure unwind", async () => {
    const deps = makeDeps({
      submitNo: async () => {
        throw new Error("NO leg rejected by exchange");
      },
    });

    await runMmPremiumCycle(deps);

    // YES is cancelled, NO never existed → no live legs left to poll.
    expect(deps.fetchOrderStatus).not.toHaveBeenCalled();
  });
});
