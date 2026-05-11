/**
 * Tests for `canon/templates/strategies/mm-premium/entry.ts`.
 *
 * Pins the live-execution wiring contract and the `main()` branching
 * between the dry-run scanner (`runner.start()`) and the live cycle
 * orchestrator (`runMmPremiumCycle`).
 *
 * The Polymarket client, bankroll helper, execution log, runner factory
 * (`./main.js`), and cycle orchestrator (`./cycle.js`) are all mocked at
 * the module boundary so importing `entry.ts` never touches the network
 * or the filesystem.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { TradeSignal } from "../../../types/TradeSignal.js";
import type { Portfolio } from "../../../types/RiskInterface.js";

const mockCreateOrder = vi.fn(async () => ({
  id: "ord-test",
  status: "submitted",
}));
const mockCancelOrder = vi.fn(async () => ({ success: true }));
const mockFetchBinaryMarketSnapshots = vi.fn(async () => []);
const mockFetchBalance = vi.fn(async () => []);
const mockFetchPositions = vi.fn(async () => []);
const mockFetchOpenOrders = vi.fn(async () => []);
const mockGetCapabilities = vi.fn(async () => ({ supportsTif: true }));
const mockFetchMarketPrice = vi.fn(async () => ({
  conditionId: "cond-001",
  yes: 0.5,
  no: 0.5,
  timestamp: new Date(),
}));

vi.mock("../../../client-polymarket.js", () => ({
  createOrder: mockCreateOrder,
  cancelOrder: mockCancelOrder,
  fetchBinaryMarketSnapshots: mockFetchBinaryMarketSnapshots,
  fetchBalance: mockFetchBalance,
  fetchPositions: mockFetchPositions,
  fetchOpenOrders: mockFetchOpenOrders,
  getCapabilities: mockGetCapabilities,
  fetchMarketPrice: mockFetchMarketPrice,
}));

const mockOnboardStatus = vi.fn(async () => ({
  funderDeployed: true,
  approvalsReady: true,
  credsReady: true,
  fundedCollateral: 100,
  funderAddress: "0xFunder000000000000000000000000000000000F",
}));

vi.mock("../../../polymarket-onboard.js", () => ({
  polymarketOnboard: {
    venue: "polymarket",
    chainId: 137,
    build: () => ({
      status: mockOnboardStatus,
      ensureFunder: vi.fn(),
      ensureApprovals: vi.fn(),
      ensureCreds: vi.fn(),
      ensureFunded: vi.fn(),
    }),
  },
}));

// --- Cycle / runner stubs -----------------------------------------------
// `runMmPremiumCycle` is the live path; `createMintPremiumRunner` is the
// dry-run path. Both are mocked so `main()` tests can assert which branch
// fired without booting the real cycle loop or scanner.

const mockRunMmPremiumCycle = vi.fn(async () => ({
  status: "no_edge" as const,
}));

vi.mock("../cycle.js", async () => {
  const actual =
    await vi.importActual<typeof import("../cycle.js")>("../cycle.js");
  return { ...actual, runMmPremiumCycle: mockRunMmPremiumCycle };
});

const mockRunnerStart = vi.fn(async () => undefined);
const mockRunnerStop = vi.fn(() => undefined);
const mockCreateMintPremiumRunner = vi.fn(() => ({
  start: mockRunnerStart,
  stop: mockRunnerStop,
  isRunning: false,
}));

vi.mock("../main.js", () => ({
  createMintPremiumRunner: mockCreateMintPremiumRunner,
}));

// --- Bankroll + execution-log stubs ------------------------------------
// Avoid filesystem reads/writes during `main()`.

const mockResolveBankroll = vi.fn(async () => ({
  amount: 10_000,
  currency: "USDC" as const,
  source: "default-dry-run" as const,
  setAt: "2026-05-11T00:00:00.000Z",
}));
const mockFormatBankrollBanner = vi.fn(
  () => "Bankroll: $10,000 USDC (default-dry-run)",
);

vi.mock("../../../bankroll.js", () => ({
  resolveBankroll: mockResolveBankroll,
  formatBankrollBanner: mockFormatBankrollBanner,
}));

const mockAppendEntry = vi.fn();

vi.mock("../../../execution-log.js", () => ({
  appendEntry: mockAppendEntry,
}));

interface FakeAllowanceClient {
  getAllowance: (() => Promise<bigint>) & ReturnType<typeof vi.fn>;
  approve: ((amount: bigint) => Promise<{ txHash: string }>) &
    ReturnType<typeof vi.fn>;
}

interface FakeMintClient {
  splitPosition: ReturnType<typeof vi.fn>;
  mergePositions: ReturnType<typeof vi.fn>;
}

interface EntryModule {
  parseEntryFlags: (
    argv: readonly string[],
  ) => { dryRun: boolean; bankroll?: number };
  createEntryDeps: (
    flags: { dryRun: boolean },
    options?: {
      allowance?: FakeAllowanceClient;
      ctfAllowance?: FakeAllowanceClient;
      mintClient?: FakeMintClient;
      query?: string;
    },
  ) => {
    scan: { fetchSnapshots: () => Promise<unknown[]> };
    executor: {
      submit: (s: TradeSignal) => Promise<{ id: string; status: string }>;
    };
    positions: {
      reconcile: () => Promise<Portfolio>;
      getPortfolio: () => Portfolio;
    };
    mintClient?: FakeMintClient;
    ctfAllowance?: FakeAllowanceClient;
  };
  assertLiveCapabilities: () => Promise<void>;
  buildLiveAllowanceClient: (wallet: unknown) => Promise<unknown>;
  buildCtfAllowanceClient: (wallet: unknown) => Promise<unknown>;
  main: (opts?: {
    argv?: readonly string[];
    wallet?: unknown;
  }) => Promise<void>;
}

let entry: EntryModule;

beforeEach(async () => {
  vi.clearAllMocks();
  vi.resetModules();
  process.env["WALLET_PRIVATE_KEY"] = "0x" + "a".repeat(64);
  mockGetCapabilities.mockImplementation(async () => ({ supportsTif: true }));
  mockRunMmPremiumCycle.mockImplementation(async () => ({
    status: "no_edge" as const,
  }));
  mockRunnerStart.mockImplementation(async () => undefined);
  mockCreateMintPremiumRunner.mockImplementation(() => ({
    start: mockRunnerStart,
    stop: mockRunnerStop,
    isRunning: false,
  }));
  mockResolveBankroll.mockImplementation(async () => ({
    amount: 10_000,
    currency: "USDC" as const,
    source: "default-dry-run" as const,
    setAt: "2026-05-11T00:00:00.000Z",
  }));
  entry = (await import("../entry.js")) as unknown as EntryModule;
});

function makeFakeAllowance(initial = 0n): FakeAllowanceClient {
  return {
    getAllowance: vi.fn(async () => initial),
    approve: vi.fn(async () => ({ txHash: "0xabc" })),
  };
}

function makeFakeMintClient(): FakeMintClient {
  return {
    splitPosition: vi.fn(async () => ({ txHash: "0xsplit" })),
    mergePositions: vi.fn(async () => ({ txHash: "0xmerge" })),
  };
}

const yesTokenId =
  "12345678901234567890123456789012345678901234567890123456789012345";
const noTokenId =
  "98765432109876543210987654321098765432109876543210987654321098765";

function makeSignal(overrides?: Partial<TradeSignal>): TradeSignal {
  return {
    automation_id: "mm-premium",
    timestamp: new Date("2026-04-30T12:00:00Z"),
    market: {
      platform: "polymarket",
      market_id: "cond-001",
      question: "MM Premium?",
    },
    direction: "sell_yes",
    size: 1000,
    confidence: 0.7,
    urgency: "opportunistic",
    metadata: {
      yesTokenId,
      noTokenId,
      midpoint: 0.5,
      offsetC: 0.0075,
      cycleCapital: 1000,
      projectedNet: 13.3,
      timeToCloseMs: 3 * 24 * 60 * 60 * 1000,
    },
    ...overrides,
  };
}

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

describe("parseEntryFlags", () => {
  it("defaults to dry-run", () => {
    expect(entry.parseEntryFlags(["node", "entry.js"]).dryRun).toBe(true);
  });

  it("returns dryRun=false when --live is set", () => {
    expect(entry.parseEntryFlags(["node", "entry.js", "--live"]).dryRun).toBe(
      false,
    );
  });
});

describe("createEntryDeps", () => {
  it("returns live scan + executor + positions adapters", () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    expect(typeof deps.scan.fetchSnapshots).toBe("function");
    expect(typeof deps.executor.submit).toBe("function");
    expect(typeof deps.positions.reconcile).toBe("function");
  });

  it("scan.fetchSnapshots calls the live polymarket client", async () => {
    const deps = entry.createEntryDeps(
      { dryRun: false },
      { query: "Sports" },
    );
    await deps.scan.fetchSnapshots();
    expect(mockFetchBinaryMarketSnapshots).toHaveBeenCalledWith("Sports");
  });

  it("sell_yes uses YES token at midpoint + offsetC with GTC", async () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    await deps.executor.submit(makeSignal({ direction: "sell_yes" }));
    expect(mockCreateOrder).toHaveBeenCalledWith(
      expect.objectContaining({
        tokenId: yesTokenId,
        side: "sell",
        price: 0.5075,
        timeInForce: "GTC",
        orderType: "limit",
      }),
    );
  });

  it("sell_no uses NO token at (1 - midpoint) + offsetC with GTC", async () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    await deps.executor.submit(makeSignal({ direction: "sell_no" }));
    expect(mockCreateOrder).toHaveBeenCalledWith(
      expect.objectContaining({
        tokenId: noTokenId,
        side: "sell",
        price: 0.5075,
        timeInForce: "GTC",
        orderType: "limit",
      }),
    );
  });

  it("positions.reconcile calls the live polymarket client", async () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    await deps.positions.reconcile();
    expect(mockFetchBalance).toHaveBeenCalledTimes(1);
    expect(mockFetchPositions).toHaveBeenCalledTimes(1);
    expect(mockFetchOpenOrders).toHaveBeenCalledTimes(1);
  });

  it("threads an injected allowance client through the live executor", async () => {
    const allowance = makeFakeAllowance(0n);
    const deps = entry.createEntryDeps({ dryRun: false }, { allowance });

    await deps.executor.submit(makeSignal());

    expect(allowance.getAllowance).toHaveBeenCalledTimes(1);
    expect(allowance.approve).toHaveBeenCalledTimes(1);
  });

  it("does not approve when cached allowance already meets the threshold", async () => {
    const allowance = makeFakeAllowance(200_000_000_000n);
    const deps = entry.createEntryDeps({ dryRun: false }, { allowance });

    await deps.executor.submit(makeSignal());
    await deps.executor.submit(makeSignal());

    expect(allowance.getAllowance).toHaveBeenCalledTimes(1);
    expect(allowance.approve).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// createEntryDeps — mintClient + ctfAllowance passthrough
// ---------------------------------------------------------------------------

describe("createEntryDeps — mint plumbing", () => {
  it("exposes the injected mintClient on EntryDeps", () => {
    const mintClient = makeFakeMintClient();
    const deps = entry.createEntryDeps({ dryRun: false }, { mintClient });
    expect(deps.mintClient).toBe(mintClient);
    expect(typeof deps.mintClient?.splitPosition).toBe("function");
    expect(typeof deps.mintClient?.mergePositions).toBe("function");
  });

  it("exposes the injected ctfAllowance on EntryDeps", () => {
    const ctfAllowance = makeFakeAllowance(0n);
    const deps = entry.createEntryDeps({ dryRun: false }, { ctfAllowance });
    expect(deps.ctfAllowance).toBe(ctfAllowance);
    expect(typeof deps.ctfAllowance?.getAllowance).toBe("function");
    expect(typeof deps.ctfAllowance?.approve).toBe("function");
  });

  it("omits mintClient and ctfAllowance when neither is injected", () => {
    const deps = entry.createEntryDeps({ dryRun: false });
    expect(deps.mintClient).toBeUndefined();
    expect(deps.ctfAllowance).toBeUndefined();
  });

  it("threads both the CTF-Exchange allowance and the CTF allowance independently", () => {
    const allowance = makeFakeAllowance(0n);
    const ctfAllowance = makeFakeAllowance(0n);
    const deps = entry.createEntryDeps(
      { dryRun: false },
      { allowance, ctfAllowance },
    );
    expect(deps.ctfAllowance).toBe(ctfAllowance);
    // The executor still sees the CTF-Exchange allowance, not the CTF
    // (ConditionalTokens) one — the two spenders are kept distinct.
    expect(deps.ctfAllowance).not.toBe(allowance);
  });
});

describe("assertLiveCapabilities", () => {
  it("resolves when sidecar advertises TIF", async () => {
    mockGetCapabilities.mockResolvedValueOnce({ supportsTif: true });
    await expect(entry.assertLiveCapabilities()).resolves.toBeUndefined();
  });

  it("rejects when sidecar lacks TIF", async () => {
    mockGetCapabilities.mockResolvedValueOnce({ supportsTif: false });
    await expect(entry.assertLiveCapabilities()).rejects.toThrow(/GTC/);
  });
});

describe("buildLiveAllowanceClient", () => {
  it("returns undefined when wallet store has no wallet", async () => {
    const wallet = makeFakeWallet({ hasWallet: false });
    expect(await entry.buildLiveAllowanceClient(wallet)).toBeUndefined();
  });

  it("derives owner address from wallet.getAddress()", async () => {
    const wallet = makeFakeWallet({ address: "0xfromwallet" });
    const client = await entry.buildLiveAllowanceClient(wallet);
    expect(client).toBeDefined();
    expect(wallet.getAddress).toHaveBeenCalledTimes(1);
  });
});

// ---------------------------------------------------------------------------
// buildCtfAllowanceClient — ConditionalTokens spender mirrors
// buildLiveAllowanceClient with a distinct spender so `splitPosition` can
// pull USDC.e from the wallet.
// ---------------------------------------------------------------------------

describe("buildCtfAllowanceClient", () => {
  it("returns undefined when wallet store has no wallet", async () => {
    const wallet = makeFakeWallet({ hasWallet: false });
    expect(await entry.buildCtfAllowanceClient(wallet)).toBeUndefined();
    expect(wallet.getAddress).not.toHaveBeenCalled();
  });

  it("returns an AllowanceClient (getAllowance + approve) when wallet is present", async () => {
    const wallet = makeFakeWallet({ address: "0xfromwallet" });
    const client = (await entry.buildCtfAllowanceClient(wallet)) as
      | { getAllowance: unknown; approve: unknown }
      | undefined;
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
    expect(await entry.buildCtfAllowanceClient(wallet)).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// main — dry-run uses the scanner runner; --live invokes runMmPremiumCycle.
// ---------------------------------------------------------------------------

describe("main", () => {
  let originalStdoutWrite: typeof process.stdout.write;

  beforeEach(() => {
    originalStdoutWrite = process.stdout.write;
    // Silence the start banners during the assertion.
    process.stdout.write = vi.fn(
      () => true,
    ) as unknown as typeof process.stdout.write;
  });

  afterEach(() => {
    process.stdout.write = originalStdoutWrite;
  });

  it("invokes runner.start() and skips runMmPremiumCycle in dry-run mode", async () => {
    await expect(
      entry.main({ argv: ["node", "entry.js"] }),
    ).resolves.toBeUndefined();
    expect(mockRunnerStart).toHaveBeenCalledTimes(1);
    expect(mockRunMmPremiumCycle).not.toHaveBeenCalled();
  });

  it("invokes runMmPremiumCycle exactly once in --live mode and skips runner.start()", async () => {
    const wallet = makeFakeWallet({ address: "0xowner" });
    await entry.main({ argv: ["node", "entry.js", "--live"], wallet });
    expect(mockRunMmPremiumCycle).toHaveBeenCalledTimes(1);
    expect(mockRunnerStart).not.toHaveBeenCalled();
  });

  it("calls assertLiveCapabilities (sidecar check) before runMmPremiumCycle in --live", async () => {
    const wallet = makeFakeWallet({ address: "0xowner" });
    await entry.main({ argv: ["node", "entry.js", "--live"], wallet });
    expect(mockGetCapabilities).toHaveBeenCalledTimes(1);
    const capsOrder = mockGetCapabilities.mock.invocationCallOrder[0];
    const cycleOrder = mockRunMmPremiumCycle.mock.invocationCallOrder[0];
    expect(capsOrder).toBeDefined();
    expect(cycleOrder).toBeDefined();
    expect(capsOrder!).toBeLessThan(cycleOrder!);
  });

  it("does NOT call assertLiveCapabilities in dry-run", async () => {
    await entry.main({ argv: ["node", "entry.js"] });
    expect(mockGetCapabilities).not.toHaveBeenCalled();
  });

  it("passes a deps object containing config + scan + executor + mintClient to runMmPremiumCycle", async () => {
    const wallet = makeFakeWallet({ address: "0xowner" });
    await entry.main({ argv: ["node", "entry.js", "--live"], wallet });
    expect(mockRunMmPremiumCycle).toHaveBeenCalledTimes(1);
    const firstCall = mockRunMmPremiumCycle.mock.calls[0] as unknown as [
      Record<string, unknown>,
    ];
    const runDeps = firstCall[0];
    expect(runDeps).toBeDefined();
    expect(runDeps["config"]).toBeDefined();
    expect(runDeps["scan"]).toBeDefined();
    expect(runDeps["executor"]).toBeDefined();
    expect(runDeps["mintClient"]).toBeDefined();
    expect(typeof runDeps["fetchOrderStatus"]).toBe("function");
    expect(typeof runDeps["fetchMidpoint"]).toBe("function");
    expect(typeof runDeps["now"]).toBe("function");
    expect(typeof runDeps["sleep"]).toBe("function");
    expect(typeof runDeps["log"]).toBe("function");
  });
});
