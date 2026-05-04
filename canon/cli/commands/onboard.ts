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
import { FileWalletStore } from "../wallet-store.js";
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

interface VenueExecuteOptions {
  /** Run the gasless permit-chain to move EOA's USDC into the Safe. */
  fund?: boolean;
  /**
   * Cap for `ensureFunded()` in 6-decimal USDC base units. Defaults to
   * the EOA's full balance.
   */
  fundAmountBaseUnits?: bigint;
}

const COLLATERAL_BASE_UNITS_PER_USDC = 1_000_000n;

async function runVenueExecute(
  rawArgs: readonly string[],
  pk: string,
  venue: string,
  opts: VenueExecuteOptions = {},
): Promise<void> {
  try {
    // Builder creds must exist BEFORE we build the adapter — its
    // RelayClient picks them up from `process.env` once at construction.
    // Without them every relayer call answers 401 and ensureFunder fails.
    if (venue === "polymarket") {
      await ensureBuilderCreds(pk);
    }
    const adapter = await loadAdapter(venue);
    const client = adapter.build(pk);
    const funder = await client.ensureFunder();
    const status = await client.status();
    persistFunderAddress(venue, status.funderAddress);
    const approvals = await client.ensureApprovals();
    const creds = await client.ensureCreds();
    const funded = opts.fund
      ? await client.ensureFunded(opts.fundAmountBaseUnits)
      : undefined;
    const finalStatus = opts.fund ? await client.status() : status;
    writeSuccess(
      {
        venue: adapter.venue,
        chainId: adapter.chainId,
        funder,
        approvals,
        ...(funded
          ? {
              funded: {
                funded: funded.funded,
                amount: funded.amount.toString(),
                expectedOut: funded.expectedOut.toString(),
                ...(funded.txHash ? { txHash: funded.txHash } : {}),
              },
            }
          : {}),
        // Don't echo the secret to stdout; expose only the readiness flag.
        credsReady: !!(creds.key && creds.secret && creds.passphrase),
        status: {
          funderAddress: finalStatus.funderAddress,
          funderDeployed: finalStatus.funderDeployed,
          approvalsReady: finalStatus.approvalsReady,
          credsReady: finalStatus.credsReady,
          fundedCollateral: finalStatus.fundedCollateral,
        },
      },
      rawArgs,
    );
  } catch (err: unknown) {
    writeError(err instanceof Error ? err.message : String(err), rawArgs);
  }
}

/**
 * Persist the funder address (Polymarket Safe) to the wallet store and
 * `process.env` so subsequent canon calls — `client-polymarket.ts`
 * `tradingCredentials()` reads `WALLET_PROXY_ADDRESS` to route orders
 * through the Safe — pick it up without manual config. Only written
 * after the funder is confirmed deployed by `ensureFunder()`.
 */
function persistFunderAddress(venue: string, funderAddress: string): void {
  if (venue !== "polymarket") return;
  if (!funderAddress || !/^0x[0-9a-fA-F]{40}$/.test(funderAddress)) return;
  const store = new FileWalletStore();
  store.setEnv("WALLET_PROXY_ADDRESS", funderAddress);
  process.env["WALLET_PROXY_ADDRESS"] = funderAddress;
}

/**
 * Bootstrap Polymarket builder credentials when missing.
 *
 * Polymarket's relayer requires authenticated builder headers on every
 * mutative Safe call. The CLOB exposes `createBuilderApiKey()` for
 * programmatic provisioning — call it once on the user's first
 * `--execute` and persist the resulting creds to the wallet store so
 * subsequent runs (and `client-polymarket.ts`) pick them up from
 * `process.env`. No-op when all three env vars are already populated.
 */
async function ensureBuilderCreds(pk: string): Promise<void> {
  if (
    process.env["POLYMARKET_BUILDER_API_KEY"] &&
    process.env["POLYMARKET_BUILDER_SECRET"] &&
    process.env["POLYMARKET_BUILDER_PASSPHRASE"]
  ) {
    return;
  }
  const mod = (await import(
    "canon-templates/polymarket-onboard.js"
  )) as {
    bootstrapBuilderCreds: (pk: string) => Promise<{
      key: string;
      secret: string;
      passphrase: string;
    }>;
  };
  const creds = await mod.bootstrapBuilderCreds(pk);
  const store = new FileWalletStore();
  store.setEnv("POLYMARKET_BUILDER_API_KEY", creds.key);
  store.setEnv("POLYMARKET_BUILDER_SECRET", creds.secret);
  store.setEnv("POLYMARKET_BUILDER_PASSPHRASE", creds.passphrase);
  process.env["POLYMARKET_BUILDER_API_KEY"] = creds.key;
  process.env["POLYMARKET_BUILDER_SECRET"] = creds.secret;
  process.env["POLYMARKET_BUILDER_PASSPHRASE"] = creds.passphrase;
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

  // Venue mode: triggered by --status, --venue, or --fund. Default venue
  // is polymarket. The `--fund` flag opts in to the gasless permit chain
  // that pulls native USDC from the EOA into the Safe; without it,
  // `--execute` only handles deploy/approvals/creds.
  const fund = args.includes("--fund");
  if (status || venueArg !== undefined || fund) {
    const venue = venueArg ?? "polymarket";
    if (status) {
      await runVenueStatus(rawArgs, pk, venue);
      return;
    }
    if (execute) {
      const opts: VenueExecuteOptions = { fund };
      if (fund && amountArg !== undefined) {
        const usdc = Number(amountArg);
        if (!Number.isFinite(usdc) || usdc <= 0) {
          writeError(
            `Invalid --amount "${amountArg}": must be a positive USDC amount`,
            rawArgs,
          );
          return;
        }
        opts.fundAmountBaseUnits =
          BigInt(Math.round(usdc * Number(COLLATERAL_BASE_UNITS_PER_USDC)));
      }
      await runVenueExecute(rawArgs, pk, venue, opts);
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
