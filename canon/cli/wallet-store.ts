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

const KEY_NAME = "POLYMARKET_PRIVATE_KEY";

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

  /** Return the private key from disk, or undefined if not present/parseable. */
  private readKey(): string | undefined {
    if (!existsSync(this.path)) return undefined;
    const text = readFileSync(this.path, "utf8");
    for (const raw of text.split("\n")) {
      const line = raw.trim();
      if (!line || line.startsWith("#")) continue;
      const eq = line.indexOf("=");
      if (eq === -1) continue;
      const name = line.slice(0, eq).trim();
      const value = line.slice(eq + 1).trim();
      if (name === KEY_NAME && value.length > 0) return value;
    }
    return undefined;
  }
}
