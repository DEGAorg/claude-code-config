/**
 * Live position manager — wraps the Polymarket client to produce a
 * Portfolio snapshot consumable by the runner's RiskInterface.
 *
 * Reused by ARB-01 (live executor) and future MINT-01, MINT-05, ARB-02
 * strategies.
 */

import {
  fetchBalance,
  fetchOpenOrders,
  fetchPositions,
  type OrderResponse,
  type Position as ClientPosition,
} from "./client-polymarket.js";
import type { Portfolio, Position } from "./types/RiskInterface.js";

export interface PositionDeps {
  reconcile(): Promise<Portfolio>;
  getPortfolio(): Portfolio;
  getOpenOrders(): OrderResponse[];
}

const LABEL_TO_DIRECTION: Record<string, Position["direction"]> = {
  Yes: "buy_yes",
  No: "buy_no",
};

function emptyPortfolio(): Portfolio {
  return { total_value: 0, positions: [], daily_pnl: 0 };
}

function mapPosition(p: ClientPosition): Position {
  return {
    market_id: p.marketId,
    direction: LABEL_TO_DIRECTION[p.outcomeLabel] ?? "buy_yes",
    size: p.size,
    entry_price: p.entryPrice,
    opened_at: new Date(),
  };
}

export function createLivePositions(): PositionDeps {
  let snapshot: Portfolio = emptyPortfolio();
  let openOrders: OrderResponse[] = [];

  async function reconcile(): Promise<Portfolio> {
    const [balances, clientPositions, orders] = await Promise.all([
      fetchBalance(),
      fetchPositions(),
      fetchOpenOrders(),
    ]);

    const cash = balances
      .filter((b) => b.currency === "USDC")
      .reduce((acc, b) => acc + b.available, 0);

    const markValue = clientPositions.reduce(
      (acc, p) => acc + p.size * p.currentPrice,
      0,
    );

    const dailyPnl = clientPositions.reduce(
      (acc, p) => acc + p.unrealizedPnL,
      0,
    );

    snapshot = {
      positions: clientPositions.map(mapPosition),
      total_value: cash + markValue,
      daily_pnl: dailyPnl,
    };
    openOrders = orders;
    return snapshot;
  }

  return {
    reconcile,
    getPortfolio: () => snapshot,
    getOpenOrders: () => openOrders,
  };
}
