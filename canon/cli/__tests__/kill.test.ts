import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

const mockFetchOpenOrders = vi.hoisted(() => vi.fn());
const mockCancelAllOrders = vi.hoisted(() => vi.fn());

vi.mock("canon-templates/client-polymarket.js", () => ({
  fetchOpenOrders: mockFetchOpenOrders,
}));

vi.mock("canon-templates/kill-switch.js", () => ({
  cancelAllOrders: mockCancelAllOrders,
}));

const stdoutWrite = vi.hoisted(() => vi.fn());
const stderrWrite = vi.hoisted(() => vi.fn());

function makeOrder(id: string) {
  return {
    id,
    marketId: `market-${id}`,
    outcomeId: `outcome-${id}`,
    side: "buy" as const,
    type: "limit" as const,
    amount: 10,
    price: 0.5,
    status: "open",
    filled: 0,
    remaining: 10,
  };
}

describe("kill subcommand", () => {
  let originalKey: string | undefined;

  beforeEach(() => {
    originalKey = process.env["POLYMARKET_PRIVATE_KEY"];
    process.env["POLYMARKET_PRIVATE_KEY"] = "0xtest-key";
    mockFetchOpenOrders.mockReset();
    mockCancelAllOrders.mockReset();
    stdoutWrite.mockReset();
    stderrWrite.mockReset();
    vi.spyOn(process.stdout, "write").mockImplementation(stdoutWrite);
    vi.spyOn(process.stderr, "write").mockImplementation(stderrWrite);
    process.exitCode = undefined;
  });

  afterEach(() => {
    if (originalKey === undefined) {
      delete process.env["POLYMARKET_PRIVATE_KEY"];
    } else {
      process.env["POLYMARKET_PRIVATE_KEY"] = originalKey;
    }
    vi.restoreAllMocks();
  });

  async function runKill(args: string[]) {
    const mod = await import("../commands/kill.js");
    return mod.run(args);
  }

  function parseStdout(): unknown {
    const call = stdoutWrite.mock.calls[0];
    if (!call) throw new Error("No stdout output");
    return JSON.parse(String(call[0]));
  }

  function parseStderr(): unknown {
    const call = stderrWrite.mock.calls[0];
    if (!call) throw new Error("No stderr output");
    return JSON.parse(String(call[0]));
  }

  it("requires authentication", async () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];
    await runKill([]);

    const output = parseStderr() as { ok: boolean; error: string };
    expect(output.ok).toBe(false);
    expect(output.error).toMatch(/requires authentication/);
    expect(output.error).toMatch(/POLYMARKET_PRIVATE_KEY/);
    expect(mockFetchOpenOrders).not.toHaveBeenCalled();
  });

  it("returns success with empty result when no open orders", async () => {
    mockFetchOpenOrders.mockResolvedValueOnce([]);
    await runKill(["--yes"]);

    const output = parseStdout() as {
      ok: boolean;
      data: { cancelled: string[]; message: string };
    };
    expect(output.ok).toBe(true);
    expect(output.data.cancelled).toEqual([]);
    expect(output.data.message).toBe("No open orders");
  });

  it("performs dry run without --yes flag", async () => {
    const orders = [makeOrder("ord-1"), makeOrder("ord-2")];
    mockFetchOpenOrders.mockResolvedValueOnce(orders);
    await runKill([]);

    const output = parseStdout() as {
      ok: boolean;
      data: {
        dryRun: boolean;
        orderCount: number;
        orders: unknown[];
        message: string;
      };
    };
    expect(output.ok).toBe(true);
    expect(output.data.dryRun).toBe(true);
    expect(output.data.orderCount).toBe(2);
    expect(output.data.orders).toHaveLength(2);
    expect(output.data.message).toMatch(/Re-run with --yes/);
    expect(mockCancelAllOrders).not.toHaveBeenCalled();
  });

  it("cancels all orders with --yes flag", async () => {
    const orders = [makeOrder("ord-1"), makeOrder("ord-2")];
    mockFetchOpenOrders.mockResolvedValueOnce(orders);
    mockCancelAllOrders.mockResolvedValueOnce({
      cancelled: ["ord-1", "ord-2"],
      failed: [],
    });

    await runKill(["--yes"]);

    expect(mockCancelAllOrders).toHaveBeenCalledWith([
      "ord-1",
      "ord-2",
    ]);
    const output = parseStdout() as {
      ok: boolean;
      data: { cancelled: string[]; failed: string[] };
    };
    expect(output.ok).toBe(true);
    expect(output.data.cancelled).toEqual(["ord-1", "ord-2"]);
    expect(output.data.failed).toEqual([]);
  });

  it("cancels all orders with -y shorthand", async () => {
    const orders = [makeOrder("ord-1")];
    mockFetchOpenOrders.mockResolvedValueOnce(orders);
    mockCancelAllOrders.mockResolvedValueOnce({
      cancelled: ["ord-1"],
      failed: [],
    });

    await runKill(["-y"]);

    expect(mockCancelAllOrders).toHaveBeenCalledWith(["ord-1"]);
    const output = parseStdout() as {
      ok: boolean;
      data: { cancelled: string[] };
    };
    expect(output.ok).toBe(true);
    expect(output.data.cancelled).toEqual(["ord-1"]);
  });

  it("reports partial failures from cancelAllOrders", async () => {
    const orders = [makeOrder("ord-1"), makeOrder("ord-2")];
    mockFetchOpenOrders.mockResolvedValueOnce(orders);
    mockCancelAllOrders.mockResolvedValueOnce({
      cancelled: ["ord-1"],
      failed: ["ord-2"],
    });

    await runKill(["--yes"]);

    const output = parseStdout() as {
      ok: boolean;
      data: { cancelled: string[]; failed: string[] };
    };
    expect(output.ok).toBe(true);
    expect(output.data.cancelled).toEqual(["ord-1"]);
    expect(output.data.failed).toEqual(["ord-2"]);
  });

  it("handles API errors from fetchOpenOrders", async () => {
    mockFetchOpenOrders.mockRejectedValueOnce(
      new Error("Network timeout"),
    );
    await runKill(["--yes"]);

    const output = parseStderr() as { ok: boolean; error: string };
    expect(output.ok).toBe(false);
    expect(output.error).toBe("Network timeout");
  });

  it("handles API errors from cancelAllOrders", async () => {
    mockFetchOpenOrders.mockResolvedValueOnce([makeOrder("ord-1")]);
    mockCancelAllOrders.mockRejectedValueOnce(
      new Error("Exchange unavailable"),
    );

    await runKill(["--yes"]);

    const output = parseStderr() as { ok: boolean; error: string };
    expect(output.ok).toBe(false);
    expect(output.error).toBe("Exchange unavailable");
  });

  it("respects --pretty flag in dry run output", async () => {
    mockFetchOpenOrders.mockResolvedValueOnce([makeOrder("ord-1")]);
    await runKill(["--pretty"]);

    const raw = String(stdoutWrite.mock.calls[0]?.[0]);
    expect(raw).toContain("\n");
    const output = JSON.parse(raw) as {
      ok: boolean;
      data: { dryRun: boolean };
    };
    expect(output.ok).toBe(true);
    expect(output.data.dryRun).toBe(true);
  });

  it("respects --pretty flag in confirmed output", async () => {
    mockFetchOpenOrders.mockResolvedValueOnce([makeOrder("ord-1")]);
    mockCancelAllOrders.mockResolvedValueOnce({
      cancelled: ["ord-1"],
      failed: [],
    });

    await runKill(["--yes", "--pretty"]);

    const raw = String(stdoutWrite.mock.calls[0]?.[0]);
    expect(raw).toContain("\n");
    const output = JSON.parse(raw) as {
      ok: boolean;
      data: { cancelled: string[] };
    };
    expect(output.ok).toBe(true);
    expect(output.data.cancelled).toEqual(["ord-1"]);
  });

  it("includes command name in auth error", async () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];
    await runKill([]);

    const output = parseStderr() as { ok: boolean; error: string };
    expect(output.error).toMatch(/"kill"/);
  });
});
