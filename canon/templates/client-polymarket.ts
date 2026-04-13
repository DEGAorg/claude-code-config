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
