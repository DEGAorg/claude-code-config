/**
 * Kalshi adapter for the venue-agnostic `MarketClient` interface.
 *
 * Public-read methods hit `demo-api.kalshi.co/trade-api/v2` directly via
 * the global `fetch`. Auth methods sign each request with the RSA-PSS
 * signer in `./kalshi-auth.ts`; credentials come from env vars only
 * (`KALSHI_API_KEY_ID`, `KALSHI_PRIVATE_KEY_PATH`).
 *
 * Identifier conventions:
 *  - `marketId` is the Kalshi market ticker (e.g.
 *    `KXNAMEDSTORM-26DEC01CPACTOT-2`).
 *  - `outcomeId` is the same ticker suffixed with `:YES` or `:NO`. Kalshi
 *    contracts trade both sides on a single ticker; the adapter encodes
 *    the side so callers carry it through the venue-neutral interface.
 *  - All prices are parsed from Kalshi dollar strings ("0.6500") to
 *    `number` (0.65). The interface contract is 0–1 normalized.
 *  - Kalshi REST accepts integer cents in request bodies (`yes_price: 1`
 *    for `$0.01`); the adapter rounds `OrderParams.price * 100`.
 */

import { randomUUID } from "node:crypto";
import { buildKalshiAuthHeaders } from "./kalshi-auth.js";
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

interface KalshiBalance {
  /** Cash balance in cents. */
  balance: number;
  balance_breakdown?: { balance: string; exchange_index: number }[];
  /** Value locked in positions / open orders, in cents. */
  portfolio_value: number;
  updated_ts?: number;
}

interface KalshiMarketPosition {
  ticker: string;
  /** Signed contracts: positive = YES exposure, negative = NO exposure. */
  position: number;
  /** Cost basis in cents. */
  market_exposure: number;
  realized_pnl?: number;
  total_traded?: number;
  fees_paid?: number;
  resting_orders_count?: number;
  last_updated_ts?: number;
}

interface KalshiPositionsResponse {
  cursor?: string;
  event_positions?: unknown[];
  market_positions?: KalshiMarketPosition[];
}

interface KalshiFill {
  trade_id: string;
  order_id: string;
  ticker: string;
  side: "yes" | "no";
  action: "buy" | "sell";
  count: number;
  yes_price?: number;
  no_price?: number;
  yes_price_dollars?: string;
  no_price_dollars?: string;
  created_time: string;
}

interface KalshiFillsResponse {
  cursor?: string;
  fills?: KalshiFill[];
}

interface KalshiOrder {
  order_id: string;
  client_order_id?: string;
  ticker: string;
  /** `"buy"` | `"sell"` — direction relative to the YES/NO side. */
  action: string;
  /** `"yes"` | `"no"` — which side of the contract the order touches. */
  side: string;
  /** `"limit"` | `"market"`. */
  type: string;
  status: string;
  yes_price_dollars?: string;
  no_price_dollars?: string;
  initial_count_fp?: string;
  fill_count_fp?: string;
  remaining_count_fp?: string;
  created_time?: string;
  last_update_time?: string;
}

interface KalshiOrdersResponse {
  cursor?: string;
  orders?: KalshiOrder[];
}

interface KalshiOrderEnvelope {
  order: KalshiOrder;
}

interface KalshiCancelEnvelope {
  order: KalshiOrder;
  reduced_by_fp?: string;
}

interface KalshiPublicTrade {
  trade_id: string;
  ticker: string;
  yes_price?: number;
  no_price?: number;
  yes_price_dollars?: string;
  no_price_dollars?: string;
  count: number;
  created_time: string;
  taker_side: "yes" | "no";
}

interface KalshiTradesResponse {
  cursor?: string;
  trades?: KalshiPublicTrade[];
}

const VALID_SIDES = ["buy", "sell"] as const;
const VALID_ORDER_TYPES = ["market", "limit"] as const;

function validateOrderParams(params: OrderParams): void {
  if (params.price < 0 || params.price > 1) {
    throw new Error(
      `Invalid price ${String(params.price)}: ` +
        "must be between 0 and 1",
    );
  }
  if (params.size <= 0) {
    throw new Error(
      `Invalid size ${String(params.size)}: ` +
        "must be greater than 0",
    );
  }
  if (!(VALID_SIDES as readonly string[]).includes(params.side)) {
    throw new Error(
      `Invalid side "${String(params.side)}": ` +
        'must be "buy" or "sell"',
    );
  }
  if (!(VALID_ORDER_TYPES as readonly string[]).includes(params.orderType)) {
    throw new Error(
      `Invalid orderType "${String(params.orderType)}": ` +
        'must be "market" or "limit"',
    );
  }
}

/**
 * Translate {@link OrderParams} into the Kalshi POST /portfolio/orders
 * body. Kalshi accepts integer cents for prices, so a `0.6253` interface
 * price round-trips through `Math.round(price * 100)` and loses sub-cent
 * precision. Sub-penny ticks need a follow-up that switches to
 * `yes_price_dollars` string fields.
 */
function buildKalshiOrderBody(params: OrderParams): Record<string, unknown> {
  validateOrderParams(params);
  const { ticker, side: yesNoSide } = parseOutcomeId(params.outcomeId);
  const kalshiSide: "yes" | "no" = yesNoSide === "YES" ? "yes" : "no";
  const action: "buy" | "sell" = params.side === "sell" ? "sell" : "buy";
  const orderType: "limit" | "market" =
    params.orderType === "market" ? "market" : "limit";
  const priceCents = Math.round(params.price * 100);
  const body: Record<string, unknown> = {
    ticker,
    action,
    side: kalshiSide,
    count: Math.round(params.size),
    type: orderType,
    client_order_id: randomUUID(),
  };
  if (kalshiSide === "yes") body["yes_price"] = priceCents;
  else body["no_price"] = priceCents;
  if (params.timeInForce !== undefined) {
    body["time_in_force"] = params.timeInForce;
  }
  return body;
}

function mapKalshiOrder(o: KalshiOrder): OrderResponse {
  const isYes = o.side === "yes";
  const price = dollarStringToNumber(
    isYes ? o.yes_price_dollars : o.no_price_dollars,
  );
  const side: "buy" | "sell" = o.action === "sell" ? "sell" : "buy";
  const type: "market" | "limit" = o.type === "market" ? "market" : "limit";
  return {
    id: o.order_id,
    marketId: o.ticker,
    outcomeId: `${o.ticker}${isYes ? YES_SUFFIX : NO_SUFFIX}`,
    side,
    type,
    amount: dollarStringToNumber(o.initial_count_fp),
    price,
    status: o.status,
    filled: dollarStringToNumber(o.fill_count_fp),
    remaining: dollarStringToNumber(o.remaining_count_fp),
  };
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

  /**
   * Issue a signed Kalshi request. The signature payload is
   * `timestamp + METHOD + url.pathname` — query string is stripped, body
   * is not signed. Throws `KalshiAuthError` (from {@link buildKalshiAuthHeaders})
   * when credentials are missing.
   */
  private async signedFetch<T>(
    method: "GET" | "POST" | "DELETE",
    path: string,
    options: {
      body?: unknown;
      query?: Record<string, string | undefined>;
    } = {},
  ): Promise<T> {
    const url = new URL(`${getApiBase()}${path}`);
    if (options.query) {
      for (const [k, v] of Object.entries(options.query)) {
        if (v !== undefined) url.searchParams.set(k, v);
      }
    }
    const authHeaders = buildKalshiAuthHeaders({
      method,
      path: url.pathname,
    });
    const headers: Record<string, string> = {
      accept: "application/json",
      ...authHeaders,
    };
    const init: RequestInit = { method, headers };
    if (options.body !== undefined) {
      headers["content-type"] = "application/json";
      init.body = JSON.stringify(options.body);
    }
    const res = await fetch(url.toString(), init);
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(
        `Kalshi ${method} ${path} failed: ${String(res.status)} ${body}`,
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
  // Auth methods — signed with RSA-PSS via `kalshi-auth.ts`.
  // ---------------------------------------------------------------------

  async fetchBalance(): Promise<Balance[]> {
    const data = await this.signedFetch<KalshiBalance>(
      "GET",
      "/portfolio/balance",
    );
    const totalCents = data.balance;
    const lockedCents = data.portfolio_value;
    const availableCents = totalCents - lockedCents;
    return [
      {
        currency: "USD",
        total: totalCents / 100,
        available: availableCents / 100,
        locked: lockedCents / 100,
      },
    ];
  }

  async fetchPositions(): Promise<Position[]> {
    const data = await this.signedFetch<KalshiPositionsResponse>(
      "GET",
      "/portfolio/positions",
    );
    const positions = data.market_positions ?? [];
    return positions
      .filter((p) => p.position !== 0)
      .map((p) => {
        const isYes = p.position > 0;
        const size = Math.abs(p.position);
        // market_exposure is the position's cost basis in cents.
        const exposureUSD = Math.abs(p.market_exposure) / 100;
        const entryPrice = size > 0 ? exposureUSD / size : 0;
        // Kalshi's positions endpoint doesn't return a live mark; callers
        // who need MTM PnL must hit `fetchMarketPrice` per market.
        return {
          marketId: p.ticker,
          outcomeId: `${p.ticker}${isYes ? YES_SUFFIX : NO_SUFFIX}`,
          outcomeLabel: isYes ? "YES" : "NO",
          size,
          entryPrice,
          currentPrice: entryPrice,
          unrealizedPnL: 0,
        };
      });
  }

  async fetchMyTrades(params?: FetchMyTradesParams): Promise<UserTrade[]> {
    const query: Record<string, string | undefined> = {};
    if (params?.marketId !== undefined) query["ticker"] = params.marketId;
    if (params?.limit !== undefined) query["limit"] = String(params.limit);
    if (params?.cursor !== undefined) query["cursor"] = params.cursor;
    const data = await this.signedFetch<KalshiFillsResponse>(
      "GET",
      "/portfolio/fills",
      { query },
    );
    const fills = data.fills ?? [];
    return fills.map((f) => {
      const isYes = f.side === "yes";
      const dollarStr = isYes ? f.yes_price_dollars : f.no_price_dollars;
      const intCents = isYes ? f.yes_price : f.no_price;
      const price =
        dollarStr !== undefined
          ? dollarStringToNumber(dollarStr)
          : (intCents ?? 0) / 100;
      return {
        id: f.trade_id,
        price,
        amount: f.count,
        side: f.action,
        timestamp: Date.parse(f.created_time),
        orderId: f.order_id,
        outcomeId: `${f.ticker}${isYes ? YES_SUFFIX : NO_SUFFIX}`,
        marketId: f.ticker,
      };
    });
  }

  async fetchOpenOrders(marketId?: string): Promise<OrderResponse[]> {
    const query: Record<string, string | undefined> = {};
    if (marketId !== undefined) query["ticker"] = marketId;
    // The `status=resting` query param is a no-op on demo (returns empty
    // even when resting orders exist). Fetch unfiltered and apply the
    // status filter in-process.
    const data = await this.signedFetch<KalshiOrdersResponse>(
      "GET",
      "/portfolio/orders",
      { query },
    );
    const orders = data.orders ?? [];
    return orders.filter((o) => o.status === "resting").map(mapKalshiOrder);
  }

  async createOrder(params: OrderParams): Promise<OrderResponse> {
    const body = buildKalshiOrderBody(params);
    const data = await this.signedFetch<KalshiOrderEnvelope>(
      "POST",
      "/portfolio/orders",
      { body },
    );
    const mapped = mapKalshiOrder(data.order);
    return mapped.price === 0 && params.price !== 0
      ? { ...mapped, price: params.price }
      : mapped;
  }

  async cancelOrder(orderId: string): Promise<CancelResult> {
    const data = await this.signedFetch<KalshiCancelEnvelope>(
      "DELETE",
      `/portfolio/orders/${encodeURIComponent(orderId)}`,
    );
    return {
      id: data.order.order_id ?? orderId,
      status: data.order.status,
    };
  }

  async buildOrder(params: OrderParams): Promise<BuildOrderResult> {
    const body = buildKalshiOrderBody(params);
    return {
      exchange: "kalshi",
      params: {
        marketId: params.marketId,
        outcomeId: params.outcomeId,
        side: params.side,
        type: params.orderType,
        amount: params.size,
        price: params.price,
      },
      raw: body,
    };
  }

  async watchOrderBook(outcomeId: string): Promise<OrderBook> {
    const book = await this.fetchOrderBook(outcomeId);
    return { ...book, timestamp: Date.now() };
  }

  async watchTrades(outcomeId: string): Promise<Trade[]> {
    const { ticker, side } = parseOutcomeId(outcomeId);
    const data = await this.getJSON<KalshiTradesResponse>("/markets/trades", {
      ticker,
      limit: "100",
    });
    const trades = data.trades ?? [];
    return trades.map((t) => {
      const isYes = side === "YES";
      const dollarStr = isYes ? t.yes_price_dollars : t.no_price_dollars;
      const intCents = isYes ? t.yes_price : t.no_price;
      const price =
        dollarStr !== undefined
          ? dollarStringToNumber(dollarStr)
          : (intCents ?? 0) / 100;
      return {
        id: t.trade_id,
        price,
        size: t.count,
        side: t.taker_side === "yes" ? "buy" : "sell",
        timestamp: Date.parse(t.created_time),
      };
    });
  }

  /**
   * Verify Kalshi credentials by issuing one signed `fetchBalance` call.
   * Idempotent — Kalshi has no separate account-bootstrap endpoint, so
   * "account ready" reduces to "credentials sign successfully".
   */
  async ensureAccount(): Promise<EnsureAccountResult> {
    await this.fetchBalance();
    return { ready: true };
  }
}
