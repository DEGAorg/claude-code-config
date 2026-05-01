/**
 * Wallet store contract — local mirror of `canon/cli/wallet-store.ts`.
 *
 * The templates layer must not import from `canon/cli` at compile time
 * (the package's `tsconfig.json` enforces `rootDir: "."`). Strategies
 * declare the WalletStore shape they need here and accept it via
 * dependency injection. The bootstrap (a strategy's `entry.ts`) is the
 * single place that dynamically imports `canon/cli/wallet-store.js` at
 * runtime to instantiate the concrete `FileWalletStore`.
 *
 * Keeping the interface in lock-step with `canon/cli/wallet-store.ts`
 * is enforced by ducktype: any value satisfying this interface is
 * accepted, and the canon-cli `FileWalletStore` happens to satisfy it.
 */

export interface WalletStore {
  /** True when the underlying store has a usable wallet. */
  hasWallet(): boolean;
  /** Return the raw private key (hex). Throws when no wallet exists. */
  getPrivateKey(): string;
  /** Return the wallet's checksummed address. */
  getAddress(): Promise<string>;
}
