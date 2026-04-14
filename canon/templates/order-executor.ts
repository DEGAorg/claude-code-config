/**
 * Order executor — converts TradeSignal → Polymarket order,
 * submits via client, and tracks lifecycle until terminal state.
 *
 * Stub: type exports and function signatures define the TDD contract.
 * Item 6 replaces the throw bodies with real implementations.
 */

import type { TradeSignal } from "./types/TradeSignal.js";
import type { OrderParams, OrderResponse } from "./client-polymarket.js";

/** Token IDs for the YES and NO outcomes of a binary market. */
export interface TokenIds {
  yes: string;
  no: string;
}

/** Configuration for order lifecycle tracking. */
export interface OrderExecutorConfig {
  /** Milliseconds between status polls (default: 5000). */
  pollIntervalMs: number;
  /** Maximum milliseconds to wait before declaring timeout (default: 60000). */
  timeoutMs: number;
}

/** Result of submitting an order. */
export interface SubmitResult {
  orderId: string;
  marketId: string;
  side: "buy" | "sell";
  size: number;
  price: number;
  status: string;
  filled: number;
  remaining: number;
  submittedAt: Date;
}

/** Result of tracking an order to a terminal state. */
export interface TrackResult {
  orderId: string;
  status: "filled" | "cancelled" | "timeout";
  filled: number;
  remaining: number;
}

/**
 * Convert a TradeSignal into OrderParams for the Polymarket client.
 *
 * Direction mapping:
 * - buy_yes  → side: "buy",  tokenId: tokenIds.yes
 * - buy_no   → side: "buy",  tokenId: tokenIds.no
 * - sell_yes → side: "sell", tokenId: tokenIds.yes
 * - sell_no  → side: "sell", tokenId: tokenIds.no
 *
 * Urgency mapping:
 * - "immediate"     → orderType: "market"
 * - "normal"        → orderType: "limit"
 * - "opportunistic" → orderType: "limit"
 *
 * Validates: price in [0, 1], size > 0.
 */
export function signalToOrderParams(
  _signal: TradeSignal,
  _tokenIds: TokenIds,
  _price: number,
): OrderParams {
  throw new Error("Not implemented — see plan item 6");
}

/**
 * Submit an order derived from a TradeSignal.
 *
 * Converts the signal via signalToOrderParams, then calls createOrder
 * from the Polymarket client.
 */
export async function submitOrder(
  _signal: TradeSignal,
  _tokenIds: TokenIds,
  _price: number,
): Promise<SubmitResult> {
  throw new Error("Not implemented — see plan item 6");
}

/**
 * Track an order's lifecycle by polling until a terminal state.
 *
 * Terminal states: "filled", "cancelled".
 * Returns "timeout" status if the order does not reach a terminal state
 * within config.timeoutMs milliseconds.
 *
 * @param orderId - The order ID to track.
 * @param fetchStatus - Callback to poll current order state.
 * @param config - Optional polling configuration.
 */
export async function trackOrder(
  _orderId: string,
  _fetchStatus: (orderId: string) => Promise<OrderResponse>,
  _config?: Partial<OrderExecutorConfig>,
): Promise<TrackResult> {
  throw new Error("Not implemented — see plan item 6");
}
