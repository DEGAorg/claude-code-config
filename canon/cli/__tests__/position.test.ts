import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

vi.mock("canon-templates/client-polymarket.js", () => ({
  fetchPositions: vi.fn(),
}));

vi.mock("canon-templates/position-manager.js", () => ({
  aggregatePortfolio: vi.fn(),
}));

const mockClient = await import("canon-templates/client-polymarket.js");
const fetchPositions = vi.mocked(mockClient.fetchPositions);

const mockPosManager = await import("canon-templates/position-manager.js");
const aggregatePortfolio = vi.mocked(mockPosManager.aggregatePortfolio);

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
  process.env["WALLET_PRIVATE_KEY"] = "0xtest";
});

afterEach(() => {
  process.stdout.write = originalStdoutWrite;
  process.stderr.write = originalStderrWrite;
  delete process.env["WALLET_PRIVATE_KEY"];
  vi.clearAllMocks();
});

const { run } = await import("../commands/position.js");

describe("position list", () => {
  const mockPositions = [
    {
      marketId: "mkt-1",
      outcomeId: "tok-yes",
      outcomeLabel: "Yes",
      size: 100,
      entryPrice: 0.5,
      currentPrice: 0.65,
      unrealizedPnL: 15,
    },
    {
      marketId: "mkt-2",
      outcomeId: "tok-no",
      outcomeLabel: "No",
      size: 50,
      entryPrice: 0.3,
      currentPrice: 0.25,
      unrealizedPnL: -2.5,
    },
  ];

  const mockPortfolio = {
    total_value: 150,
    positions: [
      {
        market_id: "mkt-1",
        direction: "buy_yes" as const,
        size: 100,
        entry_price: 0.5,
        opened_at: new Date("2026-01-01"),
      },
      {
        market_id: "mkt-2",
        direction: "buy_no" as const,
        size: 50,
        entry_price: 0.3,
        opened_at: new Date("2026-01-01"),
      },
    ],
    daily_pnl: 12.5,
  };

  it("returns positions with portfolio summary", async () => {
    fetchPositions.mockResolvedValueOnce(mockPositions);
    aggregatePortfolio.mockReturnValueOnce(mockPortfolio);

    await run(["list"]);

    expect(fetchPositions).toHaveBeenCalled();
    expect(aggregatePortfolio).toHaveBeenCalledWith(mockPositions);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: {
        positions: unknown[];
        summary: {
          totalValue: number;
          dailyPnL: number;
          positionCount: number;
        };
      };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.positions).toHaveLength(2);
    expect(parsed.data.positions[0]).toEqual(
      expect.objectContaining({
        marketId: "mkt-1",
        unrealizedPnL: 15,
      }),
    );
    expect(parsed.data.summary).toEqual({
      totalValue: 150,
      dailyPnL: 12.5,
      positionCount: 2,
    });
  });

  it("returns empty list when no positions", async () => {
    fetchPositions.mockResolvedValueOnce([]);
    aggregatePortfolio.mockReturnValueOnce({
      total_value: 0,
      positions: [],
      daily_pnl: 0,
    });

    await run(["list"]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: {
        positions: unknown[];
        summary: {
          totalValue: number;
          dailyPnL: number;
          positionCount: number;
        };
      };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.positions).toHaveLength(0);
    expect(parsed.data.summary.positionCount).toBe(0);
    expect(parsed.data.summary.totalValue).toBe(0);
  });

  it("requires auth", async () => {
    delete process.env["WALLET_PRIVATE_KEY"];

    await run(["list"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/requires authentication/);
    expect(fetchPositions).not.toHaveBeenCalled();
  });

  it("handles API errors", async () => {
    fetchPositions.mockRejectedValueOnce(new Error("API timeout"));

    await run(["list"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("API timeout");
  });

  it("supports --pretty flag", async () => {
    fetchPositions.mockResolvedValueOnce(mockPositions);
    aggregatePortfolio.mockReturnValueOnce(mockPortfolio);

    await run(["list", "--pretty"]);

    expect(stdoutData).toContain("\n");
    const parsed = JSON.parse(stdoutData) as { ok: boolean };
    expect(parsed.ok).toBe(true);
  });
});

describe("position — unknown subcommand", () => {
  it("errors on unknown subcommand", async () => {
    await run(["unknown"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Unknown position subcommand/);
  });

  it("errors when no subcommand provided", async () => {
    await run([]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Unknown position subcommand/);
  });
});
