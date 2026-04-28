/**
 * Polymarket adapter for the venue-agnostic `MarketClient` interface.
 *
 * Wraps the `pmxtjs.Polymarket` SDK and normalizes its shapes to the
 * shared types in `../client-market.ts`. Sidecar-backed methods
 * (`fetchOHLCV`, `watchOrderBook`, `watchTrades`, and order lifecycle
 * calls that need to bypass the SDK header-clobbering bug in pmxtjs
 * v2.22.1) call the pmxt sidecar directly via `callSidecar`.
 */

import { Polymarket } from "pmxtjs";
import { callSidecar } from "../sidecar.js";
import type {
  Balance,
  BuildOrderResult,
  CancelResult,
  FetchMyTradesParams,
  FetchOHLCVOptions,
  MarketClient,
  MarketMatch,
  MarketPrice,
  OrderBook,
  OrderParams,
  OrderResponse,
  Position,
  PriceCandle,
  PriceLevel,
  Trade,
  UserTrade,
} from "../client-market.js";

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

function mapLevel(l: { price: number; size: number }): PriceLevel {
  return { price: l.price, size: l.size };
}

/** `MarketClient` implementation backed by `pmxtjs.Polymarket`. */
export class PolymarketAdapter implements MarketClient {
  private client: Polymarket | undefined;

  private getClient(): Polymarket {
    if (!this.client) {
      const privateKey = process.env["POLYMARKET_PRIVATE_KEY"];
      const proxyAddress = process.env["POLYMARKET_PROXY_ADDRESS"];
      this.client = new Polymarket({
        ...(privateKey ? { privateKey } : {}),
        ...(proxyAddress ? { proxyAddress } : {}),
        autoStartServer: true,
      });
    }
    return this.client;
  }

  async searchMarkets(query: string): Promise<MarketMatch[]> {
    const poly = this.getClient();
    const markets = await poly.fetchMarkets({ query });
    const results: MarketMatch[] = [];

    for (const m of markets) {
      // Polymarket binary markets have exactly 2 outcomes — first is
      // affirmative, second is negative. Skip non-binary or markets
      // missing prices.
      if (m.outcomes.length !== 2) continue;
      const yesOutcome = m.outcomes[0];
      const noOutcome = m.outcomes[1];
      if (!yesOutcome || !noOutcome) continue;
      if (yesOutcome.price === undefined || noOutcome.price === undefined) {
        continue;
      }

      const resDate = m.resolutionDate?.toISOString();
      results.push({
        marketId: m.marketId,
        question: m.title,
        yesPrice: yesOutcome.price,
        noPrice: noOutcome.price,
        yesOutcomeId: yesOutcome.outcomeId,
        noOutcomeId: noOutcome.outcomeId,
        ...(resDate !== undefined ? { resolutionDate: resDate } : {}),
      });
    }

    return results;
  }

  async fetchMarketPrice(marketId: string): Promise<MarketPrice> {
    const poly = this.getClient();
    let markets = await poly.fetchMarkets({ query: marketId });
    let market = markets[0];

    // Text search may not match numeric marketIds; fall back to
    // fetching recent markets and filtering by ID.
    if (!market) {
      markets = await poly.fetchMarkets({ limit: 100 });
      market = markets.find((m) => String(m.marketId) === String(marketId));
    }

    if (!market) {
      throw new Error(`Market ${marketId} not found`);
    }

    if (market.outcomes.length !== 2) {
      throw new Error(
        `Market ${marketId} is not a binary market ` +
          `(${String(market.outcomes.length)} outcomes)`,
      );
    }

    const yesPrice = market.outcomes[0]?.price;
    const noPrice = market.outcomes[1]?.price;

    if (yesPrice === undefined || noPrice === undefined) {
      throw new Error(
        `Market ${marketId} missing outcome prices ` +
          `(yes=${String(yesPrice)}, no=${String(noPrice)})`,
      );
    }

    return {
      marketId: market.marketId,
      yesPrice,
      noPrice,
      timestamp: new Date(),
    };
  }

  async fetchOrderBook(outcomeId: string): Promise<OrderBook> {
    const poly = this.getClient();
    const book = await poly.fetchOrderBook(outcomeId);
    return {
      outcomeId,
      bids: book.bids.map(mapLevel),
      asks: book.asks.map(mapLevel),
    };
  }

  async fetchOHLCV(
    outcomeId: string,
    options?: FetchOHLCVOptions,
  ): Promise<PriceCandle[]> {
    const resolved = { resolution: options?.timeframe ?? "1h" };
    return callSidecar<PriceCandle[]>("fetchOHLCV", [outcomeId, resolved]);
  }

  async fetchPositions(): Promise<Position[]> {
    const poly = this.getClient();
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

  async fetchBalance(): Promise<Balance[]> {
    const poly = this.getClient();
    const balances = await poly.fetchBalance();
    return balances.map((b) => ({
      currency: b.currency,
      total: b.total,
      available: b.available,
      locked: b.locked,
    }));
  }

  async fetchMyTrades(params?: FetchMyTradesParams): Promise<UserTrade[]> {
    const poly = this.getClient();
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

  async fetchOpenOrders(marketId?: string): Promise<OrderResponse[]> {
    const poly = this.getClient();
    const orders = await poly.fetchOpenOrders(marketId);
    return orders.map(
      (o: {
        id: string;
        marketId: string;
        outcomeId: string;
        side: "buy" | "sell";
        type: "market" | "limit";
        amount: number;
        price?: number;
        status: string;
        filled: number;
        remaining: number;
      }): OrderResponse => ({
        id: o.id,
        marketId: o.marketId,
        outcomeId: o.outcomeId,
        side: o.side,
        type: o.type,
        amount: o.amount,
        price: o.price ?? 0,
        status: o.status,
        filled: o.filled,
        remaining: o.remaining,
      }),
    );
  }

  async createOrder(params: OrderParams): Promise<OrderResponse> {
    validateOrderParams(params);
    const privateKey = process.env["POLYMARKET_PRIVATE_KEY"];
    if (!privateKey) throw new Error("POLYMARKET_PRIVATE_KEY required");
    const order = await callSidecar<{
      id: string;
      marketId: string;
      outcomeId: string;
      side: "buy" | "sell";
      type: "market" | "limit";
      amount: number;
      price?: number;
      status: string;
      filled: number;
      remaining: number;
    }>(
      "createOrder",
      [{
        marketId: params.marketId,
        outcomeId: params.outcomeId,
        side: params.side,
        type: params.orderType,
        amount: params.size,
        price: params.price,
      }],
      { privateKey, signatureType: "eoa" },
    );
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

  async cancelOrder(orderId: string): Promise<CancelResult> {
    const privateKey = process.env["POLYMARKET_PRIVATE_KEY"];
    if (!privateKey) throw new Error("POLYMARKET_PRIVATE_KEY required");
    const order = await callSidecar<{ id?: string; status?: string }>(
      "cancelOrder",
      [orderId],
      { privateKey, signatureType: "eoa" },
    );
    return {
      id: order.id ?? orderId,
      status: order.status ?? "cancelled",
    };
  }

  async buildOrder(params: OrderParams): Promise<BuildOrderResult> {
    validateOrderParams(params);
    const privateKey = process.env["POLYMARKET_PRIVATE_KEY"];
    if (!privateKey) throw new Error("POLYMARKET_PRIVATE_KEY required");
    const built = await callSidecar<{
      exchange: string;
      params: {
        marketId: string;
        outcomeId: string;
        side: string;
        type: string;
        amount: number;
        price?: number;
      };
      signedOrder?: Record<string, unknown>;
      raw: unknown;
    }>(
      "buildOrder",
      [{
        marketId: params.marketId,
        outcomeId: params.outcomeId,
        side: params.side,
        type: params.orderType,
        amount: params.size,
        price: params.price,
      }],
      { privateKey, signatureType: "eoa" },
    );
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

  async watchOrderBook(outcomeId: string): Promise<OrderBook> {
    const snap = await callSidecar<{
      bids: PriceLevel[];
      asks: PriceLevel[];
      timestamp: number | null;
    }>("watchOrderBook", [outcomeId]);
    return {
      outcomeId,
      bids: snap.bids.map(mapLevel),
      asks: snap.asks.map(mapLevel),
      timestamp: snap.timestamp,
    };
  }

  async watchTrades(outcomeId: string): Promise<Trade[]> {
    return callSidecar<Trade[]>("watchTrades", [outcomeId]);
  }
}
