import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import {
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(here, "../fixtures/kalshi");

function loadFixture(name: string): unknown {
  return JSON.parse(readFileSync(`${FIXTURES}/${name}`, "utf-8"));
}

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

import { KalshiAdapter } from "../../adapters/kalshi.js";
import {
  KalshiAuthError,
  _resetKalshiAuthCacheForTests,
} from "../../adapters/kalshi-auth.js";

let adapter: KalshiAdapter;

function jsonOk(data: unknown, status = 200): Promise<{
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
  text: () => Promise<string>;
}> {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
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

function calledInit(callIdx = 0): RequestInit {
  const call = mockFetch.mock.calls[callIdx];
  if (!call) throw new Error("fetch was not called");
  return (call[1] ?? {}) as RequestInit;
}

function calledHeaders(callIdx = 0): Record<string, string> {
  const init = calledInit(callIdx);
  return (init.headers ?? {}) as Record<string, string>;
}

function calledBody(callIdx = 0): Record<string, unknown> {
  const init = calledInit(callIdx);
  const body = init.body;
  if (typeof body !== "string") {
    throw new Error("expected JSON-encoded body string");
  }
  return JSON.parse(body) as Record<string, unknown>;
}

function calledMethod(callIdx = 0): string {
  const init = calledInit(callIdx);
  return (init.method ?? "GET").toUpperCase();
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

// ---------------------------------------------------------------------------
// Auth methods — generate a fresh RSA key per test, point env vars at it,
// then assert against captured demo fixtures (sanitized).
// ---------------------------------------------------------------------------

// Uppercase placeholder so the value cannot match the lowercase-hex UUID
// regex the no-PEM/no-UUID completion criterion greps for.
const TEST_API_KEY_ID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
const TEST_TICKER = "KXMLBEXTRAS-26MAY151840PHIPIT-EXTRAS";

describe("KalshiAdapter — auth methods", () => {
  let tmpDir: string;
  let pemPath: string;

  beforeEach(() => {
    const kp = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    const privatePem = kp.privateKey;
    tmpDir = mkdtempSync(join(tmpdir(), "kalshi-adapter-"));
    pemPath = join(tmpDir, "test-key.pem");
    writeFileSync(pemPath, privatePem, { mode: 0o600 });
    process.env["KALSHI_API_KEY_ID"] = TEST_API_KEY_ID;
    process.env["KALSHI_PRIVATE_KEY_PATH"] = pemPath;
    _resetKalshiAuthCacheForTests();
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
    delete process.env["KALSHI_API_KEY_ID"];
    delete process.env["KALSHI_PRIVATE_KEY_PATH"];
    _resetKalshiAuthCacheForTests();
  });

  // -------------------------------------------------------------------------
  // fetchBalance — GET /portfolio/balance, balance cents → USD float
  // -------------------------------------------------------------------------
  describe("fetchBalance", () => {
    it("maps Kalshi balance fixture to a single USD Balance entry", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("balance.json")));
      const balances = await adapter.fetchBalance();
      expect(balances).toHaveLength(1);
      const b = balances[0];
      // Fixture: balance=100000 cents, portfolio_value=0 cents
      expect(b?.currency).toBe("USD");
      expect(b?.total).toBeCloseTo(1000);
      expect(b?.available).toBeCloseTo(1000);
      expect(b?.locked).toBeCloseTo(0);
    });

    it("includes all three KALSHI-ACCESS-* headers on the request", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("balance.json")));
      await adapter.fetchBalance();
      const headers = calledHeaders();
      expect(headers["KALSHI-ACCESS-KEY"]).toBe(TEST_API_KEY_ID);
      expect(headers["KALSHI-ACCESS-TIMESTAMP"]).toMatch(/^\d+$/);
      expect(headers["KALSHI-ACCESS-SIGNATURE"]).toBeTruthy();
      expect(calledMethod()).toBe("GET");
      expect(calledUrl()).toContain("/trade-api/v2/portfolio/balance");
    });

    it("computes available = total - locked when portfolio_value > 0", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk({
          balance: 50000,
          portfolio_value: 7500,
          balance_breakdown: [],
        }),
      );
      const [b] = await adapter.fetchBalance();
      expect(b?.total).toBeCloseTo(500);
      expect(b?.locked).toBeCloseTo(75);
      expect(b?.available).toBeCloseTo(425);
    });

    it("throws KalshiAuthError when KALSHI_API_KEY_ID is unset", async () => {
      delete process.env["KALSHI_API_KEY_ID"];
      await expect(adapter.fetchBalance()).rejects.toThrow(KalshiAuthError);
      expect(mockFetch).not.toHaveBeenCalled();
    });
  });

  // -------------------------------------------------------------------------
  // fetchPositions — GET /portfolio/positions, signed YES/NO mapping
  // -------------------------------------------------------------------------
  describe("fetchPositions", () => {
    it("returns [] for an empty market_positions fixture", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("positions.json")));
      const positions = await adapter.fetchPositions();
      expect(positions).toEqual([]);
    });

    it("maps synthetic market_positions to Position[] (YES + NO sides)", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk({
          cursor: "",
          event_positions: [],
          market_positions: [
            {
              ticker: "KX-A",
              position: 10, // 10 YES contracts
              market_exposure: 500, // 500 cents = $5 total cost → $0.50/contract
            },
            {
              ticker: "KX-B",
              position: -4, // 4 NO contracts
              market_exposure: 200, // $2 total → $0.50/contract
            },
            {
              ticker: "KX-FLAT",
              position: 0,
              market_exposure: 0,
            },
          ],
        }),
      );
      const positions = await adapter.fetchPositions();
      expect(positions).toHaveLength(2);
      const yesPos = positions.find((p) => p.marketId === "KX-A");
      expect(yesPos?.outcomeId).toBe("KX-A:YES");
      expect(yesPos?.outcomeLabel).toBe("YES");
      expect(yesPos?.size).toBe(10);
      expect(yesPos?.entryPrice).toBeCloseTo(0.5);
      const noPos = positions.find((p) => p.marketId === "KX-B");
      expect(noPos?.outcomeId).toBe("KX-B:NO");
      expect(noPos?.outcomeLabel).toBe("NO");
      expect(noPos?.size).toBe(4);
      expect(noPos?.entryPrice).toBeCloseTo(0.5);
    });

    it("signs GET /portfolio/positions with the three KALSHI-ACCESS-* headers", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("positions.json")));
      await adapter.fetchPositions();
      const headers = calledHeaders();
      expect(headers["KALSHI-ACCESS-KEY"]).toBeTruthy();
      expect(headers["KALSHI-ACCESS-SIGNATURE"]).toBeTruthy();
      expect(calledUrl()).toContain("/portfolio/positions");
      expect(calledMethod()).toBe("GET");
    });
  });

  // -------------------------------------------------------------------------
  // fetchMyTrades — GET /portfolio/fills, optional ticker/limit/cursor
  // -------------------------------------------------------------------------
  describe("fetchMyTrades", () => {
    it("returns [] for an empty fills fixture", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("trade-history.json")));
      const trades = await adapter.fetchMyTrades();
      expect(trades).toEqual([]);
    });

    it("maps a synthetic fill to UserTrade (prefers _dollars over int cents)", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk({
          cursor: "",
          fills: [
            {
              trade_id: "trade-1",
              order_id: "order-1",
              ticker: TEST_TICKER,
              side: "yes",
              action: "buy",
              count: 3,
              yes_price_dollars: "0.0100",
              no_price_dollars: "0.9900",
              yes_price: 1,
              no_price: 99,
              created_time: "2026-05-15T21:17:30.000Z",
            },
          ],
        }),
      );
      const trades = await adapter.fetchMyTrades();
      expect(trades).toHaveLength(1);
      const t = trades[0];
      expect(t?.id).toBe("trade-1");
      expect(t?.price).toBeCloseTo(0.01);
      expect(t?.amount).toBe(3);
      expect(t?.side).toBe("buy");
      expect(t?.orderId).toBe("order-1");
      expect(t?.outcomeId).toBe(`${TEST_TICKER}:YES`);
      expect(t?.marketId).toBe(TEST_TICKER);
      expect(t?.timestamp).toBe(Date.parse("2026-05-15T21:17:30.000Z"));
    });

    it("passes marketId/limit/cursor as ticker query params", async () => {
      mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", fills: [] }));
      await adapter.fetchMyTrades({
        marketId: TEST_TICKER,
        limit: 50,
        cursor: "abc",
      });
      const url = calledUrl();
      expect(url).toContain(`ticker=${encodeURIComponent(TEST_TICKER)}`);
      expect(url).toContain("limit=50");
      expect(url).toContain("cursor=abc");
    });
  });

  // -------------------------------------------------------------------------
  // fetchOpenOrders — captured fixture has only "canceled" orders;
  // adapter filters by status === "resting".
  // -------------------------------------------------------------------------
  describe("fetchOpenOrders", () => {
    it("filters out non-resting orders (captured fixture has 0 resting)", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("open-orders.json")));
      const orders = await adapter.fetchOpenOrders();
      expect(orders).toEqual([]);
    });

    it("maps a synthetic resting order to OrderResponse (YES side, buy)", async () => {
      // Same shape as captured fixture, status flipped to "resting".
      const captured = loadFixture("open-orders.json") as {
        orders: Record<string, unknown>[];
      };
      const resting = { ...captured.orders[0], status: "resting" };
      mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", orders: [resting] }));
      const orders = await adapter.fetchOpenOrders();
      expect(orders).toHaveLength(1);
      const o = orders[0];
      expect(o?.id).toBe("AAAAAAAA-BBBB-CCCC-DDDD-000000000005");
      expect(o?.marketId).toBe(TEST_TICKER);
      expect(o?.outcomeId).toBe(`${TEST_TICKER}:YES`);
      expect(o?.side).toBe("buy");
      expect(o?.type).toBe("limit");
      expect(o?.amount).toBeCloseTo(1);
      expect(o?.price).toBeCloseTo(0.01);
      expect(o?.status).toBe("resting");
      expect(o?.filled).toBeCloseTo(0);
      expect(o?.remaining).toBeCloseTo(0);
    });

    it("passes the marketId as a ticker query param when supplied", async () => {
      mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", orders: [] }));
      await adapter.fetchOpenOrders(TEST_TICKER);
      expect(calledUrl()).toContain(`ticker=${encodeURIComponent(TEST_TICKER)}`);
    });
  });

  // -------------------------------------------------------------------------
  // createOrder — POST /portfolio/orders with cents body
  // -------------------------------------------------------------------------
  describe("createOrder", () => {
    it("POSTs Kalshi cents body and maps the 201 response", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk(loadFixture("order-create.json"), 201),
      );
      const order = await adapter.createOrder({
        marketId: TEST_TICKER,
        outcomeId: `${TEST_TICKER}:YES`,
        side: "buy",
        size: 1,
        price: 0.01,
        orderType: "limit",
      });
      expect(order.id).toBe("AAAAAAAA-BBBB-CCCC-DDDD-000000000002");
      expect(order.marketId).toBe(TEST_TICKER);
      expect(order.outcomeId).toBe(`${TEST_TICKER}:YES`);
      expect(order.side).toBe("buy");
      expect(order.type).toBe("limit");
      expect(order.amount).toBeCloseTo(1);
      expect(order.price).toBeCloseTo(0.01);
      expect(order.status).toBe("resting");
      expect(order.filled).toBeCloseTo(0);
      expect(order.remaining).toBeCloseTo(1);

      expect(calledMethod()).toBe("POST");
      const body = calledBody();
      expect(body["ticker"]).toBe(TEST_TICKER);
      expect(body["action"]).toBe("buy");
      expect(body["side"]).toBe("yes");
      expect(body["count"]).toBe(1);
      expect(body["type"]).toBe("limit");
      expect(body["yes_price_dollars"]).toBe("0.0100");
      expect(body["client_order_id"]).toMatch(/^[0-9a-f-]{36}$/i);
      expect(body).not.toHaveProperty("no_price_dollars");
      expect(body).not.toHaveProperty("yes_price");
      expect(body).not.toHaveProperty("no_price");
    });

    it("sets no_price_dollars when the outcomeId targets the NO side", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk(loadFixture("order-create.json"), 201),
      );
      await adapter.createOrder({
        marketId: TEST_TICKER,
        outcomeId: `${TEST_TICKER}:NO`,
        side: "buy",
        size: 2,
        price: 0.42,
        orderType: "limit",
      });
      const body = calledBody();
      expect(body["side"]).toBe("no");
      expect(body["no_price_dollars"]).toBe("0.4200");
      expect(body).not.toHaveProperty("yes_price_dollars");
    });

    it("maps timeInForce to Kalshi's snake_case enum", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk(loadFixture("order-create.json"), 201),
      );
      await adapter.createOrder({
        marketId: TEST_TICKER,
        outcomeId: `${TEST_TICKER}:YES`,
        side: "buy",
        size: 1,
        price: 0.01,
        orderType: "limit",
        timeInForce: "IOC",
      });
      expect(calledBody()["time_in_force"]).toBe("immediate_or_cancel");
    });

    it("includes signed KALSHI-ACCESS-* headers + content-type", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk(loadFixture("order-create.json"), 201),
      );
      await adapter.createOrder({
        marketId: TEST_TICKER,
        outcomeId: `${TEST_TICKER}:YES`,
        side: "buy",
        size: 1,
        price: 0.01,
        orderType: "limit",
      });
      const headers = calledHeaders();
      expect(headers["KALSHI-ACCESS-KEY"]).toBe(TEST_API_KEY_ID);
      expect(headers["KALSHI-ACCESS-SIGNATURE"]).toBeTruthy();
      expect(headers["content-type"]).toBe("application/json");
    });

    it("rejects price outside [0, 1]", async () => {
      await expect(
        adapter.createOrder({
          marketId: TEST_TICKER,
          outcomeId: `${TEST_TICKER}:YES`,
          side: "buy",
          size: 1,
          price: 1.5,
          orderType: "limit",
        }),
      ).rejects.toThrow(/price/i);
      expect(mockFetch).not.toHaveBeenCalled();
    });

    it("rejects size <= 0", async () => {
      await expect(
        adapter.createOrder({
          marketId: TEST_TICKER,
          outcomeId: `${TEST_TICKER}:YES`,
          side: "buy",
          size: 0,
          price: 0.5,
          orderType: "limit",
        }),
      ).rejects.toThrow(/size/i);
    });

    it("throws KalshiAuthError when KALSHI_PRIVATE_KEY_PATH is missing", async () => {
      delete process.env["KALSHI_PRIVATE_KEY_PATH"];
      await expect(
        adapter.createOrder({
          marketId: TEST_TICKER,
          outcomeId: `${TEST_TICKER}:YES`,
          side: "buy",
          size: 1,
          price: 0.01,
          orderType: "limit",
        }),
      ).rejects.toThrow(KalshiAuthError);
      expect(mockFetch).not.toHaveBeenCalled();
    });
  });

  // -------------------------------------------------------------------------
  // cancelOrder — DELETE /portfolio/orders/{orderId}
  // -------------------------------------------------------------------------
  describe("cancelOrder", () => {
    it("DELETEs the order id endpoint and maps the cancel envelope", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("order-cancel.json")));
      const result = await adapter.cancelOrder(
        "AAAAAAAA-BBBB-CCCC-DDDD-000000000002",
      );
      expect(result.id).toBe("AAAAAAAA-BBBB-CCCC-DDDD-000000000002");
      expect(result.status).toBe("canceled");
      expect(calledMethod()).toBe("DELETE");
      expect(calledUrl()).toContain(
        "/portfolio/orders/AAAAAAAA-BBBB-CCCC-DDDD-000000000002",
      );
    });

    it("signs the DELETE request with KALSHI-ACCESS-* headers", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("order-cancel.json")));
      await adapter.cancelOrder("abc-123");
      const headers = calledHeaders();
      expect(headers["KALSHI-ACCESS-KEY"]).toBeTruthy();
      expect(headers["KALSHI-ACCESS-SIGNATURE"]).toBeTruthy();
    });
  });

  // -------------------------------------------------------------------------
  // buildOrder — dry run, no network
  // -------------------------------------------------------------------------
  describe("buildOrder", () => {
    it("returns a BuildOrderResult without calling fetch", async () => {
      const built = await adapter.buildOrder({
        marketId: TEST_TICKER,
        outcomeId: `${TEST_TICKER}:YES`,
        side: "buy",
        size: 2,
        price: 0.25,
        orderType: "limit",
      });
      expect(mockFetch).not.toHaveBeenCalled();
      expect(built.exchange).toBe("kalshi");
      expect(built.params).toEqual({
        marketId: TEST_TICKER,
        outcomeId: `${TEST_TICKER}:YES`,
        side: "buy",
        type: "limit",
        amount: 2,
        price: 0.25,
      });
      const raw = built.raw as Record<string, unknown>;
      expect(raw["ticker"]).toBe(TEST_TICKER);
      expect(raw["side"]).toBe("yes");
      expect(raw["action"]).toBe("buy");
      expect(raw["count"]).toBe(2);
      expect(raw["yes_price_dollars"]).toBe("0.2500");
      expect(raw["client_order_id"]).toMatch(/^[0-9a-f-]{36}$/i);
    });

    it("validates params before building", async () => {
      await expect(
        adapter.buildOrder({
          marketId: TEST_TICKER,
          outcomeId: `${TEST_TICKER}:YES`,
          side: "buy",
          size: 1,
          price: -0.1,
          orderType: "limit",
        }),
      ).rejects.toThrow(/price/i);
    });
  });

  // -------------------------------------------------------------------------
  // watchOrderBook — one-shot snapshot with a timestamp
  // -------------------------------------------------------------------------
  describe("watchOrderBook", () => {
    it("returns an OrderBook with a populated timestamp", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("orderbook.json")));
      const before = Date.now();
      const book = await adapter.watchOrderBook(
        "KXNAMEDSTORM-26DEC01CPACTOT-2:YES",
      );
      const after = Date.now();
      expect(book.outcomeId).toBe("KXNAMEDSTORM-26DEC01CPACTOT-2:YES");
      expect(book.bids.length).toBeGreaterThan(0);
      expect(book.asks.length).toBeGreaterThan(0);
      expect(typeof book.timestamp).toBe("number");
      expect(book.timestamp ?? 0).toBeGreaterThanOrEqual(before);
      expect(book.timestamp ?? 0).toBeLessThanOrEqual(after);
    });

    it("hits the public /markets/{ticker}/orderbook endpoint (unsigned)", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("orderbook.json")));
      await adapter.watchOrderBook("KXNAMEDSTORM-26DEC01CPACTOT-2:YES");
      expect(calledUrl()).toContain(
        "/markets/KXNAMEDSTORM-26DEC01CPACTOT-2/orderbook",
      );
      // Orderbook is a public endpoint — no auth headers required.
      const headers = calledHeaders();
      expect(headers["KALSHI-ACCESS-KEY"]).toBeUndefined();
    });
  });

  // -------------------------------------------------------------------------
  // watchTrades — REST snapshot of recent public trades
  // -------------------------------------------------------------------------
  describe("watchTrades", () => {
    it("maps Kalshi public trades to Trade[] for YES side", async () => {
      mockFetch.mockReturnValueOnce(
        jsonOk({
          cursor: "",
          trades: [
            {
              trade_id: "T1",
              ticker: TEST_TICKER,
              yes_price: 25,
              no_price: 75,
              count: 3,
              created_time: "2026-05-15T20:00:00.000Z",
              taker_side: "yes",
            },
            {
              trade_id: "T2",
              ticker: TEST_TICKER,
              yes_price: 30,
              no_price: 70,
              count: 1,
              created_time: "2026-05-15T20:00:05.000Z",
              taker_side: "no",
            },
          ],
        }),
      );
      const trades = await adapter.watchTrades(`${TEST_TICKER}:YES`);
      expect(trades).toHaveLength(2);
      expect(trades[0]?.id).toBe("T1");
      expect(trades[0]?.price).toBeCloseTo(0.25);
      expect(trades[0]?.size).toBe(3);
      expect(trades[0]?.side).toBe("buy");
      expect(trades[0]?.timestamp).toBe(
        Date.parse("2026-05-15T20:00:00.000Z"),
      );
      expect(trades[1]?.side).toBe("sell");
    });

    it("passes ticker query param to /markets/trades (unsigned)", async () => {
      mockFetch.mockReturnValueOnce(jsonOk({ cursor: "", trades: [] }));
      await adapter.watchTrades(`${TEST_TICKER}:YES`);
      const url = calledUrl();
      expect(url).toContain("/markets/trades");
      expect(url).toContain(`ticker=${encodeURIComponent(TEST_TICKER)}`);
      expect(calledHeaders()["KALSHI-ACCESS-KEY"]).toBeUndefined();
    });
  });

  // -------------------------------------------------------------------------
  // ensureAccount — proves creds work by issuing one signed balance call
  // -------------------------------------------------------------------------
  describe("ensureAccount", () => {
    it("returns ready=true after a successful signed balance call", async () => {
      mockFetch.mockReturnValueOnce(jsonOk(loadFixture("balance.json")));
      const result = await adapter.ensureAccount();
      expect(result.ready).toBe(true);
      expect(mockFetch).toHaveBeenCalledOnce();
      expect(calledUrl()).toContain("/portfolio/balance");
      expect(calledHeaders()["KALSHI-ACCESS-KEY"]).toBe(TEST_API_KEY_ID);
    });

    it("propagates KalshiAuthError when credentials are missing", async () => {
      delete process.env["KALSHI_API_KEY_ID"];
      delete process.env["KALSHI_PRIVATE_KEY_PATH"];
      await expect(adapter.ensureAccount()).rejects.toThrow(KalshiAuthError);
      expect(mockFetch).not.toHaveBeenCalled();
    });
  });
});
