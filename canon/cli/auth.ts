/**
 * Auth module — resolves the wallet private key.
 *
 * Resolution order:
 *   1. `WALLET_PRIVATE_KEY` env var (legacy `POLYMARKET_PRIVATE_KEY`
 *      still honoured with a deprecation warning).
 *   2. Project-local wallet store (`.canon/wallet.env`).
 *
 * Write commands call `requireAuth()` before executing. Read-only
 * commands skip auth entirely.
 */

import { getWalletPrivateKey } from "./env.js";
import { FileWalletStore, WalletNotFoundError } from "./wallet-store.js";

export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}

/** Synchronous env lookup; returns the raw env var or undefined. */
export function getPrivateKey(): string | undefined {
  return getWalletPrivateKey();
}

/**
 * Require auth for a write command.
 *
 * Returns the private key from the env or the project-local wallet
 * store. Throws `AuthError` with an actionable message if neither is
 * configured.
 *
 * @param command - The command name (for error messages).
 */
export function requireAuth(command: string): string {
  const fromEnv = getPrivateKey();
  if (fromEnv) return fromEnv;

  const store = new FileWalletStore();
  try {
    return store.getPrivateKey();
  } catch (err: unknown) {
    if (err instanceof WalletNotFoundError) {
      throw new AuthError(
        `Command "${command}" requires authentication.\n` +
          "\n" +
          "No wallet is configured. Options:\n" +
          "\n" +
          "  1. Generate a project-local burner:\n" +
          "       canon-cli wallet ensure\n" +
          "\n" +
          "  2. Or set the env var (CI / existing wallet):\n" +
          "       export WALLET_PRIVATE_KEY=<your-private-key>\n" +
          "\n" +
          "Read-only commands (market search, help) work without auth.",
      );
    }
    throw err;
  }
}
