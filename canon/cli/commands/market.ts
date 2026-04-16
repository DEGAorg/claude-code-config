/**
 * Market subcommand — search markets, fetch prices, orderbooks, OHLCV.
 *
 * All operations are read-only and require no authentication.
 *
 * Usage:
 *   canon-cli market search <query>
 *   canon-cli market price <condition-id>
 *   canon-cli market orderbook <token-id>
 *   canon-cli market ohlcv <token-id> [--timeframe <tf>]
 */

import { stripFormatFlags, writeError, writeSuccess } from "../output.js";

/** Extract a named flag value from args (e.g. --timeframe 1h). */
function getFlag(
  args: readonly string[],
  name: string,
): string | undefined {
  const idx = args.indexOf(name);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

async function handleSearch(rawArgs: readonly string[]): Promise<void> {
  const args = stripFormatFlags(rawArgs);
  const query = args.join(" ");

  if (!query) {
    writeError(
      "Missing search query. Usage:\n" +
        '  canon-cli market search <query>\n\n' +
        'Example: canon-cli market search "bitcoin"',
      rawArgs,
    );
    return;
  }

  try {
    const { searchMarkets } = await import(
      "canon-templates/client-polymarket.js"
    );
    const markets = await searchMarkets(query);
    writeSuccess(markets, rawArgs);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rawArgs,
    );
  }
}

async function handlePrice(rawArgs: readonly string[]): Promise<void> {
  const args = stripFormatFlags(rawArgs);
  const conditionId = args[0];

  if (!conditionId) {
    writeError(
      "Missing condition ID. Usage:\n" +
        "  canon-cli market price <condition-id>",
      rawArgs,
    );
    return;
  }

  try {
    const { fetchMarketPrice } = await import(
      "canon-templates/client-polymarket.js"
    );
    const price = await fetchMarketPrice(conditionId);
    writeSuccess(price, rawArgs);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rawArgs,
    );
  }
}

async function handleOrderbook(
  rawArgs: readonly string[],
): Promise<void> {
  const args = stripFormatFlags(rawArgs);
  const tokenId = args[0];

  if (!tokenId) {
    writeError(
      "Missing token ID. Usage:\n" +
        "  canon-cli market orderbook <token-id>",
      rawArgs,
    );
    return;
  }

  try {
    const { fetchOrderBook } = await import(
      "canon-templates/client-polymarket.js"
    );
    const book = await fetchOrderBook(tokenId);
    writeSuccess(book, rawArgs);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rawArgs,
    );
  }
}

async function handleOhlcv(rawArgs: readonly string[]): Promise<void> {
  const args = stripFormatFlags(rawArgs);
  const tokenId = args[0];

  if (!tokenId) {
    writeError(
      "Missing token ID. Usage:\n" +
        "  canon-cli market ohlcv <token-id> [--timeframe <tf>]",
      rawArgs,
    );
    return;
  }

  const timeframe = getFlag(args, "--timeframe");

  try {
    const { fetchOHLCV } = await import(
      "canon-templates/client-polymarket.js"
    );
    const candles = await fetchOHLCV(
      tokenId,
      timeframe ? { timeframe } : undefined,
    );
    writeSuccess(candles, rawArgs);
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
  search: handleSearch,
  price: handlePrice,
  orderbook: handleOrderbook,
  ohlcv: handleOhlcv,
};

export async function run(args: string[]): Promise<void> {
  const subcommand = args[0];

  if (!subcommand || !(subcommand in SUBCOMMANDS)) {
    writeError(
      `Unknown market subcommand "${subcommand ?? ""}". ` +
        "Available: search, price, orderbook, ohlcv",
      args,
    );
    return;
  }

  const handler = SUBCOMMANDS[subcommand];
  if (handler) {
    await handler(args.slice(1));
  }
}
