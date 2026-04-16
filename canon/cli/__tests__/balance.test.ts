import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

vi.mock("canon-templates/client-polymarket.js", () => ({
  fetchBalance: vi.fn(),
}));

const mockClient = await import("canon-templates/client-polymarket.js");
const fetchBalance = vi.mocked(mockClient.fetchBalance);

// Capture stdout/stderr writes
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
  process.env["POLYMARKET_PRIVATE_KEY"] = "0xtest";
});

afterEach(() => {
  process.stdout.write = originalStdoutWrite;
  process.stderr.write = originalStderrWrite;
  delete process.env["POLYMARKET_PRIVATE_KEY"];
  vi.clearAllMocks();
});

const { run } = await import("../commands/balance.js");

describe("balance", () => {
  it("returns wallet balances", async () => {
    fetchBalance.mockResolvedValueOnce([
      {
        currency: "USDC",
        total: 1000,
        available: 750,
        locked: 250,
      },
    ]);

    await run([]);

    expect(fetchBalance).toHaveBeenCalled();

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: Array<{
        currency: string;
        total: number;
        available: number;
        locked: number;
      }>;
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toHaveLength(1);
    expect(parsed.data[0]).toEqual({
      currency: "USDC",
      total: 1000,
      available: 750,
      locked: 250,
    });
  });

  it("returns multiple currencies", async () => {
    fetchBalance.mockResolvedValueOnce([
      {
        currency: "USDC",
        total: 500,
        available: 400,
        locked: 100,
      },
      {
        currency: "ETH",
        total: 2.5,
        available: 2.0,
        locked: 0.5,
      },
    ]);

    await run([]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: unknown[];
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toHaveLength(2);
  });

  it("returns empty array when no balances", async () => {
    fetchBalance.mockResolvedValueOnce([]);

    await run([]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: unknown[];
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toHaveLength(0);
  });

  it("requires auth", async () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];

    await run([]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/requires authentication/);
    expect(fetchBalance).not.toHaveBeenCalled();
  });

  it("handles API errors", async () => {
    fetchBalance.mockRejectedValueOnce(new Error("Wallet not found"));

    await run([]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("Wallet not found");
  });

  it("supports --pretty flag", async () => {
    fetchBalance.mockResolvedValueOnce([
      {
        currency: "USDC",
        total: 100,
        available: 80,
        locked: 20,
      },
    ]);

    await run(["--pretty"]);

    expect(stdoutData).toContain("\n");
    const parsed = JSON.parse(stdoutData) as { ok: boolean };
    expect(parsed.ok).toBe(true);
  });
});
