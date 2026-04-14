/**
 * Balance subcommand — fetch wallet balance.
 *
 * Requires POLYMARKET_PRIVATE_KEY.
 *
 * Usage:
 *   canon-cli balance [--pretty]
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
    const { fetchBalance } = await import(
      "canon-templates/client-polymarket.js"
    );
    const balances = await fetchBalance();
    writeSuccess(balances, args);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      args,
    );
  }
}
