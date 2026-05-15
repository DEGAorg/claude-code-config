import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(here, "../fixtures/kalshi");

function loadFixture(name: string): unknown {
  return JSON.parse(readFileSync(`${FIXTURES}/${name}`, "utf-8"));
}

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

import { KalshiAdapter } from "../../adapters/kalshi.js";

let adapter: KalshiAdapter;

function jsonOk(data: unknown): Promise<{
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
  text: () => Promise<string>;
}> {
  return Promise.resolve({
    ok: true,
    status: 200,
    json: () => Promise.resolve(data),
    text: () => Promise.resolve(JSON.stringify(data)),
  });
}

function calledUrl(callIdx = 0): string {
  const call = mockFetch.mock.calls[callIdx];
  if (!call) throw new Error("fetch was not called");
  const first = call[0];
  return typeof first === "string" ? first : String(first);
}

beforeEach(() => {
  mockFetch.mockReset();
  delete process.env["KALSHI_API_BASE"];
  adapter = new KalshiAdapter();
});

afterEach(() => {
  delete process.env["KALSHI_API_BASE"];
});

// ---------------------------------------------------------------------------
// searchMarkets — ticker→marketId, "0.6500"→0.65, :YES/:NO outcome ids
// ---------------------------------------------------------------------------
describe("KalshiAdapter.searchMarkets", () => {
  it("maps Kalshi markets to MarketMatch[] with parsed prices", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("markets.json")));
    const results = await adapter.searchMarkets("KXNAMEDSTORM");
    expect(results.length).toBeGreaterThanOrEqual(5);
    const m20 = results.find(
      (r) => r.marketId === "KXNAMEDSTORM-26DEC01EPACTOT-20",
    );
    expect(m20).toBeDefined();
    expect(m20?.yesPrice).toBeCloseTo(1.0);
    expect(m20?.noPrice).toBeCloseTo(0.88);
    expect(m20?.yesOutcomeId).toBe("KXNAMEDSTORM-26DEC01EPACTOT-20:YES");
    expect(m20?.noOutcomeId).toBe("KXNAMEDSTORM-26DEC01EPACTOT-20:NO");
    expect(m20?.resolutionDate).toBe("2026-12-01T15:00:00Z");
    expect(m20?.question).toMatch(/named storms/i);
  });

  it("uses series_ticker query param when query is an uppercase prefix", async () => {
    mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", markets: [] }));
    await adapter.searchMarkets("KXNAMEDSTORM");
    expect(mockFetch).toHaveBeenCalledOnce();
    const url = calledUrl();
    expect(url).toContain("series_ticker=KXNAMEDSTORM");
    expect(url).toContain("status=open");
  });

  it("falls back to client-side title filter for free-text queries", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("markets.json")));
    const results = await adapter.searchMarkets("more than 20");
    expect(results).toHaveLength(1);
    expect(results[0]?.marketId).toBe("KXNAMEDSTORM-26DEC01EPACTOT-20");
    expect(calledUrl()).not.toContain("series_ticker");
  });

  it("respects KALSHI_API_BASE override", async () => {
    process.env["KALSHI_API_BASE"] = "https://api.example/test";
    mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", markets: [] }));
    await adapter.searchMarkets("");
    expect(calledUrl()).toMatch(/^https:\/\/api\.example\/test\/markets\?/);
  });

  it("defaults to demo-api base when env var unset", async () => {
    mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", markets: [] }));
    await adapter.searchMarkets("");
    expect(calledUrl()).toMatch(
      /^https:\/\/demo-api\.kalshi\.co\/trade-api\/v2\/markets\?/,
    );
  });

  it("omits resolutionDate when close_time is missing", async () => {
    mockFetch.mockReturnValueOnce(
      jsonOk({
        cursor: "",
        markets: [
          {
            ticker: "T-1",
            event_ticker: "EVT",
            title: "no close time",
            status: "active",
            yes_ask_dollars: "0.5",
            yes_bid_dollars: "0.4",
            no_ask_dollars: "0.6",
            no_bid_dollars: "0.5",
          },
        ],
      }),
    );
    const results = await adapter.searchMarkets("");
    expect(results).toHaveLength(1);
    expect(results[0]).not.toHaveProperty("resolutionDate");
  });
});

// ---------------------------------------------------------------------------
// fetchMarketPrice — hits /markets/{ticker}
// ---------------------------------------------------------------------------
describe("KalshiAdapter.fetchMarketPrice", () => {
  it("returns MarketPrice with parsed yes/no prices", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("market.json")));
    const price = await adapter.fetchMarketPrice(
      "KXNAMEDSTORM-26DEC01CPACTOT-2",
    );
    expect(price.marketId).toBe("KXNAMEDSTORM-26DEC01CPACTOT-2");
    expect(price.yesPrice).toBeCloseTo(0.23);
    expect(price.noPrice).toBeCloseTo(0.88);
    expect(price.timestamp).toBeInstanceOf(Date);
    expect(calledUrl()).toContain("/markets/KXNAMEDSTORM-26DEC01CPACTOT-2");
  });

  it("throws on non-ok response with status in message", async () => {
    mockFetch.mockReturnValueOnce(
      Promise.resolve({
        ok: false,
        status: 404,
        json: () => Promise.resolve({}),
        text: () => Promise.resolve("not found"),
      }),
    );
    await expect(adapter.fetchMarketPrice("MISSING")).rejects.toThrow(/404/);
  });
});

// ---------------------------------------------------------------------------
// fetchOrderBook — YES/NO sides, inverted asks
// ---------------------------------------------------------------------------
describe("KalshiAdapter.fetchOrderBook", () => {
  it("returns YES book: bids = yes_dollars (desc), asks = no_dollars inverted (asc)", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("orderbook.json")));
    const book = await adapter.fetchOrderBook(
      "KXNAMEDSTORM-26DEC01CPACTOT-2:YES",
    );
    expect(book.outcomeId).toBe("KXNAMEDSTORM-26DEC01CPACTOT-2:YES");
    // yes_dollars: [["0.0100","1.00"],["0.1200","1.00"]] → desc bids
    expect(book.bids).toEqual([
      { price: 0.12, size: 1 },
      { price: 0.01, size: 1 },
    ]);
    // no_dollars: [["0.5500","59.00"],["0.7700","1.00"]] → inverted asks asc
    // (1-0.55, 59) = (0.45, 59); (1-0.77, 1) = (0.23, 1)
    expect(book.asks).toEqual([
      { price: 0.23, size: 1 },
      { price: 0.45, size: 59 },
    ]);
  });

  it("returns NO book: bids = no_dollars (desc), asks = yes_dollars inverted (asc)", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("orderbook.json")));
    const book = await adapter.fetchOrderBook(
      "KXNAMEDSTORM-26DEC01CPACTOT-2:NO",
    );
    expect(book.bids).toEqual([
      { price: 0.77, size: 1 },
      { price: 0.55, size: 59 },
    ]);
    // yes_dollars inverted: (1-0.01, 1) = (0.99, 1); (1-0.12, 1) = (0.88, 1)
    expect(book.asks).toEqual([
      { price: 0.88, size: 1 },
      { price: 0.99, size: 1 },
    ]);
  });

  it("handles empty book sides", async () => {
    mockFetch.mockReturnValueOnce(
      jsonOk({ orderbook_fp: { yes_dollars: [], no_dollars: [] } }),
    );
    const book = await adapter.fetchOrderBook("T-X:YES");
    expect(book.bids).toEqual([]);
    expect(book.asks).toEqual([]);
  });

  it("hits the per-ticker orderbook endpoint", async () => {
    mockFetch.mockReturnValueOnce(jsonOk({ orderbook_fp: {} }));
    await adapter.fetchOrderBook("KXNAMEDSTORM-26DEC01CPACTOT-2:YES");
    expect(calledUrl()).toContain(
      "/markets/KXNAMEDSTORM-26DEC01CPACTOT-2/orderbook",
    );
  });
});

// ---------------------------------------------------------------------------
// fetchOHLCV — series/{series}/markets/{ticker}/candlesticks
// ---------------------------------------------------------------------------
describe("KalshiAdapter.fetchOHLCV", () => {
  it("maps Kalshi candlesticks to PriceCandle[] using yes_ask for YES side", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("candlesticks.json")));
    const candles = await adapter.fetchOHLCV(
      "KXNAMEDSTORM-26DEC01CPACTOT-2:YES",
      { timeframe: "60" },
    );
    expect(candles).toHaveLength(2);
    const c0 = candles[0];
    expect(c0?.timestamp).toBe(1778875200 * 1000);
    // yes_ask: open 0.4500, high 0.4500, low 0.2300, close 0.2300
    expect(c0?.open).toBeCloseTo(0.45);
    expect(c0?.high).toBeCloseTo(0.45);
    expect(c0?.low).toBeCloseTo(0.23);
    expect(c0?.close).toBeCloseTo(0.23);
    expect(c0?.volume).toBeCloseTo(0);
  });

  it("inverts and swaps high/low for NO-side outcomes (uses yes_bid)", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("candlesticks.json")));
    const candles = await adapter.fetchOHLCV(
      "KXNAMEDSTORM-26DEC01CPACTOT-2:NO",
      { timeframe: "60" },
    );
    const c0 = candles[0];
    // yes_bid: open 0.0000, high 0.1200, low 0.0000, close 0.1200
    // NO inverted (high↔low swap): open 1.0, high (1-yes_bid_low=0)=1.0,
    // low (1-yes_bid_high=0.12)=0.88, close (1-0.12)=0.88
    expect(c0?.open).toBeCloseTo(1.0);
    expect(c0?.high).toBeCloseTo(1.0);
    expect(c0?.low).toBeCloseTo(0.88);
    expect(c0?.close).toBeCloseTo(0.88);
  });

  it("hits /series/{series}/markets/{ticker}/candlesticks", async () => {
    mockFetch.mockReturnValueOnce(jsonOk({ candlesticks: [], ticker: "T" }));
    await adapter.fetchOHLCV("KXNAMEDSTORM-26DEC01CPACTOT-2:YES");
    expect(calledUrl()).toContain(
      "/series/KXNAMEDSTORM/markets/KXNAMEDSTORM-26DEC01CPACTOT-2/candlesticks",
    );
  });

  it("passes period_interval derived from timeframe option", async () => {
    mockFetch.mockReturnValueOnce(jsonOk({ candlesticks: [], ticker: "T" }));
    await adapter.fetchOHLCV("KXNAMEDSTORM-26DEC01CPACTOT-2:YES", {
      timeframe: "1d",
    });
    expect(calledUrl()).toContain("period_interval=1440");
  });
});

// ---------------------------------------------------------------------------
// fetchMarketSnapshots — volume, openInterest, timeToCloseMs
// ---------------------------------------------------------------------------
describe("KalshiAdapter.fetchMarketSnapshots", () => {
  it("maps markets to MarketSnapshot[] with volume / open-interest / TTL", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("markets.json")));
    const snaps = await adapter.fetchMarketSnapshots("KXNAMEDSTORM");
    expect(snaps.length).toBeGreaterThanOrEqual(5);
    const s = snaps[0];
    expect(s?.marketId).toMatch(/^KXNAMEDSTORM/);
    expect(s?.yesOutcomeId).toBe(`${s?.marketId ?? ""}:YES`);
    expect(s?.noOutcomeId).toBe(`${s?.marketId ?? ""}:NO`);
    expect(s?.yesPrice).toBeGreaterThanOrEqual(0);
    expect(s?.yesPrice).toBeLessThanOrEqual(1);
    expect(s?.volume24h).toBeGreaterThanOrEqual(0);
    expect(s?.openInterest).toBeGreaterThanOrEqual(0);
    expect(typeof s?.timestampMs).toBe("number");
    expect(s?.timeToCloseMs).toBeDefined();
  });

  it("omits timeToCloseMs when close_time is unparseable", async () => {
    mockFetch.mockReturnValueOnce(
      jsonOk({
        cursor: "",
        markets: [
          {
            ticker: "T",
            event_ticker: "EVT",
            title: "no close",
            status: "active",
            yes_ask_dollars: "0.5",
            yes_bid_dollars: "0.4",
            no_ask_dollars: "0.6",
            no_bid_dollars: "0.5",
            volume_24h_fp: "0",
            open_interest_fp: "0",
          },
        ],
      }),
    );
    const snaps = await adapter.fetchMarketSnapshots("");
    expect(snaps).toHaveLength(1);
    expect(snaps[0]).not.toHaveProperty("timeToCloseMs");
  });
});

// ---------------------------------------------------------------------------
// searchMultiOutcomeMarkets — /events?with_nested_markets=true
// ---------------------------------------------------------------------------
describe("KalshiAdapter.searchMultiOutcomeMarkets", () => {
  it("maps events with >2 nested markets to MultiOutcomeMatch[]", async () => {
    mockFetch.mockReturnValueOnce(jsonOk(loadFixture("events.json")));
    const results = await adapter.searchMultiOutcomeMarkets("KXNAMEDSTORM");
    expect(results).toHaveLength(2);
    const counts = results.map((r) => r.legs.length).sort((a, b) => a - b);
    expect(counts).toEqual([6, 8]);
    const first = results[0];
    expect(first?.marketId).toMatch(/^KXNAMEDSTORM/);
    expect(first?.question).toBeTruthy();
    for (const leg of first?.legs ?? []) {
      expect(typeof leg.outcome).toBe("string");
      expect(leg.outcomeId).toMatch(/:YES$/);
      expect(leg.yesPrice).toBeGreaterThanOrEqual(0);
      expect(leg.yesPrice).toBeLessThanOrEqual(1);
    }
  });

  it("passes with_nested_markets=true and series_ticker for prefix queries", async () => {
    mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", events: [] }));
    await adapter.searchMultiOutcomeMarkets("KXNAMEDSTORM");
    const url = calledUrl();
    expect(url).toContain("/events?");
    expect(url).toContain("with_nested_markets=true");
    expect(url).toContain("series_ticker=KXNAMEDSTORM");
  });

  it("filters out events with ≤2 markets", async () => {
    mockFetch.mockReturnValueOnce(
      jsonOk({
        cursor: "",
        events: [
          {
            event_ticker: "EVT-A",
            series_ticker: "S",
            title: "Two-leg",
            markets: [
              {
                ticker: "EVT-A-1",
                event_ticker: "EVT-A",
                title: "Leg 1",
                status: "active",
                yes_ask_dollars: "0.5",
                yes_bid_dollars: "0.4",
                no_ask_dollars: "0.5",
                no_bid_dollars: "0.4",
              },
              {
                ticker: "EVT-A-2",
                event_ticker: "EVT-A",
                title: "Leg 2",
                status: "active",
                yes_ask_dollars: "0.5",
                yes_bid_dollars: "0.4",
                no_ask_dollars: "0.5",
                no_bid_dollars: "0.4",
              },
            ],
          },
          {
            event_ticker: "EVT-B",
            series_ticker: "S",
            title: "Three-leg",
            markets: [
              {
                ticker: "EVT-B-1",
                event_ticker: "EVT-B",
                title: "Leg 1",
                status: "active",
                yes_ask_dollars: "0.3",
                yes_bid_dollars: "0.2",
                no_ask_dollars: "0.7",
                no_bid_dollars: "0.6",
              },
              {
                ticker: "EVT-B-2",
                event_ticker: "EVT-B",
                title: "Leg 2",
                status: "active",
                yes_ask_dollars: "0.3",
                yes_bid_dollars: "0.2",
                no_ask_dollars: "0.7",
                no_bid_dollars: "0.6",
              },
              {
                ticker: "EVT-B-3",
                event_ticker: "EVT-B",
                title: "Leg 3",
                status: "active",
                yes_ask_dollars: "0.4",
                yes_bid_dollars: "0.3",
                no_ask_dollars: "0.6",
                no_bid_dollars: "0.5",
              },
            ],
          },
        ],
      }),
    );
    const results = await adapter.searchMultiOutcomeMarkets("");
    expect(results).toHaveLength(1);
    expect(results[0]?.marketId).toBe("EVT-B");
    expect(results[0]?.legs).toHaveLength(3);
  });
});

// ---------------------------------------------------------------------------
// getCapabilities — no network, supportsTif true (Kalshi supports IOC/FOK)
// ---------------------------------------------------------------------------
describe("KalshiAdapter.getCapabilities", () => {
  it("reports supportsTif=true without hitting the network", async () => {
    const caps = await adapter.getCapabilities();
    expect(caps.supportsTif).toBe(true);
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
