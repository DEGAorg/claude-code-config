/**
 * Tests for the MINT-01 cycle orchestrator (`runCycle`).
 *
 * The orchestrator composes the pure helpers (`selectMarket`, `planLegs`,
 * `shouldStopLoss`) with the injected I/O surface:
 *
 *   scan → splitPosition → submit YES + NO legs → fill-poll loop
 *   → cancel remaining on timeout OR stop-loss OR partial-leg failure
 *
 * Every test injects the deps and asserts on call shape — no real network,
 * no real chain. The pre-hydrated dependency injection mirrors the pattern
 * already used by `scan.ts` (item 4) and the live-executor tests.
 *
 * The contract this file pins (to be satisfied by item 6):
 *
 *   ```ts
 *   runCycle(deps: RunCycleDeps): Promise<CycleResult>
 *   ```
 *
 *   - On a viable scan: `splitPosition({conditionId, amount: cycleCapital*1e6})`
 *     fires once → both legs submit → fill-poll runs → on timeout each
 *     unfilled leg is cancelled → log emits `mint_set`, `cycle_start`,
 *     `cycle_reconcile`.
 *   - On midpoint drift > `stopLossDrift`: both legs are cancelled and the
 *     log emits `cycle_stop_loss`.
 *   - On partial-leg submit failure (e.g. NO throws after YES succeeds):
 *     YES is cancelled and `mintClient.mergePositions` is called to unwind
 *     the minted pair.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

import { runCycle, type MarketCandidate } from "../cycle.js";
import { DEFAULT_MINT_01_CONFIG, type Mint01Config } from "../config.js";
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

function makeConfig(overrides?: Partial<Mint01Config>): Mint01Config {
  return { ...DEFAULT_MINT_01_CONFIG, ...overrides };
}

function makeCandidate(
  overrides?: Partial<MarketCandidate>,
): MarketCandidate {
  return {
    conditionId: "0xcond-001",
    question: "Will the Lakers win?",
    midpoint: 0.5,
    timeToCloseMs: 7 * 24 * 60 * 60 * 1000,
    volume24h: 50_000,
    openInterest: 20_000,
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
  config: Mint01Config;
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
function timeoutOnFirstPoll(maxCycleDurationMs: number): ReturnType<typeof vi.fn> {
  let call = 0;
  return vi.fn(() => {
    const t = call === 0 ? 0 : maxCycleDurationMs + 1;
    call += 1;
    return t;
  });
}

/**
 * Default deps: viable scan, both legs submit cleanly, both orders stay
 * "submitted" (non-terminal) so the timeout path is exercised, midpoint
 * stays flat so stop-loss does not trigger.
 */
function makeDeps(overrides?: {
  config?: Mint01Config;
  candidates?: MarketCandidate[];
  midpoint?: number;
  submitYes?: () => Promise<{ id: string; status: string }>;
  submitNo?: () => Promise<{ id: string; status: string }>;
}): CycleDeps {
  const config = overrides?.config ?? makeConfig();
  const candidates = overrides?.candidates ?? [makeCandidate()];

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
    scan: { fetchSnapshots: vi.fn(async () => candidates) },
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

// ---------------------------------------------------------------------------
// Happy-path: viable scan → mint → two legs → fill-poll → timeout reconcile
// ---------------------------------------------------------------------------

describe("runCycle — happy path (timeout reconcile)", () => {
  let deps: CycleDeps;

  beforeEach(() => {
    deps = makeDeps();
  });

  it("calls scan.fetchSnapshots exactly once", async () => {
    await runCycle(deps);
    expect(deps.scan.fetchSnapshots).toHaveBeenCalledTimes(1);
  });

  it("picks the highest-volume candidate for the splitPosition target", async () => {
    deps = makeDeps({
      candidates: [
        makeCandidate({ conditionId: "0xlow", volume24h: 12_000 }),
        makeCandidate({ conditionId: "0xhigh", volume24h: 80_000 }),
        makeCandidate({ conditionId: "0xmid", volume24h: 30_000 }),
      ],
    });

    await runCycle(deps);

    expect(deps.mintClient.splitPosition).toHaveBeenCalledTimes(1);
    const [args] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(args.conditionId).toBe("0xhigh");
  });

  it("calls splitPosition with amount = cycleCapital * 10^6 (USDC.e 6 decimals)", async () => {
    deps = makeDeps({ config: makeConfig({ cycleCapital: 1_000 }) });
    await runCycle(deps);

    const [args] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(args.amount).toBe(1_000_000_000n);
  });

  it("scales the splitPosition amount with cycleCapital override", async () => {
    deps = makeDeps({ config: makeConfig({ cycleCapital: 2_500 }) });
    await runCycle(deps);

    const [args] = deps.mintClient.splitPosition.mock.calls[0] as [
      { conditionId: string; amount: bigint },
    ];
    expect(args.amount).toBe(2_500_000_000n);
  });

  it("submits two legs (YES + NO) with the right tokenIds and prices", async () => {
    await runCycle(deps);

    expect(deps.executor.submit).toHaveBeenCalledTimes(2);

    const calls = deps.executor.submit.mock.calls.map(
      ([signal]) => signal as TradeSignal,
    );
    const yesCall = calls.find((c) => c.direction === "sell_yes");
    const noCall = calls.find((c) => c.direction === "sell_no");

    expect(yesCall).toBeDefined();
    expect(noCall).toBeDefined();

    expect(yesCall?.metadata["yesTokenId"]).toBe(YES_TOKEN_ID);
    expect(yesCall?.metadata["noTokenId"]).toBe(NO_TOKEN_ID);
    expect(yesCall?.metadata["yesPrice"]).toBeCloseTo(0.5075, 6);

    expect(noCall?.metadata["yesTokenId"]).toBe(YES_TOKEN_ID);
    expect(noCall?.metadata["noTokenId"]).toBe(NO_TOKEN_ID);
    expect(noCall?.metadata["noPrice"]).toBeCloseTo(0.5075, 6);
  });

  it("polls order status for both legs (fill-poll runs)", async () => {
    await runCycle(deps);

    expect(deps.fetchOrderStatus).toHaveBeenCalled();
    const polledIds = new Set(
      deps.fetchOrderStatus.mock.calls.map(([id]) => id as string),
    );
    expect(polledIds.has(YES_ORDER_ID)).toBe(true);
    expect(polledIds.has(NO_ORDER_ID)).toBe(true);
  });

  it("cancels both unfilled legs when the cycle deadline expires", async () => {
    await runCycle(deps);

    expect(deps.executor.cancel).toHaveBeenCalledTimes(2);
    const cancelledIds = new Set(
      deps.executor.cancel.mock.calls.map(([id]) => id as string),
    );
    expect(cancelledIds.has(YES_ORDER_ID)).toBe(true);
    expect(cancelledIds.has(NO_ORDER_ID)).toBe(true);
  });

  it("emits mint_set, cycle_start, and cycle_reconcile events", async () => {
    await runCycle(deps);

    const types = logTypes(deps.log);
    expect(types).toContain("mint_set");
    expect(types).toContain("cycle_start");
    expect(types).toContain("cycle_reconcile");
  });

  it("calls splitPosition AFTER scan and BEFORE the first submit (call order)", async () => {
    await runCycle(deps);

    const scanOrder = deps.scan.fetchSnapshots.mock.invocationCallOrder[0];
    const splitOrder = deps.mintClient.splitPosition.mock.invocationCallOrder[0];
    const firstSubmitOrder = deps.executor.submit.mock.invocationCallOrder[0];
    const firstCancelOrder = deps.executor.cancel.mock.invocationCallOrder[0];

    expect(scanOrder).toBeLessThan(splitOrder!);
    expect(splitOrder).toBeLessThan(firstSubmitOrder!);
    expect(firstSubmitOrder).toBeLessThan(firstCancelOrder!);
  });
});

// ---------------------------------------------------------------------------
// No viable candidate
// ---------------------------------------------------------------------------

describe("runCycle — no viable candidate", () => {
  it("does not mint, submit, or cancel when scan returns no viable markets", async () => {
    const deps = makeDeps({
      candidates: [makeCandidate({ volume24h: 0, openInterest: 0 })],
    });

    await runCycle(deps);

    expect(deps.mintClient.splitPosition).not.toHaveBeenCalled();
    expect(deps.executor.submit).not.toHaveBeenCalled();
    expect(deps.executor.cancel).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Stop-loss — midpoint drifts past `stopLossDrift`
// ---------------------------------------------------------------------------

describe("runCycle — stop-loss", () => {
  it("cancels both legs and logs cycle_stop_loss on drift past threshold", async () => {
    // Entry midpoint is 0.5 (candidate default); stopLossDrift is 0.05.
    // Reading midpoint as 0.6 puts drift at 0.10 → past threshold.
    const deps = makeDeps({ midpoint: 0.6 });

    await runCycle(deps);

    expect(deps.executor.cancel).toHaveBeenCalledTimes(2);
    const cancelledIds = new Set(
      deps.executor.cancel.mock.calls.map(([id]) => id as string),
    );
    expect(cancelledIds.has(YES_ORDER_ID)).toBe(true);
    expect(cancelledIds.has(NO_ORDER_ID)).toBe(true);

    const types = logTypes(deps.log);
    expect(types).toContain("cycle_stop_loss");
  });

  it("triggers stop-loss on a downward midpoint drift past threshold", async () => {
    const deps = makeDeps({ midpoint: 0.4 });

    await runCycle(deps);

    expect(deps.executor.cancel).toHaveBeenCalledTimes(2);
    expect(logTypes(deps.log)).toContain("cycle_stop_loss");
  });

  it("does NOT log cycle_reconcile when stop-loss exits the cycle", async () => {
    const deps = makeDeps({ midpoint: 0.6 });

    await runCycle(deps);

    expect(logTypes(deps.log)).not.toContain("cycle_reconcile");
  });
});

// ---------------------------------------------------------------------------
// Partial-leg failure — NO submit throws after YES succeeds
// ---------------------------------------------------------------------------

describe("runCycle — partial-leg failure unwind", () => {
  it("cancels YES and calls mergePositions when the NO leg submit throws", async () => {
    const deps = makeDeps({
      submitNo: async () => {
        throw new Error("NO leg rejected by exchange");
      },
    });

    await runCycle(deps);

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

    await runCycle(deps);

    // YES is cancelled, NO never existed → no live legs left to poll.
    expect(deps.fetchOrderStatus).not.toHaveBeenCalled();
  });
});
