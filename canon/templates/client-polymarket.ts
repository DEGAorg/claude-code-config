/**
 * Typed wrapper around the pmxtjs Polymarket client.
 *
 * All prediction-market data flows through these functions.
 * Strategy code never touches the pmxtjs SDK directly.
 */

import { Polymarket } from "pmxtjs";

/** YES/NO price snapshot for a Polymarket condition. */
export interface MarketPrice {
  conditionId: string;
  yes: number;
  no: number;
  timestamp: Date;
}

/** A Polymarket market search result. */
export interface PolymarketMatch {
  conditionId: string;
  question: string;
  yesPrice: number;
  noPrice: number;
  resolutionDate?: string;
}

/** A single price level in an order book. */
export interface PriceLevel {
  price: number;
  size: number;
}

/** Order book for a single outcome token. */
export interface OrderBook {
  tokenId: string;
  bids: PriceLevel[];
  asks: PriceLevel[];
}

/** A current position in a Polymarket market. */
export interface Position {
  marketId: string;
  outcomeId: string;
  outcomeLabel: string;
  size: number;
  entryPrice: number;
  currentPrice: number;
  unrealizedPnL: number;
}

/** Account balance entry for a Polymarket account. */
export interface AccountBalance {
  currency: string;
  total: number;
  available: number;
  locked: number;
}

/** A single trade from the authenticated user's trade history. */
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

/** Parameters for filtering trade history. */
export interface FetchMyTradesParams {
  marketId?: string;
  limit?: number;
  cursor?: string;
}

let client: Polymarket | undefined;

function getClient(): Polymarket {
  if (!client) {
    const privateKey = process.env["POLYMARKET_PRIVATE_KEY"];
    const proxyAddress = process.env["POLYMARKET_PROXY_ADDRESS"];

    client = new Polymarket({
      ...(privateKey ? { privateKey } : {}),
      ...(proxyAddress ? { proxyAddress } : {}),
      autoStartServer: true,
    });
  }
  return client;
}

/**
 * Fetch the current YES/NO price snapshot for a Polymarket condition.
 *
 * @param conditionId - Polymarket condition ID (the market's unique identifier).
 */
export async function fetchMarketPrice(
  conditionId: string,
): Promise<MarketPrice> {
  const poly = getClient();
  const markets = await poly.fetchMarkets({ query: conditionId });
  const market = markets[0];

  if (!market) {
    throw new Error(`Market ${conditionId} not found`);
  }

  if (market.outcomes.length !== 2) {
    throw new Error(
      `Market ${conditionId} is not a binary market ` +
        `(${String(market.outcomes.length)} outcomes)`,
    );
  }

  const yesPrice = market.outcomes[0]?.price;
  const noPrice = market.outcomes[1]?.price;

  if (yesPrice === undefined || noPrice === undefined) {
    throw new Error(
      `Market ${conditionId} missing outcome prices ` +
        `(yes=${String(yesPrice)}, no=${String(noPrice)})`,
    );
  }

  return {
    conditionId: market.marketId,
    yes: yesPrice,
    no: noPrice,
    timestamp: new Date(),
  };
}

/**
 * Search Polymarket for markets matching a query string.
 *
 * Returns binary YES/NO markets with current prices. Non-binary markets
 * (missing YES or NO price) are filtered out.
 *
 * @param query - Search text (e.g. "NBA", "Warriors Celtics").
 */
export async function searchMarkets(
  query: string,
): Promise<PolymarketMatch[]> {
  const poly = getClient();
  const markets = await poly.fetchMarkets({ query });
  const results: PolymarketMatch[] = [];

  for (const m of markets) {
    // Polymarket outcomes use descriptive labels (e.g. "Indiana Pacers" /
    // "Not Indiana Pacers"), not "Yes"/"No". Any 2-outcome market is
    // binary: first outcome = affirmative, second = negative.
    if (m.outcomes.length !== 2) continue;
    const yesPrice = m.outcomes[0]?.price;
    const noPrice = m.outcomes[1]?.price;
    if (yesPrice === undefined || noPrice === undefined) continue;

    const resDate = m.resolutionDate?.toISOString();
    results.push({
      conditionId: m.marketId,
      question: m.title,
      yesPrice,
      noPrice,
      ...(resDate !== undefined ? { resolutionDate: resDate } : {}),
    });
  }

  return results;
}

/**
 * Fetch the current order book for a Polymarket outcome token.
 *
 * @param tokenId - CLOB token ID (from `market.outcomes[n].outcomeId`).
 */
export async function fetchOrderBook(tokenId: string): Promise<OrderBook> {
  const poly = getClient();
  const book = await poly.fetchOrderBook(tokenId);

  const mapLevel = (l: { price: number; size: number }): PriceLevel => ({
    price: l.price,
    size: l.size,
  });

  return {
    tokenId,
    bids: book.bids.map(mapLevel),
    asks: book.asks.map(mapLevel),
  };
}

/**
 * Fetch current positions for the authenticated Polymarket account.
 *
 * Requires `POLYMARKET_PRIVATE_KEY` to be set. Auth errors from
 * pmxtjs propagate to the caller.
 */
export async function fetchPositions(): Promise<Position[]> {
  const poly = getClient();
  const positions = await poly.fetchPositions();

  return positions.map((p) => ({
    marketId: p.marketId,
    outcomeId: p.outcomeId,
    outcomeLabel: p.outcomeLabel,
    size: p.size,
    entryPrice: p.entryPrice,
    currentPrice: p.currentPrice,
    unrealizedPnL: p.unrealizedPnL,
  }));
}

/**
 * Fetch account balances for the authenticated Polymarket account.
 *
 * Requires `POLYMARKET_PRIVATE_KEY` to be set. Auth errors from
 * pmxtjs propagate to the caller.
 */
export async function fetchBalance(): Promise<AccountBalance[]> {
  const poly = getClient();
  const balances = await poly.fetchBalance();

  return balances.map((b) => ({
    currency: b.currency,
    total: b.total,
    available: b.available,
    locked: b.locked,
  }));
}

/**
 * Fetch trade history for the authenticated Polymarket account.
 *
 * Requires `POLYMARKET_PRIVATE_KEY` to be set. Auth errors from
 * pmxtjs propagate to the caller.
 *
 * @param params - Optional filtering/pagination parameters.
 */
export async function fetchMyTrades(
  params?: FetchMyTradesParams,
): Promise<UserTrade[]> {
  const poly = getClient();
  const trades = await poly.fetchMyTrades(params);

  return trades.map(
    (t: {
      id: string;
      price: number;
      amount: number;
      side: string;
      timestamp: number;
      orderId?: string;
      outcomeId?: string;
      marketId?: string;
    }): UserTrade => ({
      id: t.id,
      price: t.price,
      amount: t.amount,
      side: t.side,
      timestamp: t.timestamp,
      ...(t.orderId !== undefined ? { orderId: t.orderId } : {}),
      ...(t.outcomeId !== undefined ? { outcomeId: t.outcomeId } : {}),
      ...(t.marketId !== undefined ? { marketId: t.marketId } : {}),
    }),
  );
}

/** Parameters for creating or building an order. */
export interface OrderParams {
  marketId: string;
  tokenId: string;
  side: "buy" | "sell";
  size: number;
  price: number;
  orderType: "market" | "limit";
}

/** Order response from createOrder or cancelOrder. */
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

/** Dry-run result from buildOrder. */
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
  if (!VALID_SIDES.includes(params.side)) {
    throw new Error(
      `Invalid side "${String(params.side)}": ` +
        "must be \"buy\" or \"sell\"",
    );
  }
  if (!VALID_ORDER_TYPES.includes(params.orderType)) {
    throw new Error(
      `Invalid orderType "${String(params.orderType)}": ` +
        "must be \"market\" or \"limit\"",
    );
  }
}

/**
 * Create a new order on the exchange.
 *
 * Validates price (0-1) and size (> 0) before delegating to pmxtjs.
 *
 * @param params - Order parameters.
 */
export async function createOrder(
  params: OrderParams,
): Promise<OrderResponse> {
  validateOrderParams(params);
  const poly = getClient();
  const order = await poly.createOrder({
    marketId: params.marketId,
    outcomeId: params.tokenId,
    side: params.side,
    type: params.orderType,
    amount: params.size,
    price: params.price,
  });
  return {
    id: order.id,
    marketId: order.marketId,
    outcomeId: order.outcomeId,
    side: order.side,
    type: order.type,
    amount: order.amount,
    price: order.price ?? params.price,
    status: order.status,
    filled: order.filled,
    remaining: order.remaining,
  };
}

/**
 * Cancel an existing order.
 *
 * @param orderId - The order ID to cancel.
 */
export async function cancelOrder(
  orderId: string,
): Promise<OrderResponse> {
  const poly = getClient();
  const order = await poly.cancelOrder(orderId);
  return {
    id: order.id,
    marketId: order.marketId,
    outcomeId: order.outcomeId,
    side: order.side,
    type: order.type,
    amount: order.amount,
    price: order.price ?? 0,
    status: order.status,
    filled: order.filled,
    remaining: order.remaining,
  };
}

/**
 * Build an order payload without submitting.
 *
 * Validates params (same as createOrder) before delegating to pmxtjs.
 *
 * @param params - Order parameters.
 */
export async function buildOrder(
  params: OrderParams,
): Promise<BuildOrderResult> {
  validateOrderParams(params);
  const poly = getClient();
  const built = await poly.buildOrder({
    marketId: params.marketId,
    outcomeId: params.tokenId,
    side: params.side,
    type: params.orderType,
    amount: params.size,
    price: params.price,
  });
  return {
    exchange: built.exchange,
    params: {
      marketId: built.params.marketId,
      outcomeId: built.params.outcomeId,
      side: built.params.side,
      type: built.params.type,
      amount: built.params.amount,
      price: built.params.price ?? params.price,
    },
    ...(built.signedOrder !== undefined
      ? { signedOrder: built.signedOrder }
      : {}),
    raw: built.raw,
  };
}
