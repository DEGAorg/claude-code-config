/**
 * Balance subcommand — fetch on-chain balances for the EOA on Polygon.
 *
 * Requires WALLET_PRIVATE_KEY.
 *
 * Usage:
 *   canon-cli balance [--pretty]
 *
 * Reports three assets:
 *   - USDC.e (bridged) — tradeable on Polymarket
 *   - USDC (native)    — needs swap to USDC.e (only shown if non-zero)
 *   - POL              — for gas
 */

import { requireAuth, AuthError } from "../auth.js";
import { writeError, writeSuccess } from "../output.js";

export async function run(args: string[]): Promise<void> {
  try {
    requireAuth("balance");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, args);
      return;
    }
    throw err;
  }

  try {
    const { fetchOnChainBalances } = await import(
      "canon-templates/client-polymarket.js"
    );
    const balances = await fetchOnChainBalances();
    writeSuccess(balances, args);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      args,
    );
  }
}
