/**
 * Order subcommand — create, cancel, and list trades.
 *
 * All operations require POLYMARKET_PRIVATE_KEY.
 *
 * Usage:
 *   canon-cli order create --token-id <id> --side <buy|sell> --size <n> --price <n> [--type <market|limit>] [--market-id <id>]
 *   canon-cli order cancel <order-id>
 *   canon-cli order list [--market-id <id>] [--limit <n>]
 */

import { requireAuth, AuthError } from "../auth.js";
import { stripFormatFlags, writeError, writeSuccess } from "../output.js";

/** Extract a named flag value from args (e.g. --side buy). */
function getFlag(args: readonly string[], name: string): string | undefined {
  const idx = args.indexOf(name);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

async function handleCreate(rawArgs: readonly string[]): Promise<void> {
  try {
    requireAuth("order create");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, rawArgs);
      return;
    }
    throw err;
  }

  const args = stripFormatFlags(rawArgs);

  const tokenId = getFlag(args, "--token-id");
  const side = getFlag(args, "--side");
  const sizeStr = getFlag(args, "--size");
  const priceStr = getFlag(args, "--price");
  const orderType = getFlag(args, "--type") ?? "limit";
  const marketId = getFlag(args, "--market-id") ?? "";

  if (!tokenId || !side || !sizeStr || !priceStr) {
    writeError(
      "Missing required flags. Usage:\n" +
        "  canon-cli order create --token-id <id> --side <buy|sell> " +
        "--size <n> --price <n> [--type <market|limit>] [--market-id <id>]",
      rawArgs,
    );
    return;
  }

  if (side !== "buy" && side !== "sell") {
    writeError(
      `Invalid --side "${side}": must be "buy" or "sell"`,
      rawArgs,
    );
    return;
  }

  if (orderType !== "market" && orderType !== "limit") {
    writeError(
      `Invalid --type "${orderType}": must be "market" or "limit"`,
      rawArgs,
    );
    return;
  }

  const size = Number(sizeStr);
  const price = Number(priceStr);

  if (Number.isNaN(size) || size <= 0) {
    writeError(
      `Invalid --size "${sizeStr}": must be a positive number`,
      rawArgs,
    );
    return;
  }

  if (Number.isNaN(price) || price < 0 || price > 1) {
    writeError(
      `Invalid --price "${priceStr}": must be between 0 and 1`,
      rawArgs,
    );
    return;
  }

  try {
    const { createOrder } = await import("canon-templates/client-polymarket.js");
    const result = await createOrder({
      marketId,
      tokenId,
      side,
      size,
      price,
      orderType,
    });
    writeSuccess(result, rawArgs);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rawArgs,
    );
  }
}

async function handleCancel(rawArgs: readonly string[]): Promise<void> {
  try {
    requireAuth("order cancel");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, rawArgs);
      return;
    }
    throw err;
  }

  const args = stripFormatFlags(rawArgs);
  const orderId = args[0];

  if (!orderId) {
    writeError(
      "Missing order ID. Usage:\n  canon-cli order cancel <order-id>",
      rawArgs,
    );
    return;
  }

  try {
    const { cancelOrder } = await import("canon-templates/client-polymarket.js");
    const result = await cancelOrder(orderId);
    writeSuccess(result, rawArgs);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rawArgs,
    );
  }
}

async function handleList(rawArgs: readonly string[]): Promise<void> {
  try {
    requireAuth("order list");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, rawArgs);
      return;
    }
    throw err;
  }

  const args = stripFormatFlags(rawArgs);

  const marketId = getFlag(args, "--market-id");
  const limitStr = getFlag(args, "--limit");
  const limit = limitStr ? Number(limitStr) : undefined;

  if (limitStr && (Number.isNaN(limit) || (limit !== undefined && limit <= 0))) {
    writeError(
      `Invalid --limit "${limitStr}": must be a positive number`,
      rawArgs,
    );
    return;
  }

  try {
    const { fetchMyTrades } = await import("canon-templates/client-polymarket.js");
    const trades = await fetchMyTrades({
      ...(marketId ? { marketId } : {}),
      ...(limit ? { limit } : {}),
    });
    writeSuccess(trades, rawArgs);
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
  create: handleCreate,
  cancel: handleCancel,
  list: handleList,
};

export async function run(args: string[]): Promise<void> {
  const subcommand = args[0];

  if (!subcommand || !(subcommand in SUBCOMMANDS)) {
    writeError(
      `Unknown order subcommand "${subcommand ?? ""}". ` +
        "Available: create, cancel, list",
      args,
    );
    return;
  }

  const handler = SUBCOMMANDS[subcommand];
  if (handler) {
    await handler(args.slice(1));
  }
}
