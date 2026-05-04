import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync, statSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  FileWalletStore,
  _resetLegacyKeyWarningForTests,
} from "../wallet-store.js";

describe("FileWalletStore", () => {
  let root: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "canon-wallet-test-"));
    _resetLegacyKeyWarningForTests();
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

  it("persists the key in .canon/wallet.env using the modern key name", async () => {
    const store = new FileWalletStore(root);
    const { address } = await store.ensure();
    const path = join(root, ".canon", "wallet.env");
    const contents = readFileSync(path, "utf8");
    expect(contents).toMatch(/^WALLET_PRIVATE_KEY=0x[0-9a-fA-F]{64}\n?$/m);
    expect(contents).not.toMatch(/^POLYMARKET_PRIVATE_KEY=/m);
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

  it("reads a modern wallet file (WALLET_PRIVATE_KEY)", async () => {
    mkdirSync(join(root, ".canon"), { recursive: true });
    const key = "0x" + "a".repeat(64);
    writeFileSync(
      join(root, ".canon", "wallet.env"),
      `WALLET_PRIVATE_KEY=${key}\n`,
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
      `# canon wallet v1\n\nWALLET_PRIVATE_KEY=${key}\n`,
      { mode: 0o600 },
    );
    const store = new FileWalletStore(root);
    expect(store.getPrivateKey()).toBe(key);
  });

  // Back-compat: wallets created before #268 used POLYMARKET_PRIVATE_KEY.
  // The store must still read them, with a one-shot deprecation warning.
  it("reads a legacy wallet file (POLYMARKET_PRIVATE_KEY) and warns once", async () => {
    mkdirSync(join(root, ".canon"), { recursive: true });
    const key = "0x" + "c".repeat(64);
    writeFileSync(
      join(root, ".canon", "wallet.env"),
      `POLYMARKET_PRIVATE_KEY=${key}\n`,
      { mode: 0o600 },
    );

    const writes: string[] = [];
    const realWrite = process.stderr.write.bind(process.stderr);
    process.stderr.write = ((chunk: string | Uint8Array) => {
      writes.push(typeof chunk === "string" ? chunk : Buffer.from(chunk).toString());
      return true;
    }) as typeof process.stderr.write;

    try {
      const store = new FileWalletStore(root);
      expect(store.getPrivateKey()).toBe(key);
      // Second call must not emit a second warning.
      expect(store.getPrivateKey()).toBe(key);
    } finally {
      process.stderr.write = realWrite;
    }

    const merged = writes.join("");
    expect(merged).toMatch(/POLYMARKET_PRIVATE_KEY is deprecated/);
    const warnings = writes.filter((w) =>
      w.includes("POLYMARKET_PRIVATE_KEY is deprecated"),
    );
    expect(warnings.length).toBeLessThanOrEqual(1);
  });

  it("prefers the modern key when both are present in wallet.env", () => {
    mkdirSync(join(root, ".canon"), { recursive: true });
    const modern = "0x" + "d".repeat(64);
    const legacy = "0x" + "e".repeat(64);
    writeFileSync(
      join(root, ".canon", "wallet.env"),
      `POLYMARKET_PRIVATE_KEY=${legacy}\nWALLET_PRIVATE_KEY=${modern}\n`,
      { mode: 0o600 },
    );
    const store = new FileWalletStore(root);
    expect(store.getPrivateKey()).toBe(modern);
  });

  // -------------------------------------------------------------------------
  // setEnv / getEnv / loadEnvIntoProcess — generic env persistence used by
  // the onboard flow to remember `WALLET_PROXY_ADDRESS` and builder creds
  // across runs.
  // -------------------------------------------------------------------------

  describe("setEnv / getEnv", () => {
    it("setEnv creates wallet.env with mode 0600 when none exists", () => {
      const store = new FileWalletStore(root);
      store.setEnv("WALLET_PROXY_ADDRESS", "0xSafeAddress");

      const path = join(root, ".canon", "wallet.env");
      expect(readFileSync(path, "utf8")).toMatch(
        /^WALLET_PROXY_ADDRESS=0xSafeAddress\n?$/m,
      );
      expect(statSync(path).mode & 0o777).toBe(0o600);
      expect(store.getEnv("WALLET_PROXY_ADDRESS")).toBe("0xSafeAddress");
    });

    it("setEnv preserves the private key line when adding a second key", async () => {
      const store = new FileWalletStore(root);
      const { address } = await store.ensure();
      store.setEnv("WALLET_PROXY_ADDRESS", "0xSafe");

      expect(await store.getAddress()).toBe(address);
      expect(store.getEnv("WALLET_PROXY_ADDRESS")).toBe("0xSafe");
    });

    it("setEnv replaces an existing key in place rather than appending", () => {
      const store = new FileWalletStore(root);
      store.setEnv("WALLET_PROXY_ADDRESS", "0xOld");
      store.setEnv("WALLET_PROXY_ADDRESS", "0xNew");

      const path = join(root, ".canon", "wallet.env");
      const text = readFileSync(path, "utf8");
      const matches = text.match(/^WALLET_PROXY_ADDRESS=/gm);
      expect(matches?.length ?? 0).toBe(1);
      expect(store.getEnv("WALLET_PROXY_ADDRESS")).toBe("0xNew");
    });

    it("setEnv preserves comment lines when upserting", () => {
      mkdirSync(join(root, ".canon"), { recursive: true });
      writeFileSync(
        join(root, ".canon", "wallet.env"),
        `# canon wallet v1\nWALLET_PRIVATE_KEY=0x${"a".repeat(64)}\n`,
        { mode: 0o600 },
      );
      const store = new FileWalletStore(root);
      store.setEnv("WALLET_PROXY_ADDRESS", "0xSafe");

      const text = readFileSync(join(root, ".canon", "wallet.env"), "utf8");
      expect(text).toMatch(/^# canon wallet v1$/m);
      expect(text).toMatch(/^WALLET_PRIVATE_KEY=/m);
      expect(text).toMatch(/^WALLET_PROXY_ADDRESS=0xSafe$/m);
    });

    it("setEnv rejects invalid env names — guards against wallet.env corruption", () => {
      const store = new FileWalletStore(root);
      expect(() => store.setEnv("lowercase", "x")).toThrow(/invalid env name/i);
      expect(() => store.setEnv("HAS SPACE", "x")).toThrow(/invalid env name/i);
      expect(() => store.setEnv("STARTS_OK_WITH=", "x")).toThrow(
        /invalid env name/i,
      );
    });

    it("setEnv rejects values containing newlines", () => {
      const store = new FileWalletStore(root);
      expect(() => store.setEnv("FOO", "line1\nline2")).toThrow(/newline/i);
    });

    it("getEnv returns undefined for unknown keys", () => {
      const store = new FileWalletStore(root);
      expect(store.getEnv("NONEXISTENT")).toBeUndefined();
    });
  });

  describe("loadEnvIntoProcess", () => {
    it("loads persisted keys into process.env", () => {
      const store = new FileWalletStore(root);
      store.setEnv("WALLET_PROXY_ADDRESS", "0xSafeFromDisk");

      delete process.env["WALLET_PROXY_ADDRESS"];
      try {
        store.loadEnvIntoProcess();
        expect(process.env["WALLET_PROXY_ADDRESS"]).toBe("0xSafeFromDisk");
      } finally {
        delete process.env["WALLET_PROXY_ADDRESS"];
      }
    });

    it("does not override values already set in process.env — explicit shell exports win", () => {
      const store = new FileWalletStore(root);
      store.setEnv("WALLET_PROXY_ADDRESS", "0xFromDisk");

      const previous = process.env["WALLET_PROXY_ADDRESS"];
      process.env["WALLET_PROXY_ADDRESS"] = "0xFromShell";
      try {
        store.loadEnvIntoProcess();
        expect(process.env["WALLET_PROXY_ADDRESS"]).toBe("0xFromShell");
      } finally {
        if (previous === undefined) {
          delete process.env["WALLET_PROXY_ADDRESS"];
        } else {
          process.env["WALLET_PROXY_ADDRESS"] = previous;
        }
      }
    });

    it("is a no-op when wallet.env does not exist", () => {
      const store = new FileWalletStore(root);
      expect(() => store.loadEnvIntoProcess()).not.toThrow();
    });
  });
});
