/**
 * Position subcommand — list positions and calculate PnL.
 *
 * All operations require WALLET_PRIVATE_KEY.
 *
 * Usage:
 *   canon-cli position list [--pretty]
 */

import { requireAuth, AuthError } from "../auth.js";
import { stripFormatFlags, writeError, writeSuccess } from "../output.js";

/** Position with PnL data for CLI output. */
interface PositionEntry {
  marketId: string;
  outcomeId: string;
  outcomeLabel: string;
  size: number;
  entryPrice: number;
  currentPrice: number;
  unrealizedPnL: number;
}

/** Portfolio summary returned by `position list`. */
interface PositionListResult {
  positions: PositionEntry[];
  summary: {
    totalValue: number;
    dailyPnL: number;
    positionCount: number;
  };
}

async function handleList(rawArgs: readonly string[]): Promise<void> {
  try {
    requireAuth("position list");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, rawArgs);
      return;
    }
    throw err;
  }

  try {
    const { fetchPositions } = await import(
      "canon-templates/client-polymarket.js"
    );
    const { aggregatePortfolio } = await import(
      "canon-templates/position-manager.js"
    );

    const positions = await fetchPositions();
    const portfolio = aggregatePortfolio(positions);

    const entries: PositionEntry[] = positions.map((p) => ({
      marketId: p.marketId,
      outcomeId: p.outcomeId,
      outcomeLabel: p.outcomeLabel,
      size: p.size,
      entryPrice: p.entryPrice,
      currentPrice: p.currentPrice,
      unrealizedPnL: p.unrealizedPnL,
    }));

    const result: PositionListResult = {
      positions: entries,
      summary: {
        totalValue: portfolio.total_value,
        dailyPnL: portfolio.daily_pnl,
        positionCount: positions.length,
      },
    };

    writeSuccess(result, rawArgs);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rawArgs,
    );
  }
}

const SUBCOMMANDS: Record<
  string,
  (args: readonly string[]) => Promise<void>
> = {
  list: handleList,
};

export async function run(args: string[]): Promise<void> {
  const sub = stripFormatFlags(args)[0];

  if (!sub || !(sub in SUBCOMMANDS)) {
    writeError(
      `Unknown position subcommand "${sub ?? ""}". ` +
        "Available: list",
      args,
    );
    return;
  }

  const handler = SUBCOMMANDS[sub];
  if (handler) {
    await handler(args.slice(1));
  }
}
