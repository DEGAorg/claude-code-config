import { describe, it, expect, vi, beforeEach } from "vitest";
import type {
  fetchMarketPrice as FetchMarketPriceFn,
  searchMarkets as SearchMarketsFn,
  fetchOrderBook as FetchOrderBookFn,
} from "../client-polymarket.js";

const mockFetchMarkets = vi.fn();
const mockFetchOrderBook = vi.fn();

vi.mock("pmxtjs", () => {
  class MockPolymarket {
    fetchMarkets = mockFetchMarkets;
    fetchOrderBook = mockFetchOrderBook;
  }
  return { Polymarket: MockPolymarket };
});

let fetchMarketPrice: typeof FetchMarketPriceFn;
let searchMarkets: typeof SearchMarketsFn;
let fetchOrderBook: typeof FetchOrderBookFn;

beforeEach(async () => {
  vi.clearAllMocks();
  // Reset the module so the cached singleton is cleared each test
  vi.resetModules();
  const mod = await import("../client-polymarket.js");
  fetchMarketPrice = mod.fetchMarketPrice;
  searchMarkets = mod.searchMarkets;
  fetchOrderBook = mod.fetchOrderBook;
});

// ---------------------------------------------------------------------------
// fetchMarketPrice
// ---------------------------------------------------------------------------
describe("fetchMarketPrice", () => {
  it("returns a MarketPrice for a valid binary market", async () => {
    mockFetchMarkets.mockResolvedValueOnce([
      {
        marketId: "cond-abc",
        outcomes: [{ price: 0.65 }, { price: 0.35 }],
      },
    ]);

    const result = await fetchMarketPrice("some-slug");

    expect(result.conditionId).toBe("cond-abc");
    expect(result.yes).toBe(0.65);
    expect(result.no).toBe(0.35);
    expect(result.timestamp).toBeInstanceOf(Date);
    expect(mockFetchMarkets).toHaveBeenCalledWith({ query: "some-slug" });
  });

  it("throws when market is not found (empty array)", async () => {
    mockFetchMarkets.mockResolvedValueOnce([]);

    await expect(fetchMarketPrice("missing")).rejects.toThrow(
      "Market missing not found",
    );
  });

  it("throws when market has non-binary outcomes", async () => {
    mockFetchMarkets.mockResolvedValueOnce([
      {
        marketId: "cond-xyz",
        outcomes: [{ price: 0.3 }, { price: 0.3 }, { price: 0.4 }],
      },
    ]);

    await expect(fetchMarketPrice("cond-xyz")).rejects.toThrow(
      "not a binary market",
    );
  });

  it("throws when outcome prices are missing", async () => {
    mockFetchMarkets.mockResolvedValueOnce([
      {
        marketId: "cond-bad",
        outcomes: [{}, {}],
      },
    ]);

    await expect(fetchMarketPrice("cond-bad")).rejects.toThrow(
      "missing outcome prices",
    );
  });
});

// ---------------------------------------------------------------------------
// searchMarkets
// ---------------------------------------------------------------------------
describe("searchMarkets", () => {
  it("returns matching binary markets with prices", async () => {
    mockFetchMarkets.mockResolvedValueOnce([
      {
        marketId: "m-1",
        title: "Will the Lakers win?",
        outcomes: [{ price: 0.55 }, { price: 0.45 }],
        resolutionDate: new Date("2026-06-01"),
      },
      {
        marketId: "m-2",
        title: "Will the Celtics win?",
        outcomes: [{ price: 0.7 }, { price: 0.3 }],
        resolutionDate: new Date("2026-06-15"),
      },
    ]);

    const results = await searchMarkets("NBA");

    expect(results).toHaveLength(2);
    expect(results[0]).toEqual({
      conditionId: "m-1",
      question: "Will the Lakers win?",
      yesPrice: 0.55,
      noPrice: 0.45,
      resolutionDate: "2026-06-01T00:00:00.000Z",
    });
    expect(results[1]?.conditionId).toBe("m-2");
    expect(results[1]?.resolutionDate).toBe("2026-06-15T00:00:00.000Z");
    expect(mockFetchMarkets).toHaveBeenCalledWith({ query: "NBA" });
  });

  it("filters out non-binary markets", async () => {
    mockFetchMarkets.mockResolvedValueOnce([
      {
        marketId: "m-bin",
        title: "Binary",
        outcomes: [{ price: 0.6 }, { price: 0.4 }],
      },
      {
        marketId: "m-tri",
        title: "Ternary",
        outcomes: [{ price: 0.3 }, { price: 0.3 }, { price: 0.4 }],
      },
    ]);

    const results = await searchMarkets("test");

    expect(results).toHaveLength(1);
    expect(results[0]?.conditionId).toBe("m-bin");
  });

  it("filters out markets with missing prices", async () => {
    mockFetchMarkets.mockResolvedValueOnce([
      {
        marketId: "m-ok",
        title: "Has prices",
        outcomes: [{ price: 0.5 }, { price: 0.5 }],
      },
      {
        marketId: "m-no-price",
        title: "Missing price",
        outcomes: [{}, { price: 0.5 }],
      },
    ]);

    const results = await searchMarkets("test");

    expect(results).toHaveLength(1);
    expect(results[0]?.conditionId).toBe("m-ok");
  });

  it("returns empty array when no markets match", async () => {
    mockFetchMarkets.mockResolvedValueOnce([]);

    const results = await searchMarkets("nonexistent");

    expect(results).toEqual([]);
  });

  it("omits resolutionDate when not provided", async () => {
    mockFetchMarkets.mockResolvedValueOnce([
      {
        marketId: "m-no-date",
        title: "No date",
        outcomes: [{ price: 0.5 }, { price: 0.5 }],
      },
    ]);

    const results = await searchMarkets("test");

    expect(results).toHaveLength(1);
    expect(results[0]).not.toHaveProperty("resolutionDate");
  });
});

// ---------------------------------------------------------------------------
// fetchOrderBook
// ---------------------------------------------------------------------------
describe("fetchOrderBook", () => {
  it("returns mapped order book with bids and asks", async () => {
    mockFetchOrderBook.mockResolvedValueOnce({
      bids: [
        { price: 0.55, size: 100 },
        { price: 0.50, size: 200 },
      ],
      asks: [
        { price: 0.60, size: 150 },
        { price: 0.65, size: 50 },
      ],
    });

    const result = await fetchOrderBook("token-123");

    expect(result.tokenId).toBe("token-123");
    expect(result.bids).toEqual([
      { price: 0.55, size: 100 },
      { price: 0.50, size: 200 },
    ]);
    expect(result.asks).toEqual([
      { price: 0.60, size: 150 },
      { price: 0.65, size: 50 },
    ]);
    expect(mockFetchOrderBook).toHaveBeenCalledWith("token-123");
  });

  it("returns empty bids and asks for a thin book", async () => {
    mockFetchOrderBook.mockResolvedValueOnce({
      bids: [],
      asks: [],
    });

    const result = await fetchOrderBook("token-empty");

    expect(result.tokenId).toBe("token-empty");
    expect(result.bids).toEqual([]);
    expect(result.asks).toEqual([]);
  });

  it("strips extra fields from order levels", async () => {
    mockFetchOrderBook.mockResolvedValueOnce({
      bids: [{ price: 0.5, size: 10, extra: "ignored" }],
      asks: [{ price: 0.6, size: 20, timestamp: 12345 }],
    });

    const result = await fetchOrderBook("token-extra");

    expect(result.bids[0]).toEqual({ price: 0.5, size: 10 });
    expect(result.asks[0]).toEqual({ price: 0.6, size: 20 });
  });
});
