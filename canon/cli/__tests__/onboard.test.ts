import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

vi.mock("canon-templates/client-polymarket.js", () => ({
  fetchOnChainBalances: vi.fn(),
  swapToUsdce: vi.fn(),
}));

const mockClient = await import("canon-templates/client-polymarket.js");
const fetchOnChainBalances = vi.mocked(mockClient.fetchOnChainBalances);
const swapToUsdce = vi.mocked(mockClient.swapToUsdce);

let stdoutData: string;
let stderrData: string;

const originalStdoutWrite = process.stdout.write.bind(process.stdout);
const originalStderrWrite = process.stderr.write.bind(process.stderr);

beforeEach(() => {
  stdoutData = "";
  stderrData = "";
  process.stdout.write = ((chunk: string) => {
    stdoutData += chunk;
    return true;
  }) as typeof process.stdout.write;
  process.stderr.write = ((chunk: string) => {
    stderrData += chunk;
    return true;
  }) as typeof process.stderr.write;
  process.exitCode = undefined;
  process.env["WALLET_PRIVATE_KEY"] = "0xtest";
  delete process.env["ONBOARD_POL_GAS_RESERVE"];
});

afterEach(() => {
  process.stdout.write = originalStdoutWrite;
  process.stderr.write = originalStderrWrite;
  delete process.env["WALLET_PRIVATE_KEY"];
  vi.clearAllMocks();
});

const { run } = await import("../commands/onboard.js");

describe("onboard", () => {
  describe("plan mode (no --execute)", () => {
    it("returns empty plan when only USDC.e + POL", async () => {
      fetchOnChainBalances.mockResolvedValueOnce([
        { currency: "USDC.e", address: "0x2791", amount: 10, tradeable: true },
        { currency: "POL", address: "native", amount: 1.5, tradeable: false },
      ]);

      await run([]);

      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: { plan: unknown[]; executed: boolean };
      };
      expect(parsed.ok).toBe(true);
      expect(parsed.data.plan).toHaveLength(0);
      expect(parsed.data.executed).toBe(false);
      expect(swapToUsdce).not.toHaveBeenCalled();
    });

    it("plans native USDC → USDC.e swap", async () => {
      fetchOnChainBalances.mockResolvedValueOnce([
        { currency: "USDC.e", address: "0x2791", amount: 0, tradeable: true },
        {
          currency: "USDC",
          address: "0x3c49",
          amount: 5,
          tradeable: false,
          note: "swap",
        },
        { currency: "POL", address: "native", amount: 1.5, tradeable: false },
      ]);

      await run([]);

      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: {
          plan: Array<{ from: string; amount: number; reason: string }>;
          executed: boolean;
        };
      };
      expect(parsed.data.executed).toBe(false);
      expect(parsed.data.plan).toHaveLength(1);
      expect(parsed.data.plan[0]?.from).toBe("USDC");
      expect(parsed.data.plan[0]?.amount).toBe(5);
      expect(swapToUsdce).not.toHaveBeenCalled();
    });

    it("plans USDT and POL-excess swaps", async () => {
      fetchOnChainBalances.mockResolvedValueOnce([
        { currency: "USDC.e", address: "0x2791", amount: 0, tradeable: true },
        {
          currency: "USDT",
          address: "0xc213",
          amount: 3,
          tradeable: false,
          note: "swap",
        },
        { currency: "POL", address: "native", amount: 20, tradeable: false },
      ]);

      await run([]);

      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: { plan: Array<{ from: string; amount: number }> };
      };
      expect(parsed.data.plan).toHaveLength(2);
      const usdt = parsed.data.plan.find((s) => s.from === "USDT");
      const pol = parsed.data.plan.find((s) => s.from === "POL");
      expect(usdt?.amount).toBe(3);
      expect(pol?.amount).toBe(19); // 20 - 1 (default reserve)
    });

    it("respects ONBOARD_POL_GAS_RESERVE env var", async () => {
      process.env["ONBOARD_POL_GAS_RESERVE"] = "10";
      fetchOnChainBalances.mockResolvedValueOnce([
        { currency: "USDC.e", address: "0x2791", amount: 0, tradeable: true },
        { currency: "POL", address: "native", amount: 20, tradeable: false },
      ]);

      await run([]);

      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: { plan: Array<{ from: string; amount: number }> };
      };
      expect(parsed.data.plan).toHaveLength(1);
      expect(parsed.data.plan[0]?.amount).toBe(10); // 20 - 10
    });

    it("skips POL swap when excess < 1", async () => {
      fetchOnChainBalances.mockResolvedValueOnce([
        { currency: "USDC.e", address: "0x2791", amount: 0, tradeable: true },
        { currency: "POL", address: "native", amount: 1.5, tradeable: false },
      ]);

      await run([]);

      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: { plan: unknown[] };
      };
      expect(parsed.data.plan).toHaveLength(0);
    });
  });

  describe("execute mode", () => {
    it("calls swapToUsdce for each planned step", async () => {
      fetchOnChainBalances.mockResolvedValueOnce([
        { currency: "USDC.e", address: "0x2791", amount: 0, tradeable: true },
        {
          currency: "USDC",
          address: "0x3c49",
          amount: 5,
          tradeable: false,
          note: "swap",
        },
        { currency: "POL", address: "native", amount: 1.5, tradeable: false },
      ]);
      swapToUsdce.mockResolvedValueOnce({
        from: "USDC",
        amountIn: 5,
        amountOut: 4.99,
        txHash: "0xabc",
      });

      await run(["--execute"]);

      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: { executed: boolean; swaps: Array<{ from: string }> };
      };
      expect(parsed.data.executed).toBe(true);
      expect(parsed.data.swaps).toHaveLength(1);
      expect(parsed.data.swaps[0]?.from).toBe("USDC");
      expect(swapToUsdce).toHaveBeenCalledWith("USDC", 5);
    });
  });

  describe("single-asset mode", () => {
    it("rejects missing --amount when --asset given", async () => {
      await run(["--asset", "USDC"]);
      const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toMatch(/asset.*amount/i);
    });

    it("rejects invalid --asset", async () => {
      await run(["--asset", "ETH", "--amount", "1"]);
      const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toMatch(/Invalid --asset/);
    });

    it("rejects non-positive --amount", async () => {
      await run(["--asset", "USDC", "--amount", "-1"]);
      const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toMatch(/Invalid --amount/);
    });

    it("plans single swap without --execute", async () => {
      await run(["--asset", "USDT", "--amount", "2.5"]);
      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: { plan: Array<{ from: string; amount: number }> };
      };
      expect(parsed.data.plan[0]?.from).toBe("USDT");
      expect(parsed.data.plan[0]?.amount).toBe(2.5);
      expect(swapToUsdce).not.toHaveBeenCalled();
    });

    it("executes single swap with --execute", async () => {
      swapToUsdce.mockResolvedValueOnce({
        from: "USDT",
        amountIn: 2.5,
        amountOut: 2.49,
        txHash: "0xdef",
      });
      await run(["--asset", "USDT", "--amount", "2.5", "--execute"]);
      expect(swapToUsdce).toHaveBeenCalledWith("USDT", 2.5);
      const parsed = JSON.parse(stdoutData) as {
        ok: boolean;
        data: { executed: boolean };
      };
      expect(parsed.data.executed).toBe(true);
    });
  });

  it("requires auth", async () => {
    delete process.env["WALLET_PRIVATE_KEY"];
    await run([]);
    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/requires authentication/);
    expect(fetchOnChainBalances).not.toHaveBeenCalled();
  });

  it("propagates swap errors", async () => {
    fetchOnChainBalances.mockResolvedValueOnce([
      { currency: "USDC.e", address: "0x2791", amount: 0, tradeable: true },
      {
        currency: "USDC",
        address: "0x3c49",
        amount: 5,
        tradeable: false,
        note: "swap",
      },
    ]);
    swapToUsdce.mockRejectedValueOnce(new Error("insufficient gas"));
    await run(["--execute"]);
    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("insufficient gas");
  });
});
