/**
 * Kalshi adapter for the venue-agnostic `MarketClient` interface.
 *
 * Public-read methods hit `demo-api.kalshi.co/trade-api/v2` directly via
 * the global `fetch`. Auth methods (signed with RSA-PSS) live in a
 * sibling module and are wired up by a later plan item; this file ships
 * them as stubs that throw a typed error until then.
 *
 * Identifier conventions:
 *  - `marketId` is the Kalshi market ticker (e.g.
 *    `KXNAMEDSTORM-26DEC01CPACTOT-2`).
 *  - `outcomeId` is the same ticker suffixed with `:YES` or `:NO`. Kalshi
 *    contracts trade both sides on a single ticker; the adapter encodes
 *    the side so callers carry it through the venue-neutral interface.
 *  - All prices are parsed from Kalshi dollar strings ("0.6500") to
 *    `number` (0.65). The interface contract is 0–1 normalized.
 */

import type {
  Balance,
  BuildOrderResult,
  Capabilities,
  CancelResult,
  EnsureAccountResult,
  FetchMyTradesParams,
  FetchOHLCVOptions,
  MarketClient,
  MarketMatch,
  MarketPrice,
  MarketSnapshot,
  MultiOutcomeMatch,
  OrderBook,
  OrderParams,
  OrderResponse,
  OutcomeLeg,
  Position,
  PriceCandle,
  PriceLevel,
  Trade,
  UserTrade,
} from "../client-market.js";

const DEFAULT_API_BASE = "https://demo-api.kalshi.co/trade-api/v2";
const YES_SUFFIX = ":YES";
const NO_SUFFIX = ":NO";

function getApiBase(): string {
  return process.env["KALSHI_API_BASE"] ?? DEFAULT_API_BASE;
}

/** Parse a Kalshi dollar string ("0.6500") into a number (0.65). */
function dollarStringToNumber(s: string | undefined): number {
  if (s === undefined || s === "") return 0;
  const n = Number(s);
  return Number.isFinite(n) ? n : 0;
}

/** 4-decimal round trip to keep `1 - 0.55` from leaking float garbage. */
function round4(n: number): number {
  return Number(n.toFixed(4));
}

interface KalshiRawMarket {
  ticker: string;
  event_ticker: string;
  title: string;
  status: string;
  yes_bid_dollars: string;
  yes_ask_dollars: string;
  no_bid_dollars: string;
  no_ask_dollars: string;
  yes_sub_title?: string;
  no_sub_title?: string;
  last_price_dollars?: string;
  volume_24h_fp?: string;
  volume_fp?: string;
  open_interest_fp?: string;
  close_time?: string;
  expiration_time?: string;
  notional_value_dollars?: string;
}

interface KalshiMarketsResponse {
  cursor?: string;
  markets: KalshiRawMarket[];
}

interface KalshiMarketResponse {
  market: KalshiRawMarket;
}

type KalshiLevel = [string, string];

interface KalshiOrderBookResponse {
  orderbook_fp: {
    yes_dollars?: KalshiLevel[] | null;
    no_dollars?: KalshiLevel[] | null;
  };
}

interface KalshiOHLC {
  open_dollars?: string;
  high_dollars?: string;
  low_dollars?: string;
  close_dollars?: string;
}

interface KalshiCandlestick {
  end_period_ts: number;
  yes_ask?: KalshiOHLC;
  yes_bid?: KalshiOHLC;
  price?: KalshiOHLC;
  volume_fp?: string;
  open_interest_fp?: string;
}

interface KalshiCandlestickResponse {
  candlesticks: KalshiCandlestick[];
  ticker: string;
}

interface KalshiEvent {
  event_ticker: string;
  series_ticker: string;
  title: string;
  sub_title?: string;
  markets: KalshiRawMarket[];
}

interface KalshiEventsResponse {
  cursor?: string;
  events: KalshiEvent[];
}

interface OutcomeRef {
  ticker: string;
  side: "YES" | "NO";
}

function parseOutcomeId(outcomeId: string): OutcomeRef {
  if (outcomeId.endsWith(YES_SUFFIX)) {
    return { ticker: outcomeId.slice(0, -YES_SUFFIX.length), side: "YES" };
  }
  if (outcomeId.endsWith(NO_SUFFIX)) {
    return { ticker: outcomeId.slice(0, -NO_SUFFIX.length), side: "NO" };
  }
  return { ticker: outcomeId, side: "YES" };
}

/** Kalshi tickers are `SERIES-EVENT-STRIKE`; the series is the first segment. */
function seriesTickerOf(ticker: string): string {
  const idx = ticker.indexOf("-");
  return idx > 0 ? ticker.slice(0, idx) : ticker;
}

/** True for tokens that look like a Kalshi series prefix (`KXNAMEDSTORM`). */
function isSeriesPrefix(s: string): boolean {
  return /^[A-Z0-9]+$/.test(s);
}

function mapMarketMatch(m: KalshiRawMarket): MarketMatch {
  const out: MarketMatch = {
    marketId: m.ticker,
    question: m.title,
    yesPrice: dollarStringToNumber(m.yes_ask_dollars),
    noPrice: dollarStringToNumber(m.no_ask_dollars),
    yesOutcomeId: `${m.ticker}${YES_SUFFIX}`,
    noOutcomeId: `${m.ticker}${NO_SUFFIX}`,
  };
  if (m.close_time) out.resolutionDate = m.close_time;
  return out;
}

function periodIntervalFor(timeframe: string | undefined): string {
  if (timeframe === "1d" || timeframe === "1440") return "1440";
  if (timeframe === "1m" || timeframe === "1") return "1";
  return "60";
}

function lookbackSecondsFor(periodInterval: string): number {
  if (periodInterval === "1") return 60 * 60;
  if (periodInterval === "1440") return 30 * 24 * 60 * 60;
  return 24 * 60 * 60;
}

/**
 * Build OHLC from a candlestick for the requested side.
 *
 * Preference order: real trade prices (`price`) → ask/bid quotes. The
 * `price` block is empty (`{}`) when no trades occurred in the period, so
 * the adapter falls back to `yes_ask` for the YES side and `yes_bid`
 * (inverted) for the NO side.
 */
function candleOHLC(
  c: KalshiCandlestick,
  side: "YES" | "NO",
): { open: number; high: number; low: number; close: number } {
  const trade = c.price;
  const hasTrade =
    trade !== undefined &&
    (trade.open_dollars !== undefined ||
      trade.close_dollars !== undefined);
  if (hasTrade) {
    const open = dollarStringToNumber(trade.open_dollars);
    const close = dollarStringToNumber(trade.close_dollars);
    const high = dollarStringToNumber(trade.high_dollars);
    const low = dollarStringToNumber(trade.low_dollars);
    return side === "YES"
      ? { open, high, low, close }
      : {
          open: round4(1 - open),
          high: round4(1 - low),
          low: round4(1 - high),
          close: round4(1 - close),
        };
  }
  if (side === "YES") {
    const src = c.yes_ask;
    return {
      open: dollarStringToNumber(src?.open_dollars),
      high: dollarStringToNumber(src?.high_dollars),
      low: dollarStringToNumber(src?.low_dollars),
      close: dollarStringToNumber(src?.close_dollars),
    };
  }
  const src = c.yes_bid;
  return {
    open: round4(1 - dollarStringToNumber(src?.open_dollars)),
    high: round4(1 - dollarStringToNumber(src?.low_dollars)),
    low: round4(1 - dollarStringToNumber(src?.high_dollars)),
    close: round4(1 - dollarStringToNumber(src?.close_dollars)),
  };
}

function notImpl(name: string): string {
  return `KalshiAdapter.${name}: not yet implemented`;
}

/** `MarketClient` implementation backed by the Kalshi REST API. */
export class KalshiAdapter implements MarketClient {
  private async getJSON<T>(
    path: string,
    params?: Record<string, string | undefined>,
  ): Promise<T> {
    const url = new URL(`${getApiBase()}${path}`);
    if (params) {
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined) url.searchParams.set(k, v);
      }
    }
    const res = await fetch(url.toString(), {
      method: "GET",
      headers: { accept: "application/json" },
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(
        `Kalshi GET ${path} failed: ${String(res.status)} ${body}`,
      );
    }
    return (await res.json()) as T;
  }

  async searchMarkets(query: string): Promise<MarketMatch[]> {
    const params: Record<string, string> = {
      status: "open",
      limit: "100",
    };
    if (query && isSeriesPrefix(query)) params["series_ticker"] = query;
    const data = await this.getJSON<KalshiMarketsResponse>("/markets", params);
    let markets = data.markets ?? [];
    if (query && !params["series_ticker"]) {
      const q = query.toLowerCase();
      markets = markets.filter((m) => m.title.toLowerCase().includes(q));
    }
    return markets.map(mapMarketMatch);
  }

  async fetchMarketPrice(marketId: string): Promise<MarketPrice> {
    const data = await this.getJSON<KalshiMarketResponse>(
      `/markets/${encodeURIComponent(marketId)}`,
    );
    const m = data.market;
    return {
      marketId: m.ticker,
      yesPrice: dollarStringToNumber(m.yes_ask_dollars),
      noPrice: dollarStringToNumber(m.no_ask_dollars),
      timestamp: new Date(),
    };
  }

  async fetchOrderBook(outcomeId: string): Promise<OrderBook> {
    const { ticker, side } = parseOutcomeId(outcomeId);
    const data = await this.getJSON<KalshiOrderBookResponse>(
      `/markets/${encodeURIComponent(ticker)}/orderbook`,
    );
    const yesLevels = data.orderbook_fp.yes_dollars ?? [];
    const noLevels = data.orderbook_fp.no_dollars ?? [];

    const toBid = (entry: KalshiLevel): PriceLevel => ({
      price: dollarStringToNumber(entry[0]),
      size: dollarStringToNumber(entry[1]),
    });
    const toAsk = (entry: KalshiLevel): PriceLevel => ({
      price: round4(1 - dollarStringToNumber(entry[0])),
      size: dollarStringToNumber(entry[1]),
    });

    const bidsSrc = side === "YES" ? yesLevels : noLevels;
    const asksSrc = side === "YES" ? noLevels : yesLevels;
    const bids = bidsSrc.map(toBid).sort((a, b) => b.price - a.price);
    const asks = asksSrc.map(toAsk).sort((a, b) => a.price - b.price);

    return { outcomeId, bids, asks };
  }

  async fetchOHLCV(
    outcomeId: string,
    options?: FetchOHLCVOptions,
  ): Promise<PriceCandle[]> {
    const { ticker, side } = parseOutcomeId(outcomeId);
    const seriesTicker = seriesTickerOf(ticker);
    const periodInterval = periodIntervalFor(options?.timeframe);
    const nowSec = Math.floor(Date.now() / 1000);
    const startTs = String(nowSec - lookbackSecondsFor(periodInterval));
    const endTs = String(nowSec);
    const data = await this.getJSON<KalshiCandlestickResponse>(
      `/series/${encodeURIComponent(seriesTicker)}/markets/${encodeURIComponent(ticker)}/candlesticks`,
      {
        period_interval: periodInterval,
        start_ts: startTs,
        end_ts: endTs,
      },
    );
    const candles = data.candlesticks ?? [];
    return candles.map((c) => {
      const ohlc = candleOHLC(c, side);
      return {
        timestamp: c.end_period_ts * 1000,
        open: ohlc.open,
        high: ohlc.high,
        low: ohlc.low,
        close: ohlc.close,
        volume:
          c.volume_fp !== undefined ? dollarStringToNumber(c.volume_fp) : null,
      };
    });
  }

  async fetchMarketSnapshots(query: string): Promise<MarketSnapshot[]> {
    const params: Record<string, string> = { status: "open", limit: "100" };
    if (query && isSeriesPrefix(query)) params["series_ticker"] = query;
    const data = await this.getJSON<KalshiMarketsResponse>("/markets", params);
    let markets = data.markets ?? [];
    if (query && !params["series_ticker"]) {
      const q = query.toLowerCase();
      markets = markets.filter((m) => m.title.toLowerCase().includes(q));
    }
    const now = Date.now();
    return markets.map((m) => {
      const closeMs = m.close_time ? Date.parse(m.close_time) : NaN;
      const timeToCloseMs = Number.isFinite(closeMs)
        ? Math.max(0, closeMs - now)
        : undefined;
      const snap: MarketSnapshot = {
        marketId: m.ticker,
        question: m.title,
        yesOutcomeId: `${m.ticker}${YES_SUFFIX}`,
        noOutcomeId: `${m.ticker}${NO_SUFFIX}`,
        yesPrice: dollarStringToNumber(m.yes_ask_dollars),
        noPrice: dollarStringToNumber(m.no_ask_dollars),
        volume24h: dollarStringToNumber(m.volume_24h_fp),
        openInterest: dollarStringToNumber(m.open_interest_fp),
        timestampMs: now,
      };
      if (timeToCloseMs !== undefined) snap.timeToCloseMs = timeToCloseMs;
      return snap;
    });
  }

  async searchMultiOutcomeMarkets(
    query: string,
  ): Promise<MultiOutcomeMatch[]> {
    const params: Record<string, string> = {
      with_nested_markets: "true",
      status: "open",
    };
    if (query && isSeriesPrefix(query)) params["series_ticker"] = query;
    const data = await this.getJSON<KalshiEventsResponse>("/events", params);
    let events = data.events ?? [];
    if (query && !params["series_ticker"]) {
      const q = query.toLowerCase();
      events = events.filter(
        (e) =>
          e.title.toLowerCase().includes(q) ||
          e.event_ticker.toLowerCase().includes(q),
      );
    }
    const results: MultiOutcomeMatch[] = [];
    for (const e of events) {
      const eventMarkets = e.markets ?? [];
      if (eventMarkets.length <= 2) continue;
      const legs: OutcomeLeg[] = eventMarkets.map((m) => ({
        outcome: m.yes_sub_title ?? m.title,
        outcomeId: `${m.ticker}${YES_SUFFIX}`,
        yesPrice: dollarStringToNumber(m.yes_ask_dollars),
      }));
      results.push({
        marketId: e.event_ticker,
        question: e.title,
        legs,
      });
    }
    return results;
  }

  async getCapabilities(): Promise<Capabilities> {
    return { supportsTif: true };
  }

  // ---------------------------------------------------------------------
  // Auth methods — stubs; wired up by a later plan item alongside
  // `kalshi-auth.ts` (RSA-PSS signer + auth fixtures).
  // ---------------------------------------------------------------------

  async fetchPositions(): Promise<Position[]> {
    throw new Error(notImpl("fetchPositions"));
  }

  async fetchBalance(): Promise<Balance[]> {
    throw new Error(notImpl("fetchBalance"));
  }

  async fetchMyTrades(params?: FetchMyTradesParams): Promise<UserTrade[]> {
    void params;
    throw new Error(notImpl("fetchMyTrades"));
  }

  async fetchOpenOrders(marketId?: string): Promise<OrderResponse[]> {
    void marketId;
    throw new Error(notImpl("fetchOpenOrders"));
  }

  async createOrder(params: OrderParams): Promise<OrderResponse> {
    void params;
    throw new Error(notImpl("createOrder"));
  }

  async cancelOrder(orderId: string): Promise<CancelResult> {
    void orderId;
    throw new Error(notImpl("cancelOrder"));
  }

  async buildOrder(params: OrderParams): Promise<BuildOrderResult> {
    void params;
    throw new Error(notImpl("buildOrder"));
  }

  async watchOrderBook(outcomeId: string): Promise<OrderBook> {
    void outcomeId;
    throw new Error(notImpl("watchOrderBook"));
  }

  async watchTrades(outcomeId: string): Promise<Trade[]> {
    void outcomeId;
    throw new Error(notImpl("watchTrades"));
  }

  async ensureAccount(): Promise<EnsureAccountResult> {
    throw new Error(notImpl("ensureAccount"));
  }
}
