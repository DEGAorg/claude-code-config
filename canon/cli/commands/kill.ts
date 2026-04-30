/**
 * Kill subcommand — cancel all open orders (kill switch).
 *
 * Requires WALLET_PRIVATE_KEY. Without --yes, performs a dry run
 * showing open orders. With --yes, cancels them all.
 *
 * Usage:
 *   canon-cli kill [--yes]
 */

import { AuthError, requireAuth } from "../auth.js";
import { stripFormatFlags, writeError, writeSuccess } from "../output.js";

export async function run(args: string[]): Promise<void> {
  try {
    requireAuth("kill");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, args);
      return;
    }
    throw err;
  }

  const cleanArgs = stripFormatFlags(args);
  const confirmed =
    cleanArgs.includes("--yes") || cleanArgs.includes("-y");

  try {
    const { fetchOpenOrders } = await import(
      "canon-templates/client-polymarket.js"
    );
    const openOrders = await fetchOpenOrders();

    if (openOrders.length === 0) {
      writeSuccess(
        { cancelled: [], failed: [], message: "No open orders" },
        args,
      );
      return;
    }

    if (!confirmed) {
      writeSuccess(
        {
          dryRun: true,
          orderCount: openOrders.length,
          orders: openOrders,
          message:
            `Found ${String(openOrders.length)} open order(s). ` +
            "Re-run with --yes to cancel all.",
        },
        args,
      );
      return;
    }

    const { cancelAllOrders } = await import(
      "canon-templates/kill-switch.js"
    );
    const orderIds = openOrders.map(
      (o: { id: string }) => o.id,
    );
    const result = await cancelAllOrders(orderIds);

    writeSuccess(result, args);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      args,
    );
  }
}
