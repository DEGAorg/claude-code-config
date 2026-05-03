/**
 * Onboard subcommand — two modes share one entry point.
 *
 * Venue mode (new): drives the venue-onboarding chain via a
 * `MarketVenueOnboard` adapter (Polymarket today). Triggered by
 * `--status` or `--venue`. Reads PK from the wallet store (or env).
 *
 *   canon-cli onboard --status [--venue polymarket]
 *       Read-only snapshot — funder, approvals, creds, collateral.
 *   canon-cli onboard --execute [--venue polymarket]
 *       Idempotent: ensureFunder → ensureApprovals → ensureCreds.
 *
 * Asset-swap mode (legacy): scans on-chain balances and swaps
 * non-USDC.e tradeable assets to USDC.e. Triggered when neither
 * `--status` nor `--venue` is present.
 *
 *   canon-cli onboard              Show swap plan (no execution)
 *   canon-cli onboard --execute    Run the planned swaps
 *   canon-cli onboard --asset <USDC|USDT|POL> --amount <n> --execute
 *                                  Swap a specific asset/amount.
 *
 * POL swaps always reserve gas (default: 1 POL, override with
 * ONBOARD_POL_GAS_RESERVE env var).
 */

import { requireAuth, AuthError } from "../auth.js";
import { stripFormatFlags, writeError, writeSuccess } from "../output.js";
import type { MarketVenueOnboard } from "canon-templates/types/MarketVenueOnboard.js";

type SwapSource = "USDC" | "USDT" | "POL";
const ASSETS: readonly SwapSource[] = ["USDC", "USDT", "POL"];

interface Step {
  from: SwapSource;
  amount: number;
  reason: string;
}

/**
 * Lazy adapter loaders so the CLI doesn't pay venue-import cost
 * on legacy swap flows (and so a broken adapter doesn't break the
 * whole `onboard` subcommand).
 */
const VENUE_ADAPTERS: Record<string, () => Promise<MarketVenueOnboard>> = {
  polymarket: async () => {
    const mod = (await import(
      "canon-templates/polymarket-onboard.js"
    )) as { polymarketOnboard: MarketVenueOnboard };
    return mod.polymarketOnboard;
  },
};

const SUPPORTED_VENUES = Object.keys(VENUE_ADAPTERS).join(", ");

function getFlag(args: readonly string[], name: string): string | undefined {
  const idx = args.indexOf(name);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

function isSwapSource(s: string | undefined): s is SwapSource {
  return s !== undefined && (ASSETS as readonly string[]).includes(s);
}

async function loadAdapter(
  venue: string,
): Promise<MarketVenueOnboard> {
  const loader = VENUE_ADAPTERS[venue];
  if (!loader) {
    throw new Error(
      `Unknown --venue "${venue}": supported venues are ${SUPPORTED_VENUES}`,
    );
  }
  return loader();
}

async function runVenueStatus(
  rawArgs: readonly string[],
  pk: string,
  venue: string,
): Promise<void> {
  try {
    const adapter = await loadAdapter(venue);
    const client = adapter.build(pk);
    const status = await client.status();
    writeSuccess(
      {
        venue: adapter.venue,
        chainId: adapter.chainId,
        funderAddress: status.funderAddress,
        funderDeployed: status.funderDeployed,
        approvalsReady: status.approvalsReady,
        credsReady: status.credsReady,
        fundedCollateral: status.fundedCollateral,
      },
      rawArgs,
    );
  } catch (err: unknown) {
    writeError(err instanceof Error ? err.message : String(err), rawArgs);
  }
}

async function runVenueExecute(
  rawArgs: readonly string[],
  pk: string,
  venue: string,
): Promise<void> {
  try {
    const adapter = await loadAdapter(venue);
    const client = adapter.build(pk);
    const funder = await client.ensureFunder();
    const approvals = await client.ensureApprovals();
    const creds = await client.ensureCreds();
    const status = await client.status();
    writeSuccess(
      {
        venue: adapter.venue,
        chainId: adapter.chainId,
        funder,
        approvals,
        // Don't echo the secret to stdout; expose only the readiness flag.
        credsReady: !!(creds.key && creds.secret && creds.passphrase),
        status: {
          funderAddress: status.funderAddress,
          funderDeployed: status.funderDeployed,
          approvalsReady: status.approvalsReady,
          credsReady: status.credsReady,
          fundedCollateral: status.fundedCollateral,
        },
      },
      rawArgs,
    );
  } catch (err: unknown) {
    writeError(err instanceof Error ? err.message : String(err), rawArgs);
  }
}

export async function run(rawArgs: string[]): Promise<void> {
  let pk: string;
  try {
    pk = requireAuth("onboard");
  } catch (err: unknown) {
    if (err instanceof AuthError) {
      writeError(err.message, rawArgs);
      return;
    }
    throw err;
  }

  const args = stripFormatFlags(rawArgs);
  const status = args.includes("--status");
  const execute = args.includes("--execute");
  const venueArg = getFlag(args, "--venue");
  const assetArg = getFlag(args, "--asset");
  const amountArg = getFlag(args, "--amount");

  // Venue mode: triggered by --status or --venue. Default venue is polymarket.
  if (status || venueArg !== undefined) {
    const venue = venueArg ?? "polymarket";
    if (status) {
      await runVenueStatus(rawArgs, pk, venue);
      return;
    }
    if (execute) {
      await runVenueExecute(rawArgs, pk, venue);
      return;
    }
    // --venue alone (no --status / --execute): default to read-only status.
    await runVenueStatus(rawArgs, pk, venue);
    return;
  }

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
