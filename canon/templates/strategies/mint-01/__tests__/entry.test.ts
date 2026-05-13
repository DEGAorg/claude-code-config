/**
 * Tests for `canon/templates/strategies/mint-01/entry.ts`.
 *
 * Covers the four clauses from the plan item:
 *   1. flag parsing — `--live` flips dryRun, default is dry-run.
 *   2. capability gate — `assertLiveCapabilities` consults the sidecar
 *      and refuses to run when `supportsTif` is false.
 *   3. allowance injection — `createEntryDeps({ allowance })` threads a
 *      fake `AllowanceClient` into the live executor; the executor
 *      consults `getAllowance` and tops up via `approve` before the
 *      first `createOrder`.
 *   4. integration trace — `detectMint01Candidate → planLegs →
 *      signalToOrderParams` produces CLOB-shaped tokenIds on BOTH the
 *      sell_yes and sell_no legs, and the same shape reaches
 *      `createOrder` end-to-end via the live executor.
 *
 * The Polymarket client is mocked at the module boundary so importing
 * entry.ts never touches the network.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import type { TradeSignal } from "../../../types/TradeSignal.js";
import type { MarketCandidate } from "../cycle.js";

const mockCreateOrder = vi.fn(async (params: { tokenId: string }) => ({
  id: `ord-${params.tokenId.slice(0, 6)}`,
  marketId: "cond-001",
  outcomeId: params.tokenId,
  side: "sell" as const,
  type: "limit" as const,
  amount: 0,
  price: 0,
  status: "submitted",
  filled: 0,
  remaining: 0,
}));
const mockCancelOrder = vi.fn(async () => ({ id: "ord-x", status: "cancelled" }));
const mockGetCapabilities = vi.fn(async () => ({ supportsTif: true }));
const mockFetchOpenOrders = vi.fn(async () => []);
const mockFetchMarketPrice = vi.fn(async () => ({
  conditionId: "cond-001",
  yes: 0.5,
  no: 0.5,
  timestamp: new Date(),
}));
const mockFetchBinaryMarketSnapshots = vi.fn(async () => []);

vi.mock("../../../client-polymarket.js", () => ({
  createOrder: mockCreateOrder,
  cancelOrder: mockCancelOrder,
  getCapabilities: mockGetCapabilities,
  fetchOpenOrders: mockFetchOpenOrders,
  fetchMarketPrice: mockFetchMarketPrice,
  fetchBinaryMarketSnapshots: mockFetchBinaryMarketSnapshots,
}));

const mockRunCycle = vi.fn(async () => ({ status: "no_candidate" as const }));

vi.mock("../cycle.js", async () => {
  const actual =
    await vi.importActual<typeof import("../cycle.js")>("../cycle.js");
  return { ...actual, runCycle: mockRunCycle };
});

interface FakeAllowanceClient {
  getAllowance: (() => Promise<bigint>) & ReturnType<typeof vi.fn>;
  approve: ((amount: bigint) => Promise<{ txHash: string }>) &
    ReturnType<typeof vi.fn>;
}

function makeFakeAllowance(initial = 0n): FakeAllowanceClient {
  return {
    getAllowance: vi.fn(async () => initial),
    approve: vi.fn(async () => ({ txHash: "0xabc" })),
  };
}

interface EntryModule {
  parseEntryFlags: (argv: readonly string[]) => { dryRun: boolean };
  assertLiveCapabilities: () => Promise<void>;
  detectMint01Candidate: typeof import("../entry.js").detectMint01Candidate;
  resolveMint01Order: typeof import("../entry.js").resolveMint01Order;
  createEntryDeps: typeof import("../entry.js").createEntryDeps;
  buildLiveAllowanceClient: typeof import("../entry.js").buildLiveAllowanceClient;
  buildCtfAllowanceClient: typeof import("../entry.js").buildCtfAllowanceClient;
  buildLiveMintClient: typeof import("../entry.js").buildLiveMintClient;
  main: typeof import("../entry.js").main;
}

let entry: EntryModule;

beforeEach(async () => {
  vi.clearAllMocks();
  vi.resetModules();
  mockGetCapabilities.mockImplementation(async () => ({ supportsTif: true }));
  mockFetchOpenOrders.mockImplementation(async () => []);
  mockFetchMarketPrice.mockImplementation(async () => ({
    conditionId: "cond-001",
    yes: 0.5,
    no: 0.5,
    timestamp: new Date(),
  }));
  mockFetchBinaryMarketSnapshots.mockImplementation(async () => []);
  mockRunCycle.mockImplementation(async () => ({ status: "no_candidate" as const }));
  entry = (await import("../entry.js")) as unknown as EntryModule;
});

const YES_TOKEN_ID =
  "12345678901234567890123456789012345678901234567890123456789012345";
const NO_TOKEN_ID =
  "98765432109876543210987654321098765432109876543210987654321098765";

function makeCandidate(overrides?: Partial<MarketCandidate>): MarketCandidate {
  return {
    conditionId: "0xcondition",
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

// ---------------------------------------------------------------------------
// parseEntryFlags
// ---------------------------------------------------------------------------

describe("parseEntryFlags", () => {
  it("defaults to dry-run when no flag is provided", () => {
    expect(entry.parseEntryFlags(["node", "entry.js"]).dryRun).toBe(true);
  });

  it("returns dryRun=false when --live is set", () => {
    expect(
      entry.parseEntryFlags(["node", "entry.js", "--live"]).dryRun,
    ).toBe(false);
  });

  it("returns dryRun=true when --dry-run is explicitly set", () => {
    expect(
      entry.parseEntryFlags(["node", "entry.js", "--dry-run"]).dryRun,
    ).toBe(true);
  });

  it("ignores unrelated argv entries", () => {
    expect(
      entry.parseEntryFlags(["node", "entry.js", "--other", "v"]).dryRun,
    ).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// assertLiveCapabilities
// ---------------------------------------------------------------------------

describe("assertLiveCapabilities", () => {
  it("resolves when the sidecar advertises tif support", async () => {
    mockGetCapabilities.mockResolvedValueOnce({ supportsTif: true });
    await expect(entry.assertLiveCapabilities()).resolves.toBeUndefined();
    expect(mockGetCapabilities).toHaveBeenCalledTimes(1);
  });

  it("rejects when the sidecar does not advertise tif support", async () => {
    mockGetCapabilities.mockResolvedValueOnce({ supportsTif: false });
    await expect(entry.assertLiveCapabilities()).rejects.toThrow(
      /time-in-force/,
    );
  });
});

// ---------------------------------------------------------------------------
// detectMint01Candidate — emits a CLOB-shaped two-leg signal pair
// ---------------------------------------------------------------------------

describe("detectMint01Candidate", () => {
  it("returns null when no candidate passes the filter gate", () => {
    const result = entry.detectMint01Candidate([
      makeCandidate({ volume24h: 0, openInterest: 0 }),
    ]);
    expect(result).toBeNull();
  });

  it("emits sell_yes + sell_no signals at midpoint + premium on each leg", () => {
    const result = entry.detectMint01Candidate([makeCandidate()]);
    expect(result).not.toBeNull();
    const { signals, legs } = result!;
    expect(signals).toHaveLength(2);
    const [yesSig, noSig] = signals;
    expect(yesSig.direction).toBe("sell_yes");
    expect(noSig.direction).toBe("sell_no");
    expect(yesSig.metadata["yesTokenId"]).toBe(YES_TOKEN_ID);
    expect(yesSig.metadata["noTokenId"]).toBe(NO_TOKEN_ID);
    expect(noSig.metadata["yesTokenId"]).toBe(YES_TOKEN_ID);
    expect(noSig.metadata["noTokenId"]).toBe(NO_TOKEN_ID);
    expect(legs.yesPrice).toBeCloseTo(0.5075, 6);
    expect(legs.noPrice).toBeCloseTo(0.5075, 6);
    // Size reflects the shipped default cycleCapital ($5 — safe smoke
    // size). Spec target is $1,000 for production — operators override
    // in their scaffolded `src/config.ts`.
    expect(yesSig.size).toBe(5);
  });
});

// ---------------------------------------------------------------------------
// createEntryDeps — wires LiveExecutor + allowance injection
// ---------------------------------------------------------------------------

describe("createEntryDeps", () => {
  it("returns a live executor with submit/cancel functions", () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    expect(typeof deps.executor.submit).toBe("function");
    expect(typeof deps.executor.cancel).toBe("function");
  });

  it("threads an injected allowance client into the live executor", async () => {
    const allowance = makeFakeAllowance(0n);
    const result = entry.detectMint01Candidate([makeCandidate()])!;
    const deps = entry.createEntryDeps({ dryRun: false }, { allowance });

    await deps.executor.submit(result.signals[0]);

    expect(allowance.getAllowance).toHaveBeenCalledTimes(1);
    expect(allowance.approve).toHaveBeenCalledTimes(1);
    expect(mockCreateOrder).toHaveBeenCalledTimes(1);
  });

  it("does not approve when the cached allowance already meets the threshold", async () => {
    const allowance = makeFakeAllowance(200_000_000_000n);
    const result = entry.detectMint01Candidate([makeCandidate()])!;
    const deps = entry.createEntryDeps({ dryRun: false }, { allowance });

    await deps.executor.submit(result.signals[0]);
    await deps.executor.submit(result.signals[1]);

    expect(allowance.getAllowance).toHaveBeenCalledTimes(1);
    expect(allowance.approve).not.toHaveBeenCalled();
    expect(mockCreateOrder).toHaveBeenCalledTimes(2);
  });
});

// ---------------------------------------------------------------------------
// resolveMint01Order — picks the correct tokenId/price per leg
// ---------------------------------------------------------------------------

describe("resolveMint01Order", () => {
  it("returns the YES tokenId and yesPrice for the sell_yes leg", () => {
    const { signals } = entry.detectMint01Candidate([makeCandidate()])!;
    const resolved = entry.resolveMint01Order(signals[0]);
    expect(resolved.tokenIds.yes).toBe(YES_TOKEN_ID);
    expect(resolved.tokenIds.no).toBe(NO_TOKEN_ID);
    expect(resolved.price).toBeCloseTo(0.5075, 6);
    expect(resolved.timeInForce).toBe("GTC");
  });

  it("returns the NO leg's noPrice for the sell_no leg", () => {
    const { signals } = entry.detectMint01Candidate([
      makeCandidate({ midpoint: 0.4 }),
    ])!;
    const resolved = entry.resolveMint01Order(signals[1]);
    expect(resolved.price).toBeCloseTo(0.6075, 6);
  });

  it("throws when token ids are missing from metadata", () => {
    const stub: TradeSignal = {
      automation_id: "mint-01",
      timestamp: new Date(),
      market: { platform: "polymarket", market_id: "x", question: "?" },
      direction: "sell_yes",
      size: 1,
      confidence: 1,
      urgency: "normal",
      metadata: { yesPrice: 0.5, noPrice: 0.5 },
    };
    expect(() => entry.resolveMint01Order(stub)).toThrow(/yesTokenId/);
  });
});

// ---------------------------------------------------------------------------
// Integration trace — both legs reach createOrder with CLOB-shaped tokenIds
// ---------------------------------------------------------------------------

describe("integration trace (selectMarket → planLegs → signalToOrderParams)", () => {
  it("forwards 77-digit decimal token ids for BOTH legs end-to-end", async () => {
    const { signalToOrderParams } = (await import(
      "../../../order-executor.js"
    )) as typeof import("../../../order-executor.js");

    const detected = entry.detectMint01Candidate([makeCandidate()]);
    expect(detected).not.toBeNull();
    const [yesSig, noSig] = detected!.signals;

    // Direct chain: signal → resolveMint01Order → signalToOrderParams.
    const yesResolved = entry.resolveMint01Order(yesSig);
    const yesParams = signalToOrderParams(
      yesSig,
      yesResolved.tokenIds,
      yesResolved.price,
      yesResolved.timeInForce,
    );
    const noResolved = entry.resolveMint01Order(noSig);
    const noParams = signalToOrderParams(
      noSig,
      noResolved.tokenIds,
      noResolved.price,
      noResolved.timeInForce,
    );

    expect(yesParams.tokenId).toBe(YES_TOKEN_ID);
    expect(yesParams.tokenId).toMatch(/^\d{60,}$/);
    expect(yesParams.side).toBe("sell");
    expect(yesParams.orderType).toBe("limit");
    expect(yesParams.timeInForce).toBe("GTC");

    expect(noParams.tokenId).toBe(NO_TOKEN_ID);
    expect(noParams.tokenId).toMatch(/^\d{60,}$/);
    expect(noParams.side).toBe("sell");

    // End-to-end via the live executor still produces the same shape on
    // both legs.
    const deps = entry.createEntryDeps({ dryRun: false });
    await deps.executor.submit(yesSig);
    await deps.executor.submit(noSig);

    expect(mockCreateOrder).toHaveBeenCalledTimes(2);
    expect(mockCreateOrder).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        tokenId: YES_TOKEN_ID,
        side: "sell",
        timeInForce: "GTC",
      }),
    );
    expect(mockCreateOrder).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        tokenId: NO_TOKEN_ID,
        side: "sell",
        timeInForce: "GTC",
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// buildLiveAllowanceClient — WalletStore injection
// ---------------------------------------------------------------------------

interface FakeWalletStore {
  hasWallet: ReturnType<typeof vi.fn>;
  getPrivateKey: ReturnType<typeof vi.fn>;
  getAddress: ReturnType<typeof vi.fn>;
  ensure: ReturnType<typeof vi.fn>;
}

function makeFakeWallet(opts: {
  hasWallet?: boolean;
  address?: string;
  privateKey?: string;
} = {}): FakeWalletStore {
  return {
    hasWallet: vi.fn(() => opts.hasWallet ?? true),
    getPrivateKey: vi.fn(() => opts.privateKey ?? "0x" + "a".repeat(64)),
    getAddress: vi.fn(async () => opts.address ?? "0xowner"),
    ensure: vi.fn(),
  };
}

describe("buildLiveAllowanceClient (WalletStore injection)", () => {
  it("returns undefined when the wallet store has no wallet", async () => {
    const wallet = makeFakeWallet({ hasWallet: false });
    const client = await entry.buildLiveAllowanceClient(
      wallet as unknown as Parameters<typeof entry.buildLiveAllowanceClient>[0],
    );
    expect(client).toBeUndefined();
    expect(wallet.hasWallet).toHaveBeenCalled();
    expect(wallet.getAddress).not.toHaveBeenCalled();
  });

  it("derives owner address from wallet.getAddress()", async () => {
    const wallet = makeFakeWallet({ address: "0xfromwallet" });
    const client = await entry.buildLiveAllowanceClient(
      wallet as unknown as Parameters<typeof entry.buildLiveAllowanceClient>[0],
    );
    expect(client).toBeDefined();
    expect(wallet.getAddress).toHaveBeenCalledTimes(1);
  });

  it("returns undefined when getAddress throws", async () => {
    const wallet = makeFakeWallet();
    wallet.getAddress.mockImplementationOnce(async () => {
      throw new Error("WalletNotFoundError");
    });
    const client = await entry.buildLiveAllowanceClient(
      wallet as unknown as Parameters<typeof entry.buildLiveAllowanceClient>[0],
    );
    expect(client).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// buildCtfAllowanceClient — mirrors buildLiveAllowanceClient with the
// ConditionalTokens contract as the spender (USDC.e → splitPosition pull).
// ---------------------------------------------------------------------------

describe("buildCtfAllowanceClient (ConditionalTokens spender)", () => {
  it("returns undefined when the wallet store has no wallet", async () => {
    const wallet = makeFakeWallet({ hasWallet: false });
    const client = await entry.buildCtfAllowanceClient(
      wallet as unknown as Parameters<typeof entry.buildCtfAllowanceClient>[0],
    );
    expect(client).toBeUndefined();
    expect(wallet.hasWallet).toHaveBeenCalled();
    expect(wallet.getAddress).not.toHaveBeenCalled();
  });

  it("returns an AllowanceClient (getAllowance + approve) when wallet is present", async () => {
    const wallet = makeFakeWallet({ address: "0xfromwallet" });
    const client = await entry.buildCtfAllowanceClient(
      wallet as unknown as Parameters<typeof entry.buildCtfAllowanceClient>[0],
    );
    expect(client).toBeDefined();
    expect(typeof client?.getAllowance).toBe("function");
    expect(typeof client?.approve).toBe("function");
    expect(wallet.getAddress).toHaveBeenCalledTimes(1);
  });

  it("returns undefined when getAddress throws", async () => {
    const wallet = makeFakeWallet();
    wallet.getAddress.mockImplementationOnce(async () => {
      throw new Error("WalletNotFoundError");
    });
    const client = await entry.buildCtfAllowanceClient(
      wallet as unknown as Parameters<typeof entry.buildCtfAllowanceClient>[0],
    );
    expect(client).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// createEntryDeps — mintClient + ctfAllowance passthrough
// ---------------------------------------------------------------------------

describe("createEntryDeps — mint plumbing", () => {
  it("exposes the injected mintClient on EntryDeps", () => {
    const mintClient = {
      splitPosition: vi.fn(async () => ({ txHash: "0xmint" })),
      mergePositions: vi.fn(async () => ({ txHash: "0xmerge" })),
    };
    const deps = entry.createEntryDeps(
      { dryRun: false },
      { mintClient } as Parameters<typeof entry.createEntryDeps>[1],
    );
    expect(deps.mintClient).toBe(mintClient);
    expect(typeof deps.mintClient?.splitPosition).toBe("function");
    expect(typeof deps.mintClient?.mergePositions).toBe("function");
  });

  it("exposes the injected ctfAllowance on EntryDeps", () => {
    const ctfAllowance = makeFakeAllowance(0n);
    const deps = entry.createEntryDeps(
      { dryRun: false },
      { ctfAllowance } as Parameters<typeof entry.createEntryDeps>[1],
    );
    expect(deps.ctfAllowance).toBe(ctfAllowance);
    expect(typeof deps.ctfAllowance?.getAllowance).toBe("function");
    expect(typeof deps.ctfAllowance?.approve).toBe("function");
  });

  it("omits mintClient and ctfAllowance when neither is injected", () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    expect(deps.mintClient).toBeUndefined();
    expect(deps.ctfAllowance).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// main — dry-run skips runCycle, --live invokes runCycle exactly once
// ---------------------------------------------------------------------------

describe("main", () => {
  let originalStdoutWrite: typeof process.stdout.write;

  beforeEach(() => {
    originalStdoutWrite = process.stdout.write;
    // Silence the "START MINT-01 cycle ..." banner during the assertion.
    process.stdout.write = vi.fn(() => true) as unknown as typeof process.stdout.write;
  });

  afterEach(() => {
    process.stdout.write = originalStdoutWrite;
  });

  it("exits cleanly without invoking runCycle in dry-run mode", async () => {
    await expect(
      entry.main({ argv: ["node", "entry.js"] }),
    ).resolves.toBeUndefined();
    expect(mockRunCycle).not.toHaveBeenCalled();
  });

  it("exits cleanly without invoking runCycle when --dry-run is explicit", async () => {
    await expect(
      entry.main({ argv: ["node", "entry.js", "--dry-run"] }),
    ).resolves.toBeUndefined();
    expect(mockRunCycle).not.toHaveBeenCalled();
  });

  it("invokes runCycle exactly once in --live mode with an injected wallet", async () => {
    const wallet = makeFakeWallet({ address: "0xowner" });
    await entry.main({
      argv: ["node", "entry.js", "--live"],
      wallet: wallet as unknown as Parameters<typeof entry.main>[0] extends
        | { wallet?: infer W }
        | undefined
        ? W
        : never,
    });
    expect(mockRunCycle).toHaveBeenCalledTimes(1);
  });

  it("passes the live cycle deps (config + executor + mintClient) to runCycle", async () => {
    const wallet = makeFakeWallet({ address: "0xowner" });
    await entry.main({
      argv: ["node", "entry.js", "--live"],
      wallet: wallet as unknown as Parameters<typeof entry.main>[0] extends
        | { wallet?: infer W }
        | undefined
        ? W
        : never,
    });
    expect(mockRunCycle).toHaveBeenCalledTimes(1);
    const firstCall = mockRunCycle.mock.calls[0] as unknown as [
      Record<string, unknown>,
    ];
    const runDeps = firstCall[0];
    expect(runDeps).toBeDefined();
    expect(runDeps["config"]).toBeDefined();
    expect(runDeps["executor"]).toBeDefined();
    expect(runDeps["mintClient"]).toBeDefined();
    expect(runDeps["scan"]).toBeDefined();
    expect(typeof runDeps["fetchOrderStatus"]).toBe("function");
    expect(typeof runDeps["fetchMidpoint"]).toBe("function");
    expect(typeof runDeps["now"]).toBe("function");
    expect(typeof runDeps["sleep"]).toBe("function");
    expect(typeof runDeps["log"]).toBe("function");
  });

  it("calls assertLiveCapabilities (sidecar check) before runCycle in --live", async () => {
    const wallet = makeFakeWallet({ address: "0xowner" });
    await entry.main({
      argv: ["node", "entry.js", "--live"],
      wallet: wallet as unknown as Parameters<typeof entry.main>[0] extends
        | { wallet?: infer W }
        | undefined
        ? W
        : never,
    });
    expect(mockGetCapabilities).toHaveBeenCalledTimes(1);
    const capsOrder = mockGetCapabilities.mock.invocationCallOrder[0];
    const cycleOrder = mockRunCycle.mock.invocationCallOrder[0];
    expect(capsOrder).toBeLessThan(cycleOrder!);
  });

  it("throws (and skips runCycle) when --live runs without an injected wallet that has a key", async () => {
    const wallet = makeFakeWallet({ hasWallet: false });
    await expect(
      entry.main({
        argv: ["node", "entry.js", "--live"],
        wallet: wallet as unknown as Parameters<typeof entry.main>[0] extends
          | { wallet?: infer W }
          | undefined
          ? W
          : never,
      }),
    ).rejects.toThrow(/wallet/);
    expect(mockRunCycle).not.toHaveBeenCalled();
  });
});
