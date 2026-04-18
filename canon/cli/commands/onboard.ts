/**
 * Onboard subcommand — scan on-chain balances, swap non-USDC.e
 * assets to USDC.e so the user can start trading.
 *
 * Requires POLYMARKET_PRIVATE_KEY.
 *
 * Usage:
 *   canon-cli onboard              Show plan (no swaps executed)
 *   canon-cli onboard --execute    Execute the plan: swap all non-USDC.e
 *                                  tradeable assets to USDC.e.
 *   canon-cli onboard --asset <USDC|USDT|POL> --amount <n> --execute
 *                                  Swap a specific asset/amount.
 *
 * POL swaps always reserve gas (default: 1 POL, override with
 * ONBOARD_POL_GAS_RESERVE env var).
 */

import { requireAuth, AuthError } from "../auth.js";
import { stripFormatFlags, writeError, writeSuccess } from "../output.js";

type SwapSource = "USDC" | "USDT" | "POL";
const ASSETS: readonly SwapSource[] = ["USDC", "USDT", "POL"];

interface Step {
  from: SwapSource;
  amount: number;
  reason: string;
}

function getFlag(args: readonly string[], name: string): string | undefined {
  const idx = args.indexOf(name);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

function isSwapSource(s: string | undefined): s is SwapSource {
  return s !== undefined && (ASSETS as readonly string[]).includes(s);
}

export async function run(rawArgs: string[]): Promise<void> {
  try {
    requireAuth("onboard");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, rawArgs);
      return;
    }
    throw err;
  }

  const args = stripFormatFlags(rawArgs);
  const execute = args.includes("--execute");
  const assetArg = getFlag(args, "--asset");
  const amountArg = getFlag(args, "--amount");

  if ((assetArg === undefined) !== (amountArg === undefined)) {
    writeError(
      "--asset and --amount must be provided together",
      rawArgs,
    );
    return;
  }

  if (assetArg !== undefined && !isSwapSource(assetArg)) {
    writeError(
      `Invalid --asset "${assetArg}": must be one of USDC, USDT, POL`,
      rawArgs,
    );
    return;
  }

  try {
    const { fetchOnChainBalances, swapToUsdce } = await import(
      "canon-templates/client-polymarket.js"
    );

    // Single-asset mode: swap exactly what the user asked for.
    if (assetArg !== undefined && amountArg !== undefined) {
      const amount = Number(amountArg);
      if (!Number.isFinite(amount) || amount <= 0) {
        writeError(
          `Invalid --amount "${amountArg}": must be a positive number`,
          rawArgs,
        );
        return;
      }
      if (!execute) {
        writeSuccess(
          {
            plan: [
              { from: assetArg, amount, reason: "explicit --asset/--amount" },
            ],
            executed: false,
          },
          rawArgs,
        );
        return;
      }
      const result = await swapToUsdce(assetArg, amount);
      writeSuccess({ executed: true, swaps: [result] }, rawArgs);
      return;
    }

    // Auto-plan mode: build plan from on-chain balances.
    const balances = await fetchOnChainBalances();
    const byCurrency = new Map(balances.map((b) => [b.currency, b.amount]));

    const polReserve = Number(
      process.env["ONBOARD_POL_GAS_RESERVE"] ?? "1",
    );
    const plan: Step[] = [];

    const usdcNative = byCurrency.get("USDC") ?? 0;
    if (usdcNative > 0) {
      plan.push({
        from: "USDC",
        amount: usdcNative,
        reason: "native USDC is not accepted by Polymarket CLOB",
      });
    }
    const usdt = byCurrency.get("USDT") ?? 0;
    if (usdt > 0) {
      plan.push({
        from: "USDT",
        amount: usdt,
        reason: "USDT is not accepted by Polymarket CLOB",
      });
    }
    const pol = byCurrency.get("POL") ?? 0;
    if (pol > polReserve + 1) {
      plan.push({
        from: "POL",
        amount: pol - polReserve,
        reason: `POL excess (keeping ${String(polReserve)} for gas)`,
      });
    }

    if (plan.length === 0) {
      writeSuccess(
        {
          plan: [],
          executed: execute,
          note: "nothing to swap — USDC.e is already the tradeable balance",
        },
        rawArgs,
      );
      return;
    }

    if (!execute) {
      writeSuccess(
        {
          plan,
          executed: false,
          note: "run with --execute to swap these on-chain",
        },
        rawArgs,
      );
      return;
    }

    const swaps = [];
    for (const step of plan) {
      const result = await swapToUsdce(step.from, step.amount);
      swaps.push(result);
    }
    writeSuccess({ executed: true, swaps }, rawArgs);
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rawArgs,
    );
  }
}
