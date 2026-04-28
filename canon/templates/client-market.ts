/**
 * Venue-agnostic prediction-market client interface.
 *
 * Strategy code, CLI commands, and templates depend on `MarketClient`
 * rather than any specific exchange SDK. Concrete implementations live
 * under `./adapters/` (e.g. `PolymarketAdapter`). Use `getMarketClient`
 * to obtain a cached instance for the configured venue.
 */

import { PolymarketAdapter } from "./adapters/polymarket.js";

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

/** A single price level in an order book. */
export interface PriceLevel {
  price: number;
  size: number;
}

/** Order book snapshot for a single outcome. */
export interface OrderBook {
  outcomeId: string;
  bids: PriceLevel[];
  asks: PriceLevel[];
  /** Server-provided timestamp (ms epoch), if known. */
  timestamp?: number | null;
}

/** Current YES/NO price snapshot for a binary market. */
export interface MarketPrice {
  marketId: string;
  yesPrice: number;
  noPrice: number;
  timestamp: Date;
}

/** A binary market matched by `searchMarkets`. */
export interface MarketMatch {
  marketId: string;
  question: string;
  yesPrice: number;
  noPrice: number;
  yesOutcomeId: string;
  noOutcomeId: string;
  resolutionDate?: string;
}

/** A current position held by the authenticated account. */
export interface Position {
  marketId: string;
  outcomeId: string;
  outcomeLabel: string;
  size: number;
  entryPrice: number;
  currentPrice: number;
  unrealizedPnL: number;
}

/** Account balance entry. */
export interface Balance {
  currency: string;
  total: number;
  available: number;
  locked: number;
}

/** Parameters for creating or building an order. */
export interface OrderParams {
  marketId: string;
  outcomeId: string;
  side: "buy" | "sell";
  size: number;
  price: number;
  orderType: "market" | "limit";
}

/** Order returned by the exchange. */
export interface OrderResponse {
  id: string;
  marketId: string;
  outcomeId: string;
  side: "buy" | "sell";
  type: "market" | "limit";
  amount: number;
  price: number;
  status: string;
  filled: number;
  remaining: number;
}

/** Result of cancelling an order. */
export interface CancelResult {
  id: string;
  status: string;
}

/** Dry-run order build result (no submission). */
export interface BuildOrderResult {
  exchange: string;
  params: {
    marketId: string;
    outcomeId: string;
    side: string;
    type: string;
    amount: number;
    price: number;
  };
  signedOrder?: Record<string, unknown>;
  raw: unknown;
}

/** A public trade (e.g. from `watchTrades`). */
export interface Trade {
  id: string;
  price: number;
  size: number;
  side: string;
  timestamp: number;
}

/** A trade from the authenticated user's history. */
export interface UserTrade {
  id: string;
  price: number;
  amount: number;
  side: string;
  timestamp: number;
  orderId?: string;
  outcomeId?: string;
  marketId?: string;
}

/** Filtering / pagination parameters for `fetchMyTrades`. */
export interface FetchMyTradesParams {
  marketId?: string;
  limit?: number;
  cursor?: string;
}

/** OHLCV candle. */
export interface PriceCandle {
  timestamp: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number | null;
}

/** Options for `fetchOHLCV`. */
export interface FetchOHLCVOptions {
  timeframe?: string;
}

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------

/**
 * Venue-agnostic prediction-market client.
 *
 * All prices are normalized to the 0–1 range. All identifiers are
 * venue-neutral: `marketId` for the market, `outcomeId` for a specific
 * outcome token / contract.
 */
export interface MarketClient {
  /** Search markets matching a free-text query. */
  searchMarkets(query: string): Promise<MarketMatch[]>;

  /** Fetch the current YES/NO price snapshot for a binary market. */
  fetchMarketPrice(marketId: string): Promise<MarketPrice>;

  /** Fetch the current order book for an outcome. */
  fetchOrderBook(outcomeId: string): Promise<OrderBook>;

  /** Fetch OHLCV candles for an outcome. */
  fetchOHLCV(
    outcomeId: string,
    options?: FetchOHLCVOptions,
  ): Promise<PriceCandle[]>;

  /** Fetch open positions for the authenticated account. */
  fetchPositions(): Promise<Position[]>;

  /** Fetch account balances for the authenticated account. */
  fetchBalance(): Promise<Balance[]>;

  /** Fetch trade history for the authenticated account. */
  fetchMyTrades(params?: FetchMyTradesParams): Promise<UserTrade[]>;

  /** Fetch open orders for the authenticated account. */
  fetchOpenOrders(marketId?: string): Promise<OrderResponse[]>;

  /**
   * Submit a new order.
   *
   * `OrderResponse.price` falls back to `params.price` when the venue
   * omits the price in its response.
   */
  createOrder(params: OrderParams): Promise<OrderResponse>;

  /** Cancel an existing order by id. */
  cancelOrder(orderId: string): Promise<CancelResult>;

  /** Build (but do not submit) a signed order payload. */
  buildOrder(params: OrderParams): Promise<BuildOrderResult>;

  /**
   * Fetch a one-shot order book snapshot via streaming endpoint.
   *
   * Phase 1 returns a single snapshot rather than a true subscription;
   * a future revision may switch to `AsyncIterable<OrderBook>`.
   */
  watchOrderBook(outcomeId: string): Promise<OrderBook>;

  /**
   * Fetch a one-shot batch of recent trades via streaming endpoint.
   *
   * Phase 1 returns a single batch rather than a true subscription.
   */
  watchTrades(outcomeId: string): Promise<Trade[]>;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

const VENUE_FACTORIES: Record<string, () => MarketClient> = {
  polymarket: () => new PolymarketAdapter(),
};

const cache = new Map<string, MarketClient>();

/**
 * Resolve and return a cached `MarketClient` for the requested venue.
 *
 * Selection precedence: explicit `venue` arg → `MARKET_VENUE` env var →
 * default `"polymarket"`. Throws if the resolved venue is unknown.
 */
export function getMarketClient(venue?: string): MarketClient {
  const selected = venue ?? process.env["MARKET_VENUE"] ?? "polymarket";
  const cached = cache.get(selected);
  if (cached) return cached;

  const factory = VENUE_FACTORIES[selected];
  if (!factory) {
    throw new Error(
      `Unknown market venue "${selected}": supported venues are ` +
        Object.keys(VENUE_FACTORIES)
          .map((v) => `"${v}"`)
          .join(", "),
    );
  }

  const client = factory();
  cache.set(selected, client);
  return client;
}
