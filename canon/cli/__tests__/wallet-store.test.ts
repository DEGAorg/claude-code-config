import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync, statSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FileWalletStore } from "../wallet-store.js";

describe("FileWalletStore", () => {
  let root: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "canon-wallet-test-"));
  });

  afterEach(() => {
    rmSync(root, { recursive: true, force: true });
  });

  it("reports hasWallet=false when no file exists", async () => {
    const store = new FileWalletStore(root);
    expect(store.hasWallet()).toBe(false);
  });

  it("getAddress rejects when no wallet exists", async () => {
    const store = new FileWalletStore(root);
    await expect(store.getAddress()).rejects.toThrow(/no wallet/i);
  });

  it("getPrivateKey throws when no wallet exists", () => {
    const store = new FileWalletStore(root);
    expect(() => store.getPrivateKey()).toThrow(/no wallet/i);
  });

  it("ensure creates a wallet on first call and reports created=true", async () => {
    const store = new FileWalletStore(root);
    const result = await store.ensure();
    expect(result.created).toBe(true);
    expect(result.address).toMatch(/^0x[0-9a-fA-F]{40}$/);
    expect(store.hasWallet()).toBe(true);
  });

  it("persists the key in .canon/wallet.env", async () => {
    const store = new FileWalletStore(root);
    const { address } = await store.ensure();
    const path = join(root, ".canon", "wallet.env");
    const contents = readFileSync(path, "utf8");
    expect(contents).toMatch(/^POLYMARKET_PRIVATE_KEY=0x[0-9a-fA-F]{64}\n?$/m);
    expect(await store.getAddress()).toBe(address);
  });

  it("writes the wallet file with mode 0600", async () => {
    const store = new FileWalletStore(root);
    await store.ensure();
    const path = join(root, ".canon", "wallet.env");
    const mode = statSync(path).mode & 0o777;
    expect(mode).toBe(0o600);
  });

  it("ensure is idempotent — second call reports created=false and same address", async () => {
    const store = new FileWalletStore(root);
    const first = await store.ensure();
    const second = await store.ensure();
    expect(second.created).toBe(false);
    expect(second.address).toBe(first.address);
  });

  it("getPrivateKey returns the stored key", async () => {
    const store = new FileWalletStore(root);
    await store.ensure();
    expect(store.getPrivateKey()).toMatch(/^0x[0-9a-fA-F]{64}$/);
  });

  it("reads a pre-existing wallet file", async () => {
    mkdirSync(join(root, ".canon"), { recursive: true });
    const key = "0x" + "a".repeat(64);
    writeFileSync(
      join(root, ".canon", "wallet.env"),
      `POLYMARKET_PRIVATE_KEY=${key}\n`,
      { mode: 0o600 },
    );
    const store = new FileWalletStore(root);
    expect(store.hasWallet()).toBe(true);
    expect(store.getPrivateKey()).toBe(key);
    expect(await store.getAddress()).toMatch(/^0x[0-9a-fA-F]{40}$/);
  });

  it("tolerates comments and blank lines in wallet.env", () => {
    mkdirSync(join(root, ".canon"), { recursive: true });
    const key = "0x" + "b".repeat(64);
    writeFileSync(
      join(root, ".canon", "wallet.env"),
      `# canon wallet v1\n\nPOLYMARKET_PRIVATE_KEY=${key}\n`,
      { mode: 0o600 },
    );
    const store = new FileWalletStore(root);
    expect(store.getPrivateKey()).toBe(key);
  });
});
