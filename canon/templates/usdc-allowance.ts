/**
 * USDC allowance adapter for the Polymarket CTFExchange.
 *
 * Concrete `AllowanceClient` implementation backed by an ethers v5
 * provider + signer. Reads the current ERC-20 allowance the connected
 * wallet has granted to the exchange spender, and submits an
 * `approve()` transaction when the live executor's threshold check
 * decides a top-up is needed.
 *
 * STATUS: interface + factory shape only. The on-chain calls are
 * intentionally unimplemented and throw `AllowanceNotImplementedError`
 * until the wallet/provider plumbing is wired through to the templates
 * layer (currently lives in `canon/cli/wallet-store.ts`). See
 * `docs/reviews/261-open-questions.md` Q-3.
 */
import type { AllowanceClient } from "./live-executor.js";

/** Ethers-v5-style provider/signer surface needed by the adapter. */
export interface UsdcAllowanceConfig {
  /** Wallet address (the allowance owner). */
  ownerAddress: string;
  /** Spender that the allowance is granted to (Polymarket CTFExchange). */
  spenderAddress: string;
  /** USDC.e contract address on Polygon. */
  usdcAddress: string;
  /**
   * Hook that returns the configured wallet/signer used to send
   * `approve()` transactions. Kept abstract to avoid coupling the
   * templates layer to a concrete wallet store at import time.
   */
  getSigner: () => Promise<unknown>;
  /**
   * Hook that returns a read-only provider for `allowance(...)` calls.
   */
  getProvider: () => Promise<unknown>;
}

export class AllowanceNotImplementedError extends Error {
  constructor(operation: string) {
    super(
      `USDC allowance adapter is not yet wired (${operation}). ` +
        "See docs/reviews/261-open-questions.md (Q-3).",
    );
    this.name = "AllowanceNotImplementedError";
  }
}

/**
 * Build a USDC allowance adapter for the live executor.
 *
 * The returned `AllowanceClient` will, once implemented:
 *   - `getAllowance()` → call USDC `allowance(owner, spender)` via the
 *     provider and return the raw 6-decimal `bigint`.
 *   - `approve(amount)` → submit an `approve(spender, amount)` tx
 *     using the signer, await one confirmation, return `{ txHash }`.
 *
 * Until then it throws `AllowanceNotImplementedError` so the absence
 * of real wiring is loud rather than silent.
 */
export function createUsdcAllowanceClient(
  config: UsdcAllowanceConfig,
): AllowanceClient {
  void config;
  return {
    async getAllowance(): Promise<bigint> {
      throw new AllowanceNotImplementedError("getAllowance");
    },
    async approve(_amount: bigint): Promise<{ txHash: string }> {
      void _amount;
      throw new AllowanceNotImplementedError("approve");
    },
  };
}
