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
}));

const mockClient = await import("canon-templates/client-polymarket.js");
const fetchOnChainBalances = vi.mocked(mockClient.fetchOnChainBalances);

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
});

afterEach(() => {
  process.stdout.write = originalStdoutWrite;
  process.stderr.write = originalStderrWrite;
  delete process.env["WALLET_PRIVATE_KEY"];
  vi.clearAllMocks();
});

const { run } = await import("../commands/balance.js");

describe("balance", () => {
  it("returns on-chain balances with USDC.e tradeable", async () => {
    fetchOnChainBalances.mockResolvedValueOnce([
      {
        currency: "USDC.e",
        address: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
        amount: 9.88,
        tradeable: true,
      },
      {
        currency: "POL",
        address: "native",
        amount: 21.5,
        tradeable: false,
        note: "for gas only",
      },
    ]);

    await run([]);

    expect(fetchOnChainBalances).toHaveBeenCalled();
    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: Array<{
        currency: string;
        address: string;
        amount: number;
        tradeable: boolean;
        note?: string;
      }>;
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toHaveLength(2);
    expect(parsed.data[0]?.currency).toBe("USDC.e");
    expect(parsed.data[0]?.tradeable).toBe(true);
    expect(parsed.data[1]?.currency).toBe("POL");
    expect(parsed.data[1]?.tradeable).toBe(false);
  });

  it("includes native USDC with swap hint when present", async () => {
    fetchOnChainBalances.mockResolvedValueOnce([
      {
        currency: "USDC.e",
        address: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
        amount: 0,
        tradeable: true,
      },
      {
        currency: "USDC",
        address: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
        amount: 5.0,
        tradeable: false,
        note: "native USDC — swap to USDC.e to trade on Polymarket",
      },
      {
        currency: "POL",
        address: "native",
        amount: 1.0,
        tradeable: false,
        note: "for gas only",
      },
    ]);

    await run([]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: Array<{ currency: string; tradeable: boolean; note?: string }>;
    };
    expect(parsed.data).toHaveLength(3);
    const native = parsed.data.find((b) => b.currency === "USDC");
    expect(native?.tradeable).toBe(false);
    expect(native?.note).toContain("swap");
  });

  it("requires auth", async () => {
    delete process.env["WALLET_PRIVATE_KEY"];

    await run([]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/requires authentication/);
    expect(fetchOnChainBalances).not.toHaveBeenCalled();
  });

  it("handles RPC errors", async () => {
    fetchOnChainBalances.mockRejectedValueOnce(new Error("RPC unreachable"));

    await run([]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("RPC unreachable");
  });

  it("supports --pretty flag", async () => {
    fetchOnChainBalances.mockResolvedValueOnce([
      {
        currency: "USDC.e",
        address: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
        amount: 100,
        tradeable: true,
      },
    ]);

    await run(["--pretty"]);

    expect(stdoutData).toContain("\n");
    const parsed = JSON.parse(stdoutData) as { ok: boolean };
    expect(parsed.ok).toBe(true);
  });
});
