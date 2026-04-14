/**
 * Kill switch — emergency cancellation of all open orders and
 * optional closure of all positions.
 *
 * Stub — implementation in item 10.
 */

import type { RiskInterface } from "./types/RiskInterface.js";

/** Result of cancelling all open orders. */
export interface CancelAllResult {
  /** Order IDs that were successfully cancelled. */
  cancelled: string[];
  /** Order IDs that failed to cancel after all retries. */
  failed: string[];
}

/** Result of closing all open positions. */
export interface CloseAllResult {
  /** Outcome token IDs for positions that were successfully closed. */
  closed: string[];
  /** Outcome token IDs for positions that failed to close. */
  failed: string[];
}

/** Combined result from activating the kill switch. */
export interface KillSwitchResult {
  cancelResult: CancelAllResult;
  closeResult: CloseAllResult | null;
  circuitBreakerTriggered: boolean;
}

/** Options for the kill switch activation. */
export interface KillSwitchOptions {
  /** Whether to also close all positions (default: false). */
  closePositions?: boolean | undefined;
  /** Reason for activating the kill switch. */
  reason?: string | undefined;
  /** Max retry attempts for failed cancellations (default: 3). */
  maxRetries?: number | undefined;
  /** Risk interface to notify via onCircuitBreaker. */
  riskInterface?: RiskInterface | undefined;
}

/**
 * Cancel all open orders by ID, with retry on failure.
 *
 * @param orderIds - IDs of open orders to cancel.
 * @param options - Retry configuration.
 */
export async function cancelAllOrders(
  _orderIds: string[],
  _options?: { maxRetries?: number | undefined } | undefined,
): Promise<CancelAllResult> {
  throw new Error("Not implemented — see item 10");
}

/**
 * Close all open positions via market sell orders.
 *
 * Fetches current positions from the Polymarket API and creates
 * market sell orders for each position with size > 0.
 */
export async function closeAllPositions(): Promise<CloseAllResult> {
  throw new Error("Not implemented — see item 10");
}

/**
 * Activate the kill switch: cancel all orders, optionally close
 * positions, and trigger circuit breaker on the risk interface.
 *
 * @param orderIds - IDs of open orders to cancel.
 * @param options - Kill switch configuration.
 */
export async function activateKillSwitch(
  _orderIds: string[],
  _options?: KillSwitchOptions | undefined,
): Promise<KillSwitchResult> {
  throw new Error("Not implemented — see item 10");
}
