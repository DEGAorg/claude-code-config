/**
 * Wallet storage abstraction.
 *
 * v1 ships a single file-backed implementation that persists the
 * private key in `.canon/wallet.env` (mode 0600) under the project
 * root. The `WalletStore` interface is the seam we will use later to
 * swap in macOS Keychain / libsecret / hardware-wallet backends
 * without touching callers.
 */

import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";

export interface WalletStore {
  hasWallet(): boolean;
  getPrivateKey(): string;
  getAddress(): Promise<string>;
  ensure(): Promise<EnsureResult>;
}

export interface EnsureResult {
  address: string;
  /** True when this call generated a new wallet; false when one already existed. */
  created: boolean;
}

export class WalletNotFoundError extends Error {
  constructor() {
    super(
      "No wallet found. Run 'canon-cli wallet ensure' to generate one.",
    );
    this.name = "WalletNotFoundError";
  }
}

/** Canonical line key written to `.canon/wallet.env` for new wallets. */
const KEY_NAME = "WALLET_PRIVATE_KEY";
/** Legacy line key kept readable for back-compat with older wallets. */
const LEGACY_KEY_NAME = "POLYMARKET_PRIVATE_KEY";

/**
 * Project-local wallet store backed by `.canon/wallet.env`.
 *
 * @param rootDir Project root; defaults to `process.cwd()`.
 */
export class FileWalletStore implements WalletStore {
  private readonly path: string;

  constructor(rootDir: string = process.cwd()) {
    this.path = join(rootDir, ".canon", "wallet.env");
  }

  hasWallet(): boolean {
    if (!existsSync(this.path)) return false;
    return this.readKey() !== undefined;
  }

  getPrivateKey(): string {
    const key = this.readKey();
    if (!key) throw new WalletNotFoundError();
    return key;
  }

  async getAddress(): Promise<string> {
    const key = this.getPrivateKey();
    const { Wallet } = await import("ethers");
    return new Wallet(key).address;
  }

  async ensure(): Promise<EnsureResult> {
    if (this.hasWallet()) {
      return { address: await this.getAddress(), created: false };
    }
    const { Wallet } = await import("ethers");
    const wallet = Wallet.createRandom();
    mkdirSync(dirname(this.path), { recursive: true });
    writeFileSync(
      this.path,
      `# canon wallet v1 — project-local burner. Fund with USDC.e on Polygon.\n${KEY_NAME}=${wallet.privateKey}\n`,
      { mode: 0o600 },
    );
    return { address: wallet.address, created: true };
  }

  /**
   * Return the private key from disk, or undefined if not present/parseable.
   *
   * Prefers the canonical `WALLET_PRIVATE_KEY` line. Falls back to the
   * legacy `POLYMARKET_PRIVATE_KEY` for wallets created before #268,
   * with a one-shot stderr warning so users know to migrate.
   */
  private readKey(): string | undefined {
    if (!existsSync(this.path)) return undefined;
    const text = readFileSync(this.path, "utf8");
    let modern: string | undefined;
    let legacy: string | undefined;
    for (const raw of text.split("\n")) {
      const line = raw.trim();
      if (!line || line.startsWith("#")) continue;
      const eq = line.indexOf("=");
      if (eq === -1) continue;
      const name = line.slice(0, eq).trim();
      const value = line.slice(eq + 1).trim();
      if (value.length === 0) continue;
      if (name === KEY_NAME) modern = value;
      else if (name === LEGACY_KEY_NAME) legacy = value;
    }
    if (modern !== undefined) return modern;
    if (legacy !== undefined) {
      warnLegacyKeyOnce(this.path);
      return legacy;
    }
    return undefined;
  }
}

let legacyKeyWarned = false;
function warnLegacyKeyOnce(path: string): void {
  if (legacyKeyWarned) return;
  legacyKeyWarned = true;
  process.stderr.write(
    `[canon] ${path}: ${LEGACY_KEY_NAME} is deprecated; ` +
      `rename the line to ${KEY_NAME} (back-compat will be dropped in a future release).\n`,
  );
}

/** Reset the legacy-key warning latch (test helper only). */
export function _resetLegacyKeyWarningForTests(): void {
  legacyKeyWarned = false;
}
