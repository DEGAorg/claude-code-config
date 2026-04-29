/**
 * Tests for `canon/templates/strategies/arb-binary/entry.ts`.
 *
 * Pins the contract for the bootstrap module after the live-execution
 * refactor (item 6 of the 20260429-arb01-live-executor plan):
 *
 *   - `parseEntryFlags(argv)` returns `{ dryRun }` based on `--live` /
 *     `--dry-run`. Default (no flag) is dry-run. `--live` flips to live.
 *   - `createEntryRisk()` returns the same `ArbBinaryRisk` instance the
 *     bootstrap uses, wired with `maxConsecutiveLosses=3`. Three losses
 *     must trip the circuit breaker and reject the next signal.
 *   - `createEntryDeps({ dryRun })` returns `{ executor, positions }`
 *     wired to the live adapters from `canon/templates/live-executor.ts`
 *     and `canon/templates/live-positions.ts` — never the in-file stubs
 *     (those are removed by item 6, completion criterion: `grep -c
 *     "stubExecutor\\|stubPositions" entry.ts` returns 0).
 *
 * The Polymarket client is mocked at the module boundary so importing
 * entry.ts never touches the network and the bootstrap's top-level
 * runner.start() (if any) is harmless.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { TradeSignal } from "../../../types/TradeSignal.js";
import type { Portfolio } from "../../../types/RiskInterface.js";

const mockCreateOrder = vi.fn(async () => ({
  id: "ord-test",
  status: "submitted",
}));
const mockCancelOrder = vi.fn(async () => ({ success: true }));
const mockSearchMarkets = vi.fn(async () => []);
const mockFetchOrderBook = vi.fn(async (tokenId: string) => ({
  tokenId,
  asks: [],
  bids: [],
}));
const mockFetchBalance = vi.fn(async () => []);
const mockFetchPositions = vi.fn(async () => []);
const mockFetchOpenOrders = vi.fn(async () => []);

vi.mock("../../../client-polymarket.js", () => ({
  createOrder: mockCreateOrder,
  cancelOrder: mockCancelOrder,
  searchMarkets: mockSearchMarkets,
  fetchOrderBook: mockFetchOrderBook,
  fetchBalance: mockFetchBalance,
  fetchPositions: mockFetchPositions,
  fetchOpenOrders: mockFetchOpenOrders,
}));

interface EntryModule {
  parseEntryFlags: (argv: readonly string[]) => { dryRun: boolean };
  createEntryRisk: () => {
    preTradeCheck: (
      s: TradeSignal,
      p: Portfolio,
    ) => {
      approved: boolean;
      rejection_reason?: string;
      modified_size?: number;
    };
    recordOutcome: (won: boolean) => void;
  };
  createEntryDeps: (flags: { dryRun: boolean }) => {
    executor: {
      submit: (s: TradeSignal) => Promise<{ id: string; status: string }>;
    };
    positions: {
      reconcile: () => Promise<Portfolio>;
      getPortfolio: () => Portfolio;
    };
  };
}

let entry: EntryModule;

beforeEach(async () => {
  vi.clearAllMocks();
  vi.resetModules();
  entry = (await import("../entry.js")) as unknown as EntryModule;
});

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

function makeSignal(overrides?: Partial<TradeSignal>): TradeSignal {
  return {
    automation_id: "arb-binary",
    timestamp: new Date("2026-04-29T12:00:00Z"),
    market: {
      platform: "polymarket",
      market_id: "cond-001",
      question: "Will the Lakers win?",
    },
    direction: "buy_yes",
    size: 200,
    confidence: 0.95,
    urgency: "immediate",
    metadata: {
      grossEdge: 0.2,
      totalFees: 0.036,
      netEdge: 0.164,
      netReturn: 0.205,
    },
    ...overrides,
  };
}

function makePortfolio(overrides?: Partial<Portfolio>): Portfolio {
  return {
    total_value: 10_000,
    positions: [],
    daily_pnl: 0,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// parseEntryFlags — --live / --dry-run / default
// ---------------------------------------------------------------------------

describe("parseEntryFlags", () => {
  it("defaults to dry-run when no flag is provided", () => {
    const flags = entry.parseEntryFlags(["node", "entry.js"]);
    expect(flags.dryRun).toBe(true);
  });

  it("returns dryRun=false when --live is set", () => {
    const flags = entry.parseEntryFlags(["node", "entry.js", "--live"]);
    expect(flags.dryRun).toBe(false);
  });

  it("returns dryRun=true when --dry-run is explicitly set", () => {
    const flags = entry.parseEntryFlags(["node", "entry.js", "--dry-run"]);
    expect(flags.dryRun).toBe(true);
  });

  it("ignores unrelated argv entries", () => {
    const flags = entry.parseEntryFlags([
      "node",
      "entry.js",
      "--some-other-flag",
      "value",
    ]);
    expect(flags.dryRun).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// createEntryRisk — circuit breaker after 3 consecutive losses
// ---------------------------------------------------------------------------

describe("createEntryRisk", () => {
  it("approves a normal signal before any losses are recorded", () => {
    const risk = entry.createEntryRisk();
    const decision = risk.preTradeCheck(makeSignal(), makePortfolio());
    expect(decision.approved).toBe(true);
  });

  it("trips the circuit breaker after 3 consecutive losses", () => {
    const risk = entry.createEntryRisk();

    risk.recordOutcome(false);
    risk.recordOutcome(false);
    risk.recordOutcome(false);

    const decision = risk.preTradeCheck(makeSignal(), makePortfolio());
    expect(decision.approved).toBe(false);
    expect(decision.rejection_reason).toBeDefined();
    expect(decision.rejection_reason).toMatch(/circuit.?breaker/i);
  });

  it("does NOT trip the circuit breaker after only 2 consecutive losses", () => {
    const risk = entry.createEntryRisk();

    risk.recordOutcome(false);
    risk.recordOutcome(false);

    const decision = risk.preTradeCheck(makeSignal(), makePortfolio());
    expect(decision.approved).toBe(true);
  });

  it("resets the consecutive-loss counter on a win", () => {
    const risk = entry.createEntryRisk();

    risk.recordOutcome(false);
    risk.recordOutcome(false);
    risk.recordOutcome(true); // win — reset
    risk.recordOutcome(false);
    risk.recordOutcome(false);

    const decision = risk.preTradeCheck(makeSignal(), makePortfolio());
    expect(decision.approved).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// createEntryDeps — wires live executor / positions, no stubs
// ---------------------------------------------------------------------------

describe("createEntryDeps", () => {
  it("returns an executor and a positions adapter regardless of dryRun", () => {
    const live = entry.createEntryDeps({ dryRun: false });
    expect(typeof live.executor.submit).toBe("function");
    expect(typeof live.positions.reconcile).toBe("function");
    expect(typeof live.positions.getPortfolio).toBe("function");

    const dry = entry.createEntryDeps({ dryRun: true });
    expect(typeof dry.executor.submit).toBe("function");
    expect(typeof dry.positions.reconcile).toBe("function");
  });

  it("wires the live polymarket client into executor.submit (no stub)", async () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    const result = await deps.executor.submit(makeSignal());

    expect(mockCreateOrder).toHaveBeenCalledTimes(1);
    expect(result.id).toBe("ord-test");
    expect(result.status).toBe("submitted");
  });

  it("wires the live polymarket client into positions.reconcile (no stub)", async () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    await deps.positions.reconcile();

    expect(mockFetchBalance).toHaveBeenCalledTimes(1);
    expect(mockFetchPositions).toHaveBeenCalledTimes(1);
    expect(mockFetchOpenOrders).toHaveBeenCalledTimes(1);
  });
});
