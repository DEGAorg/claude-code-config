/**
 * Process-env accessors for canon's wallet variables.
 *
 * Canonical names (as of #268) are market-agnostic:
 *
 *   WALLET_PRIVATE_KEY    — hex private key for the canon Polygon EOA
 *   WALLET_PROXY_ADDRESS  — proxy / EOA address (allowance owner)
 *
 * Legacy names from earlier releases (`POLYMARKET_PRIVATE_KEY`,
 * `POLYMARKET_PROXY_ADDRESS`) are still honoured. Reading a legacy
 * value emits a one-shot stderr warning so callers know to migrate.
 */

const WALLET_KEY_VARS = {
  modern: "WALLET_PRIVATE_KEY",
  legacy: "POLYMARKET_PRIVATE_KEY",
} as const;

const WALLET_PROXY_VARS = {
  modern: "WALLET_PROXY_ADDRESS",
  legacy: "POLYMARKET_PROXY_ADDRESS",
} as const;

const warned = new Set<string>();

function read(modern: string, legacy: string): string | undefined {
  const m = process.env[modern];
  if (m !== undefined && m.length > 0) return m;
  const l = process.env[legacy];
  if (l !== undefined && l.length > 0) {
    if (!warned.has(legacy)) {
      warned.add(legacy);
      process.stderr.write(
        `[canon] env ${legacy} is deprecated; export ${modern} instead ` +
          `(legacy fallback will be removed in a future release).\n`,
      );
    }
    return l;
  }
  return undefined;
}

/** Return the configured wallet private key, or undefined. */
export function getWalletPrivateKey(): string | undefined {
  return read(WALLET_KEY_VARS.modern, WALLET_KEY_VARS.legacy);
}

/** Return the configured wallet proxy / owner address, or undefined. */
export function getWalletProxyAddress(): string | undefined {
  return read(WALLET_PROXY_VARS.modern, WALLET_PROXY_VARS.legacy);
}

/** Reset the deprecation warning cache (test helper only). */
export function _resetEnvWarningsForTests(): void {
  warned.clear();
}
