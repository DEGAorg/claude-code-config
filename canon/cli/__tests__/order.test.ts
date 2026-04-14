import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

vi.mock("canon-templates/client-polymarket.js", () => ({
  createOrder: vi.fn(),
  cancelOrder: vi.fn(),
  fetchMyTrades: vi.fn(),
}));

const mockClient = await import("canon-templates/client-polymarket.js");
const createOrder = vi.mocked(mockClient.createOrder);
const cancelOrder = vi.mocked(mockClient.cancelOrder);
const fetchMyTrades = vi.mocked(mockClient.fetchMyTrades);

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

// Dynamic import after mocks are set up
const { run } = await import("../commands/order.js");

describe("order create", () => {
  it("creates an order with valid params", async () => {
    createOrder.mockResolvedValueOnce({
      id: "ord-1",
      marketId: "mkt-1",
      outcomeId: "tok-yes",
      side: "buy",
      type: "limit",
      amount: 10,
      price: 0.65,
      status: "open",
      filled: 0,
      remaining: 10,
    });

    await run([
      "create",
      "--token-id", "tok-yes",
      "--side", "buy",
      "--size", "10",
      "--price", "0.65",
      "--market-id", "mkt-1",
    ]);

    expect(createOrder).toHaveBeenCalledWith({
      marketId: "mkt-1",
      tokenId: "tok-yes",
      side: "buy",
      size: 10,
      price: 0.65,
      orderType: "limit",
    });

    const parsed = JSON.parse(stdoutData) as { ok: boolean; data: unknown };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toEqual(
      expect.objectContaining({ id: "ord-1", status: "open" }),
    );
  });

  it("defaults to limit order type", async () => {
    createOrder.mockResolvedValueOnce({
      id: "ord-2",
      marketId: "",
      outcomeId: "tok-1",
      side: "buy",
      type: "limit",
      amount: 5,
      price: 0.5,
      status: "open",
      filled: 0,
      remaining: 5,
    });

    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "5",
      "--price", "0.5",
    ]);

    expect(createOrder).toHaveBeenCalledWith(
      expect.objectContaining({ orderType: "limit" }),
    );
  });

  it("accepts market order type", async () => {
    createOrder.mockResolvedValueOnce({
      id: "ord-3",
      marketId: "",
      outcomeId: "tok-1",
      side: "sell",
      type: "market",
      amount: 3,
      price: 0.4,
      status: "open",
      filled: 0,
      remaining: 3,
    });

    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "sell",
      "--size", "3",
      "--price", "0.4",
      "--type", "market",
    ]);

    expect(createOrder).toHaveBeenCalledWith(
      expect.objectContaining({ orderType: "market" }),
    );
  });

  it("errors on missing required flags", async () => {
    await run(["create", "--token-id", "tok-1"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Missing required flags/);
    expect(createOrder).not.toHaveBeenCalled();
  });

  it("errors on invalid side", async () => {
    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "hold",
      "--size", "5",
      "--price", "0.5",
    ]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Invalid --side/);
  });

  it("errors on invalid order type", async () => {
    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "5",
      "--price", "0.5",
      "--type", "stop",
    ]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Invalid --type/);
  });

  it("errors on invalid size", async () => {
    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "-1",
      "--price", "0.5",
    ]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Invalid --size/);
  });

  it("errors on invalid price (too high)", async () => {
    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "5",
      "--price", "1.5",
    ]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Invalid --price/);
  });

  it("errors on non-numeric price", async () => {
    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "5",
      "--price", "abc",
    ]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Invalid --price/);
  });

  it("requires auth", async () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];

    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "5",
      "--price", "0.5",
    ]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/requires authentication/);
    expect(createOrder).not.toHaveBeenCalled();
  });

  it("handles API errors", async () => {
    createOrder.mockRejectedValueOnce(new Error("API rate limit"));

    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "5",
      "--price", "0.5",
    ]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("API rate limit");
  });

  it("supports --pretty flag", async () => {
    createOrder.mockResolvedValueOnce({
      id: "ord-p",
      marketId: "",
      outcomeId: "tok-1",
      side: "buy",
      type: "limit",
      amount: 5,
      price: 0.5,
      status: "open",
      filled: 0,
      remaining: 5,
    });

    await run([
      "create",
      "--token-id", "tok-1",
      "--side", "buy",
      "--size", "5",
      "--price", "0.5",
      "--pretty",
    ]);

    expect(stdoutData).toContain("\n");
    const parsed = JSON.parse(stdoutData) as { ok: boolean };
    expect(parsed.ok).toBe(true);
  });
});

describe("order cancel", () => {
  it("cancels an order by ID", async () => {
    cancelOrder.mockResolvedValueOnce({
      id: "ord-1",
      marketId: "mkt-1",
      outcomeId: "tok-1",
      side: "buy",
      type: "limit",
      amount: 10,
      price: 0.65,
      status: "cancelled",
      filled: 3,
      remaining: 7,
    });

    await run(["cancel", "ord-1"]);

    expect(cancelOrder).toHaveBeenCalledWith("ord-1");
    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: { status: string };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.status).toBe("cancelled");
  });

  it("errors when no order ID provided", async () => {
    await run(["cancel"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Missing order ID/);
    expect(cancelOrder).not.toHaveBeenCalled();
  });

  it("requires auth", async () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];

    await run(["cancel", "ord-1"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/requires authentication/);
    expect(cancelOrder).not.toHaveBeenCalled();
  });

  it("handles API errors", async () => {
    cancelOrder.mockRejectedValueOnce(new Error("Order not found"));

    await run(["cancel", "ord-999"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("Order not found");
  });
});

describe("order list", () => {
  it("lists trades", async () => {
    fetchMyTrades.mockResolvedValueOnce([
      {
        id: "t-1",
        price: 0.65,
        amount: 10,
        side: "buy",
        timestamp: 1700000000,
        orderId: "ord-1",
      },
      {
        id: "t-2",
        price: 0.4,
        amount: 5,
        side: "sell",
        timestamp: 1700001000,
      },
    ]);

    await run(["list"]);

    expect(fetchMyTrades).toHaveBeenCalledWith({});
    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: unknown[];
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toHaveLength(2);
  });

  it("passes --market-id filter", async () => {
    fetchMyTrades.mockResolvedValueOnce([]);

    await run(["list", "--market-id", "mkt-42"]);

    expect(fetchMyTrades).toHaveBeenCalledWith({ marketId: "mkt-42" });
  });

  it("passes --limit filter", async () => {
    fetchMyTrades.mockResolvedValueOnce([]);

    await run(["list", "--limit", "5"]);

    expect(fetchMyTrades).toHaveBeenCalledWith({ limit: 5 });
  });

  it("passes both filters", async () => {
    fetchMyTrades.mockResolvedValueOnce([]);

    await run(["list", "--market-id", "mkt-1", "--limit", "10"]);

    expect(fetchMyTrades).toHaveBeenCalledWith({
      marketId: "mkt-1",
      limit: 10,
    });
  });

  it("errors on invalid limit", async () => {
    await run(["list", "--limit", "abc"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Invalid --limit/);
    expect(fetchMyTrades).not.toHaveBeenCalled();
  });

  it("requires auth", async () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];

    await run(["list"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/requires authentication/);
    expect(fetchMyTrades).not.toHaveBeenCalled();
  });

  it("handles API errors", async () => {
    fetchMyTrades.mockRejectedValueOnce(new Error("Network error"));

    await run(["list"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("Network error");
  });
});

describe("order — unknown subcommand", () => {
  it("errors on unknown subcommand", async () => {
    await run(["unknown"]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Unknown order subcommand/);
  });

  it("errors when no subcommand provided", async () => {
    await run([]);

    const parsed = JSON.parse(stderrData) as { ok: boolean; error: string };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toMatch(/Unknown order subcommand/);
  });
});
