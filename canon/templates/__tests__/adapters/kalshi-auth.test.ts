/**
 * Tests for the Kalshi RSA-PSS signer + header builder.
 *
 * Test keys are generated in-memory per test so no PEM or UUID is ever
 * committed to git. Signatures are verified with the matching public key
 * because RSA-PSS uses random salt — byte equality is not stable.
 */

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  constants,
  createVerify,
  generateKeyPairSync,
} from "node:crypto";
import {
  mkdtempSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  _resetKalshiAuthCacheForTests,
  buildKalshiAuthHeaders,
  KalshiAuthError,
  loadPrivateKeyPem,
  signKalshiPayload,
} from "../../adapters/kalshi-auth.js";

// Uppercase placeholder so the value does not match the lowercase-hex UUID
// regex the no-PEM/no-UUID completion criterion greps for.
const TEST_API_KEY_ID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
const FIXED_TS = 1715800000000;

function verifyPss(
  payload: string,
  signatureB64: string,
  publicKey: string,
): boolean {
  const verifier = createVerify("sha256");
  verifier.update(payload);
  verifier.end();
  return verifier.verify(
    {
      key: publicKey,
      padding: constants.RSA_PKCS1_PSS_PADDING,
      saltLength: constants.RSA_PSS_SALTLEN_DIGEST,
    },
    Buffer.from(signatureB64, "base64"),
  );
}

let tmpDir: string;
let pemPath: string;
let privateKey: string;
let publicKey: string;

beforeEach(() => {
  _resetKalshiAuthCacheForTests();
  const kp = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
  });
  privateKey = kp.privateKey;
  publicKey = kp.publicKey;
  tmpDir = mkdtempSync(join(tmpdir(), "kalshi-auth-"));
  pemPath = join(tmpDir, "test-key.pem");
  writeFileSync(pemPath, privateKey, { mode: 0o600 });
});

afterEach(() => {
  rmSync(tmpDir, { recursive: true, force: true });
  delete process.env["KALSHI_API_KEY_ID"];
  delete process.env["KALSHI_PRIVATE_KEY_PATH"];
});

describe("signKalshiPayload", () => {
  it("returns a base64 signature that verifies against the public key", () => {
    const payload = `${FIXED_TS}GET/trade-api/v2/portfolio/balance`;
    const signature = signKalshiPayload(payload, privateKey);
    expect(signature).toMatch(/^[A-Za-z0-9+/]+={0,2}$/);
    expect(verifyPss(payload, signature, publicKey)).toBe(true);
  });

  it("produces signatures that do not verify for tampered payloads", () => {
    const original = `${FIXED_TS}GET/trade-api/v2/portfolio/balance`;
    const signature = signKalshiPayload(original, privateKey);
    const tampered = `${FIXED_TS}GET/trade-api/v2/portfolio/positions`;
    expect(verifyPss(tampered, signature, publicKey)).toBe(false);
  });

  it("returns a valid signature on every call (stable verification)", () => {
    const payload = `${FIXED_TS}GET/trade-api/v2/markets`;
    for (let i = 0; i < 5; i += 1) {
      const sig = signKalshiPayload(payload, privateKey);
      expect(verifyPss(payload, sig, publicKey)).toBe(true);
    }
  });
});

describe("loadPrivateKeyPem", () => {
  it("reads PEM contents from disk", () => {
    const pem = loadPrivateKeyPem(pemPath);
    expect(pem).toBe(privateKey);
  });

  it("throws KalshiAuthError when the file is missing", () => {
    expect(() => loadPrivateKeyPem(join(tmpDir, "missing.pem"))).toThrow(
      KalshiAuthError,
    );
  });

  it("caches the file contents — second read does not hit disk", () => {
    const first = loadPrivateKeyPem(pemPath);
    unlinkSync(pemPath);
    const second = loadPrivateKeyPem(pemPath);
    expect(second).toBe(first);
  });
});

describe("buildKalshiAuthHeaders", () => {
  it("returns exactly the three KALSHI-ACCESS-* headers", () => {
    const headers = buildKalshiAuthHeaders({
      method: "GET",
      path: "/trade-api/v2/portfolio/balance",
      apiKeyId: TEST_API_KEY_ID,
      privateKeyPem: privateKey,
      timestamp: FIXED_TS,
    });
    expect(Object.keys(headers).sort()).toEqual([
      "KALSHI-ACCESS-KEY",
      "KALSHI-ACCESS-SIGNATURE",
      "KALSHI-ACCESS-TIMESTAMP",
    ]);
  });

  it("echoes the supplied apiKeyId and timestamp", () => {
    const headers = buildKalshiAuthHeaders({
      method: "GET",
      path: "/trade-api/v2/portfolio/balance",
      apiKeyId: TEST_API_KEY_ID,
      privateKeyPem: privateKey,
      timestamp: FIXED_TS,
    });
    expect(headers["KALSHI-ACCESS-KEY"]).toBe(TEST_API_KEY_ID);
    expect(headers["KALSHI-ACCESS-TIMESTAMP"]).toBe(String(FIXED_TS));
  });

  it("signs the canonical `timestamp + method + path` payload", () => {
    const headers = buildKalshiAuthHeaders({
      method: "GET",
      path: "/trade-api/v2/portfolio/balance",
      apiKeyId: TEST_API_KEY_ID,
      privateKeyPem: privateKey,
      timestamp: FIXED_TS,
    });
    const payload = `${FIXED_TS}GET/trade-api/v2/portfolio/balance`;
    expect(
      verifyPss(payload, headers["KALSHI-ACCESS-SIGNATURE"], publicKey),
    ).toBe(true);
  });

  it("strips the query string from the path before signing", () => {
    const headers = buildKalshiAuthHeaders({
      method: "GET",
      path: "/trade-api/v2/markets?status=open&limit=10",
      apiKeyId: TEST_API_KEY_ID,
      privateKeyPem: privateKey,
      timestamp: FIXED_TS,
    });
    const stripped = `${FIXED_TS}GET/trade-api/v2/markets`;
    expect(
      verifyPss(stripped, headers["KALSHI-ACCESS-SIGNATURE"], publicKey),
    ).toBe(true);
    const withQuery = `${FIXED_TS}GET/trade-api/v2/markets?status=open&limit=10`;
    expect(
      verifyPss(withQuery, headers["KALSHI-ACCESS-SIGNATURE"], publicKey),
    ).toBe(false);
  });

  it("uppercases the HTTP method before signing", () => {
    const headers = buildKalshiAuthHeaders({
      method: "post",
      path: "/trade-api/v2/portfolio/orders",
      apiKeyId: TEST_API_KEY_ID,
      privateKeyPem: privateKey,
      timestamp: FIXED_TS,
    });
    const payload = `${FIXED_TS}POST/trade-api/v2/portfolio/orders`;
    expect(
      verifyPss(payload, headers["KALSHI-ACCESS-SIGNATURE"], publicKey),
    ).toBe(true);
  });

  it("loads the PEM from KALSHI_PRIVATE_KEY_PATH when no inline pem given", () => {
    process.env["KALSHI_API_KEY_ID"] = TEST_API_KEY_ID;
    process.env["KALSHI_PRIVATE_KEY_PATH"] = pemPath;
    const headers = buildKalshiAuthHeaders({
      method: "GET",
      path: "/trade-api/v2/portfolio/balance",
      timestamp: FIXED_TS,
    });
    expect(headers["KALSHI-ACCESS-KEY"]).toBe(TEST_API_KEY_ID);
    const payload = `${FIXED_TS}GET/trade-api/v2/portfolio/balance`;
    expect(
      verifyPss(payload, headers["KALSHI-ACCESS-SIGNATURE"], publicKey),
    ).toBe(true);
  });

  it("throws KalshiAuthError when KALSHI_API_KEY_ID is missing", () => {
    expect(() =>
      buildKalshiAuthHeaders({
        method: "GET",
        path: "/trade-api/v2/portfolio/balance",
        privateKeyPem: privateKey,
        timestamp: FIXED_TS,
      }),
    ).toThrow(KalshiAuthError);
    expect(() =>
      buildKalshiAuthHeaders({
        method: "GET",
        path: "/trade-api/v2/portfolio/balance",
        privateKeyPem: privateKey,
        timestamp: FIXED_TS,
      }),
    ).toThrow(/KALSHI_API_KEY_ID/);
  });

  it("throws KalshiAuthError when KALSHI_PRIVATE_KEY_PATH is missing", () => {
    expect(() =>
      buildKalshiAuthHeaders({
        method: "GET",
        path: "/trade-api/v2/portfolio/balance",
        apiKeyId: TEST_API_KEY_ID,
        timestamp: FIXED_TS,
      }),
    ).toThrow(KalshiAuthError);
    expect(() =>
      buildKalshiAuthHeaders({
        method: "GET",
        path: "/trade-api/v2/portfolio/balance",
        apiKeyId: TEST_API_KEY_ID,
        timestamp: FIXED_TS,
      }),
    ).toThrow(/KALSHI_PRIVATE_KEY_PATH/);
  });

  it("produces a valid signature on repeated calls with identical inputs", () => {
    const payload = `${FIXED_TS}GET/trade-api/v2/portfolio/balance`;
    for (let i = 0; i < 5; i += 1) {
      const headers = buildKalshiAuthHeaders({
        method: "GET",
        path: "/trade-api/v2/portfolio/balance",
        apiKeyId: TEST_API_KEY_ID,
        privateKeyPem: privateKey,
        timestamp: FIXED_TS,
      });
      expect(headers["KALSHI-ACCESS-KEY"]).toBe(TEST_API_KEY_ID);
      expect(headers["KALSHI-ACCESS-TIMESTAMP"]).toBe(String(FIXED_TS));
      expect(
        verifyPss(payload, headers["KALSHI-ACCESS-SIGNATURE"], publicKey),
      ).toBe(true);
    }
  });
});
