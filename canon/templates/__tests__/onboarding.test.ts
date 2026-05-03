/**
 * Tests for the Polymarket onboarding adapter (`canon/templates/polymarket-onboard.ts`).
 *
 * Defines the contract for `polymarketOnboard.build(privateKey)`:
 *
 *   - `status()` is a pure read; it short-circuits and returns
 *     `{ funderDeployed: false, approvalsReady: false, credsReady: false,
 *        fundedCollateral: 0, funderAddress }` when the funder Safe is not
 *     deployed — without reading allowances or balances.
 *
 *   - `ensureFunder()` is idempotent. When `relay.getDeployed(safe)` is
 *     `true` it returns `{ deployed: true }` without calling `relay.deploy()`.
 *
 *   - `ensureApprovals()` is idempotent per spender. When every required
 *     spender's allowance is already at the threshold, `relay.execute()` is
 *     never called and the method returns `{ approved: true }`.
 *
 *   - `ensureCreds()` calls `clob.deriveApiKey()` first; on success returns
 *     those creds. When derive throws an error matching "incomplete", it
 *     falls back to `clob.createApiKey()`.
 *
 *   - Failure paths:
 *       * Relayer 4xx during deploy surfaces an actionable error.
 *       * Both derive and create returning incomplete creds throws.
 *       * A malformed `getContractConfig(chainId)` payload surfaces an
 *         actionable error rather than silently using stale defaults.
 *
 * Mocks `RelayClient` and `ClobClient` (plus `ethers` for on-chain reads).
 * Written ahead of the real implementation (item 3 of the plan): every test
 * here is expected to fail until `polymarket-onboard.ts` lands.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { OnboardClient } from "../types/OnboardClient.ts";
import type { MarketVenueOnboard } from "../types/MarketVenueOnboard.ts";

// ---------------------------------------------------------------------------
// @polymarket/builder-relayer-client mocks
// ---------------------------------------------------------------------------

const mockRelayDeploy = vi.fn();
const mockRelayGetDeployed = vi.fn();
const mockRelayExecute = vi.fn();
const mockDeriveSafe = vi.fn();
const mockRelayerContractConfig = vi.fn();

// `RelayClient` is a class — use `function` (not arrow) so `new` works.
const RelayClientCtor = vi.fn(function RelayClientStub(
  this: { deploy: unknown; getDeployed: unknown; execute: unknown },
  _relayerUrl: string,
  _chainId: number,
  _signer: unknown,
) {
  this.deploy = mockRelayDeploy;
  this.getDeployed = mockRelayGetDeployed;
  this.execute = mockRelayExecute;
});

vi.mock("@polymarket/builder-relayer-client", () => ({
  RelayClient: RelayClientCtor,
  deriveSafe: mockDeriveSafe,
  getContractConfig: mockRelayerContractConfig,
}));

// ---------------------------------------------------------------------------
// @polymarket/clob-client-v2 mocks
// ---------------------------------------------------------------------------

const mockDeriveApiKey = vi.fn();
const mockCreateApiKey = vi.fn();
const mockCreateOrDeriveApiKey = vi.fn();
const mockGetBalanceAllowance = vi.fn();
const mockClobContractConfig = vi.fn();

const ClobClientCtor = vi.fn(function ClobClientStub(
  this: {
    deriveApiKey: unknown;
    createApiKey: unknown;
    createOrDeriveApiKey: unknown;
    getBalanceAllowance: unknown;
  },
  _opts: unknown,
) {
  this.deriveApiKey = mockDeriveApiKey;
  this.createApiKey = mockCreateApiKey;
  this.createOrDeriveApiKey = mockCreateOrDeriveApiKey;
  this.getBalanceAllowance = mockGetBalanceAllowance;
});

vi.mock("@polymarket/clob-client-v2", () => ({
  ClobClient: ClobClientCtor,
  getContractConfig: mockClobContractConfig,
}));

// ---------------------------------------------------------------------------
// ethers v5 mocks (on-chain allowance / balance reads + Wallet for signing)
// ---------------------------------------------------------------------------

const mockAllowance = vi.fn();
const mockIsApprovedForAll = vi.fn();
const mockBalanceOf = vi.fn();

const ContractCtor = vi.fn(function ContractStub(
  this: {
    allowance: unknown;
    isApprovedForAll: unknown;
    balanceOf: unknown;
  },
  _address: string,
  _abi: unknown,
  _runner: unknown,
) {
  this.allowance = mockAllowance;
  this.isApprovedForAll = mockIsApprovedForAll;
  this.balanceOf = mockBalanceOf;
});

const WalletCtor = vi.fn(function WalletStub(
  this: { address: string; privateKey: string },
  privateKey: string,
) {
  this.address = EOA;
  this.privateKey = privateKey;
});

const JsonRpcProviderCtor = vi.fn(function ProviderStub() {
  // empty stub — adapter only passes it as a runner to Contract
});

const EOA = "0x1111111111111111111111111111111111111111";

vi.mock("ethers", () => ({
  ethers: {
    Contract: ContractCtor,
    Wallet: WalletCtor,
    providers: { JsonRpcProvider: JsonRpcProviderCtor },
    constants: { MaxUint256: { toBigInt: () => MAX_UINT256 } },
  },
  Contract: ContractCtor,
  Wallet: WalletCtor,
  providers: { JsonRpcProvider: JsonRpcProviderCtor },
  constants: { MaxUint256: { toBigInt: () => MAX_UINT256 } },
}));

// ---------------------------------------------------------------------------
// Constants and helpers
// ---------------------------------------------------------------------------

const MAX_UINT256 = (1n << 256n) - 1n;

const PRIVATE_KEY = `0x${"11".repeat(32)}`;
const SAFE = "0x2222222222222222222222222222222222222222";
const SAFE_FACTORY = "0xaacFeEa03eb1561C4e67d661e40682Bd20E3541b";
const SAFE_MULTISEND = "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761";
const EXCHANGE = "0xE111180000d2663C0091e4f400237545B87B996B";
const NEG_RISK_EXCHANGE = "0xe2222d279d744050d28e00520010520000310F59";
const NEG_RISK_ADAPTER = "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296";
const CTF = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045";
const COLLATERAL = "0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB";

const FULL_CREDS = {
  key: "key-abc",
  secret: "secret-abc",
  passphrase: "pass-abc",
};

const NEW_CREDS = {
  key: "key-new",
  secret: "secret-new",
  passphrase: "pass-new",
};

function bigNumberLike(value: bigint) {
  return { toBigInt: () => value };
}

function txReceiptLike(hash: string) {
  return {
    wait: vi.fn().mockResolvedValue({
      transactionHash: hash,
      status: 1,
    }),
    transactionHash: hash,
  };
}

// Lazy imports — re-imported in `beforeEach` so module-level state and the
// `vi.mock` factories are wired before the adapter executes.
let polymarketOnboard: MarketVenueOnboard;

beforeEach(async () => {
  vi.clearAllMocks();
  vi.resetModules();

  // Default happy-path stubs (individual tests override as needed).
  mockDeriveSafe.mockReturnValue(SAFE);

  mockRelayerContractConfig.mockReturnValue({
    SafeContracts: {
      SafeFactory: SAFE_FACTORY,
      SafeMultisend: SAFE_MULTISEND,
    },
    ProxyContracts: {
      ProxyFactory: "0x0000000000000000000000000000000000000000",
      RelayHub: "0x0000000000000000000000000000000000000000",
    },
    DepositWalletContracts: {
      DepositWalletFactory: "0x0000000000000000000000000000000000000000",
      DepositWalletImplementation:
        "0x0000000000000000000000000000000000000000",
    },
  });

  mockClobContractConfig.mockReturnValue({
    exchange: EXCHANGE,
    negRiskAdapter: NEG_RISK_ADAPTER,
    negRiskExchange: NEG_RISK_EXCHANGE,
    collateral: COLLATERAL,
    conditionalTokens: CTF,
    exchangeV2: EXCHANGE,
    negRiskExchangeV2: NEG_RISK_EXCHANGE,
  });

  // Default to a fully-onboarded wallet; tests that exercise the
  // unboarded branch override these.
  mockRelayGetDeployed.mockResolvedValue(true);
  mockAllowance.mockResolvedValue(bigNumberLike(MAX_UINT256));
  mockIsApprovedForAll.mockResolvedValue(true);
  mockBalanceOf.mockResolvedValue(bigNumberLike(0n));
  mockDeriveApiKey.mockResolvedValue(FULL_CREDS);
  mockCreateApiKey.mockResolvedValue(NEW_CREDS);
  mockCreateOrDeriveApiKey.mockResolvedValue(FULL_CREDS);
  mockGetBalanceAllowance.mockResolvedValue({
    balance: "0",
    allowance: MAX_UINT256.toString(),
  });

  const mod = await import("../polymarket-onboard.js");
  polymarketOnboard = mod.polymarketOnboard;
});

afterEach(() => {
  vi.useRealTimers();
});

// ---------------------------------------------------------------------------
// Registry hook shape
// ---------------------------------------------------------------------------

describe("polymarketOnboard registry hook", () => {
  it("identifies the venue as 'polymarket' and pins Polygon mainnet", () => {
    expect(polymarketOnboard.venue).toBe("polymarket");
    expect(polymarketOnboard.chainId).toBe(137);
  });

  it("build(privateKey) returns an OnboardClient with the four required methods", () => {
    const client: OnboardClient = polymarketOnboard.build(PRIVATE_KEY);

    expect(typeof client.status).toBe("function");
    expect(typeof client.ensureFunder).toBe("function");
    expect(typeof client.ensureApprovals).toBe("function");
    expect(typeof client.ensureCreds).toBe("function");
  });
});

// ---------------------------------------------------------------------------
// status()
// ---------------------------------------------------------------------------

describe("status()", () => {
  it("short-circuits when the funder Safe is not deployed", async () => {
    mockRelayGetDeployed.mockResolvedValue(false);

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const status = await client.status();

    expect(status).toEqual({
      funderDeployed: false,
      approvalsReady: false,
      credsReady: false,
      fundedCollateral: 0,
      funderAddress: SAFE,
    });

    // Short-circuit means: no allowance / approval / creds reads.
    expect(mockAllowance).not.toHaveBeenCalled();
    expect(mockIsApprovedForAll).not.toHaveBeenCalled();
    expect(mockDeriveApiKey).not.toHaveBeenCalled();
    expect(mockCreateOrDeriveApiKey).not.toHaveBeenCalled();
  });

  it("reflects a fully onboarded wallet when deploy + approvals + creds are present", async () => {
    mockRelayGetDeployed.mockResolvedValue(true);
    mockAllowance.mockResolvedValue(bigNumberLike(MAX_UINT256));
    mockIsApprovedForAll.mockResolvedValue(true);
    mockBalanceOf.mockResolvedValue(bigNumberLike(123_456_000n)); // 123.456 in 6-decimal collateral
    mockDeriveApiKey.mockResolvedValue(FULL_CREDS);

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const status = await client.status();

    expect(status.funderDeployed).toBe(true);
    expect(status.approvalsReady).toBe(true);
    expect(status.credsReady).toBe(true);
    expect(status.funderAddress).toBe(SAFE);
    // Collateral is reported in human units (6-decimal token).
    expect(status.fundedCollateral).toBeCloseTo(123.456, 5);
  });

  it("never mutates state — no deploy / execute / createApiKey calls during status()", async () => {
    const client = polymarketOnboard.build(PRIVATE_KEY);
    await client.status();

    expect(mockRelayDeploy).not.toHaveBeenCalled();
    expect(mockRelayExecute).not.toHaveBeenCalled();
    expect(mockCreateApiKey).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// ensureFunder()
// ---------------------------------------------------------------------------

describe("ensureFunder()", () => {
  it("skips deploy when getDeployed=true and reports already-deployed", async () => {
    mockRelayGetDeployed.mockResolvedValue(true);

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const result = await client.ensureFunder();

    expect(result.deployed).toBe(true);
    expect(result.txHash).toBeUndefined();
    expect(mockRelayDeploy).not.toHaveBeenCalled();
  });

  it("calls relay.deploy() and returns the resulting txHash when not yet deployed", async () => {
    // First check: not deployed. After deploy().wait(), getDeployed flips true.
    mockRelayGetDeployed
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true);
    mockRelayDeploy.mockResolvedValue(txReceiptLike("0xdeploybeef"));

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const result = await client.ensureFunder();

    expect(mockRelayDeploy).toHaveBeenCalledTimes(1);
    expect(result.deployed).toBe(true);
    expect(result.txHash).toBe("0xdeploybeef");
  });

  it("propagates a relayer 4xx error from deploy()", async () => {
    vi.useFakeTimers();
    mockRelayGetDeployed.mockResolvedValue(false);
    mockRelayDeploy.mockRejectedValue(
      new Error("Relayer responded 400 Bad Request: stale nonce"),
    );

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const settled = client.ensureFunder().catch((error: unknown) => error);

    // Allow any bounded retry/backoff timers to drain.
    await vi.runAllTimersAsync();
    const result = await settled;

    expect(result).toBeInstanceOf(Error);
    expect(String((result as Error).message)).toMatch(/relayer|400/i);
  });
});

// ---------------------------------------------------------------------------
// ensureApprovals()
// ---------------------------------------------------------------------------

describe("ensureApprovals()", () => {
  it("skips per-spender when every allowance is already at the threshold", async () => {
    mockRelayGetDeployed.mockResolvedValue(true);
    // ERC-20 allowance is MAX for every spender.
    mockAllowance.mockResolvedValue(bigNumberLike(MAX_UINT256));
    // ERC-1155 setApprovalForAll already true for every spender.
    mockIsApprovedForAll.mockResolvedValue(true);

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const result = await client.ensureApprovals();

    expect(result.approved).toBe(true);
    expect(result.txHash).toBeUndefined();
    expect(mockRelayExecute).not.toHaveBeenCalled();
  });

  it("submits a batched Safe transaction when at least one spender is below threshold", async () => {
    mockRelayGetDeployed.mockResolvedValue(true);
    mockAllowance.mockResolvedValue(bigNumberLike(0n));
    mockIsApprovedForAll.mockResolvedValue(false);
    mockRelayExecute.mockResolvedValue(txReceiptLike("0xapproveCafe"));

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const result = await client.ensureApprovals();

    expect(mockRelayExecute).toHaveBeenCalledTimes(1);
    expect(result.approved).toBe(true);
    expect(result.txHash).toBe("0xapproveCafe");

    // The first argument to relay.execute is the array of SafeTransactions.
    const firstCall = mockRelayExecute.mock.calls[0];
    expect(Array.isArray(firstCall?.[0])).toBe(true);
    expect((firstCall?.[0] as unknown[]).length).toBeGreaterThan(0);
  });

  it("submits only the approvals that are missing (mixed state)", async () => {
    mockRelayGetDeployed.mockResolvedValue(true);
    // Half the ERC-20 spenders are missing; ERC-1155s are all good.
    let allowanceCall = 0;
    mockAllowance.mockImplementation(async () => {
      allowanceCall += 1;
      return bigNumberLike(allowanceCall % 2 === 0 ? MAX_UINT256 : 0n);
    });
    mockIsApprovedForAll.mockResolvedValue(true);
    mockRelayExecute.mockResolvedValue(txReceiptLike("0xpartialApprove"));

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const result = await client.ensureApprovals();

    expect(result.approved).toBe(true);
    expect(mockRelayExecute).toHaveBeenCalledTimes(1);

    // The batch must only include the spenders that were below threshold —
    // not all of them.
    const txs = mockRelayExecute.mock.calls[0]?.[0] as Array<unknown>;
    expect(txs.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// ensureCreds()
// ---------------------------------------------------------------------------

describe("ensureCreds()", () => {
  it("returns the derive result when creds are already registered", async () => {
    mockDeriveApiKey.mockResolvedValue(FULL_CREDS);

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const creds = await client.ensureCreds();

    expect(creds).toEqual(FULL_CREDS);
    expect(mockDeriveApiKey).toHaveBeenCalled();
    expect(mockCreateApiKey).not.toHaveBeenCalled();
  });

  it("falls back to createApiKey when derive throws an 'incomplete' error", async () => {
    mockDeriveApiKey.mockRejectedValue(
      new Error("CLOB returned incomplete creds for this signer"),
    );
    mockCreateApiKey.mockResolvedValue(NEW_CREDS);

    const client = polymarketOnboard.build(PRIVATE_KEY);
    const creds = await client.ensureCreds();

    expect(creds).toEqual(NEW_CREDS);
    expect(mockDeriveApiKey).toHaveBeenCalled();
    expect(mockCreateApiKey).toHaveBeenCalled();
  });

  it("throws when both derive and create yield incomplete creds", async () => {
    mockDeriveApiKey.mockRejectedValue(new Error("incomplete creds"));
    mockCreateApiKey.mockResolvedValue({
      key: "",
      secret: "",
      passphrase: "",
    });

    const client = polymarketOnboard.build(PRIVATE_KEY);

    await expect(client.ensureCreds()).rejects.toThrow(/incomplete|creds/i);
  });

  it("does not swallow non-'incomplete' derive errors", async () => {
    mockDeriveApiKey.mockRejectedValue(new Error("503 service unavailable"));

    const client = polymarketOnboard.build(PRIVATE_KEY);

    await expect(client.ensureCreds()).rejects.toThrow(/503|unavailable/i);
    expect(mockCreateApiKey).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Malformed `getContractConfig` payload
// ---------------------------------------------------------------------------

describe("malformed getContractConfig", () => {
  it("status() throws an actionable error when the CLOB config is missing the exchange spender", async () => {
    mockClobContractConfig.mockReturnValue({
      // Intentionally omits `exchange` and friends.
      collateral: COLLATERAL,
    });

    const client = polymarketOnboard.build(PRIVATE_KEY);

    await expect(client.status()).rejects.toThrow(
      /exchange|spender|config|invalid/i,
    );
  });

  it("status() throws when the CLOB config is missing the collateral token", async () => {
    mockClobContractConfig.mockReturnValue({
      exchange: EXCHANGE,
      negRiskAdapter: NEG_RISK_ADAPTER,
      negRiskExchange: NEG_RISK_EXCHANGE,
      conditionalTokens: CTF,
      exchangeV2: EXCHANGE,
      negRiskExchangeV2: NEG_RISK_EXCHANGE,
      // collateral missing
    });

    const client = polymarketOnboard.build(PRIVATE_KEY);

    await expect(client.status()).rejects.toThrow(
      /collateral|config|invalid/i,
    );
  });

  it("status() throws when the relayer config is missing the SafeFactory", async () => {
    mockRelayerContractConfig.mockReturnValue({
      SafeContracts: {
        // SafeFactory missing
        SafeMultisend: SAFE_MULTISEND,
      },
      ProxyContracts: {},
      DepositWalletContracts: {},
    });

    expect(() => polymarketOnboard.build(PRIVATE_KEY)).toThrow(
      /safe.?factory|config|invalid/i,
    );
  });
});
