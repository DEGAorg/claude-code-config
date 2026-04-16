import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { AuthError, getPrivateKey, requireAuth } from "../auth.js";

describe("getPrivateKey", () => {
  let originalKey: string | undefined;

  beforeEach(() => {
    originalKey = process.env["POLYMARKET_PRIVATE_KEY"];
  });

  afterEach(() => {
    if (originalKey === undefined) {
      delete process.env["POLYMARKET_PRIVATE_KEY"];
    } else {
      process.env["POLYMARKET_PRIVATE_KEY"] = originalKey;
    }
  });

  it("returns the key when set", () => {
    process.env["POLYMARKET_PRIVATE_KEY"] = "0xabc123";
    expect(getPrivateKey()).toBe("0xabc123");
  });

  it("returns undefined when not set", () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];
    expect(getPrivateKey()).toBeUndefined();
  });
});

describe("requireAuth", () => {
  let originalKey: string | undefined;

  beforeEach(() => {
    originalKey = process.env["POLYMARKET_PRIVATE_KEY"];
  });

  afterEach(() => {
    if (originalKey === undefined) {
      delete process.env["POLYMARKET_PRIVATE_KEY"];
    } else {
      process.env["POLYMARKET_PRIVATE_KEY"] = originalKey;
    }
  });

  it("returns the key when set", () => {
    process.env["POLYMARKET_PRIVATE_KEY"] = "0xdef456";
    expect(requireAuth("position list")).toBe("0xdef456");
  });

  it("throws AuthError when key is missing", () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];
    expect(() => requireAuth("position list")).toThrow(AuthError);
  });

  it("includes command name in error message", () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];
    expect(() => requireAuth("position list")).toThrow(
      /position list/,
    );
  });

  it("includes instructions to set the env var", () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];
    expect(() => requireAuth("order create")).toThrow(
      /POLYMARKET_PRIVATE_KEY/,
    );
  });

  it("mentions read-only commands work without auth", () => {
    delete process.env["POLYMARKET_PRIVATE_KEY"];
    expect(() => requireAuth("balance")).toThrow(
      /Read-only commands/,
    );
  });
});

describe("AuthError", () => {
  it("is an instance of Error", () => {
    const err = new AuthError("test");
    expect(err).toBeInstanceOf(Error);
  });

  it("has name AuthError", () => {
    const err = new AuthError("test");
    expect(err.name).toBe("AuthError");
  });
});
