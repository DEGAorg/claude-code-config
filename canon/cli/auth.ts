/**
 * Auth module — reads POLYMARKET_PRIVATE_KEY from the environment.
 *
 * Write commands call requireAuth() before executing. Read-only
 * commands skip auth entirely.
 */

/** Error thrown when auth is required but the key is missing. */
export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}

/**
 * Read the Polymarket private key from the environment.
 *
 * Returns the key string, or undefined if not set.
 */
export function getPrivateKey(): string | undefined {
  return process.env["POLYMARKET_PRIVATE_KEY"];
}

/**
 * Require auth for a write command.
 *
 * Throws AuthError with a clear, actionable message if
 * POLYMARKET_PRIVATE_KEY is not set. Call this at the top of
 * any command handler that needs authentication.
 *
 * @param command - The command name (for error messages).
 */
export function requireAuth(command: string): string {
  const key = getPrivateKey();
  if (!key) {
    throw new AuthError(
      `Command "${command}" requires authentication.\n` +
        "\n" +
        "Set the POLYMARKET_PRIVATE_KEY environment variable:\n" +
        "\n" +
        "  export POLYMARKET_PRIVATE_KEY=<your-private-key>\n" +
        "\n" +
        "Read-only commands (market search, help) work without auth.",
    );
  }
  return key;
}
