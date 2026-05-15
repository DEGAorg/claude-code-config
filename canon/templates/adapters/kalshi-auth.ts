/**
 * Kalshi RSA-PSS request signer + auth header builder.
 *
 * Kalshi's REST API authenticates each request with three headers:
 *
 *   KALSHI-ACCESS-KEY        UUID identifying the API key
 *   KALSHI-ACCESS-TIMESTAMP  Milliseconds since epoch (string)
 *   KALSHI-ACCESS-SIGNATURE  base64(RSA-PSS(timestamp + METHOD + path))
 *
 * The signature payload concatenates the timestamp, the uppercase HTTP
 * method, and the request path (no query string, no host). The
 * signature uses RSA-PSS with SHA-256, MGF1-SHA-256, and a salt length
 * equal to the SHA-256 digest length (32 bytes).
 *
 * Credentials come from env vars: `KALSHI_API_KEY_ID` (UUID) and
 * `KALSHI_PRIVATE_KEY_PATH` (absolute filesystem path to a PEM-encoded
 * RSA private key). Either env var may be overridden per call via the
 * options bag — primarily for tests.
 */

import { constants, createSign } from "node:crypto";
import { readFileSync } from "node:fs";

/** Error thrown when Kalshi credentials are missing or malformed. */
export class KalshiAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "KalshiAuthError";
  }
}

/** The three headers Kalshi requires on every authenticated request. */
export interface KalshiAuthHeaders {
  "KALSHI-ACCESS-KEY": string;
  "KALSHI-ACCESS-TIMESTAMP": string;
  "KALSHI-ACCESS-SIGNATURE": string;
}

/** Inputs to {@link buildKalshiAuthHeaders}. */
export interface BuildKalshiAuthHeadersOptions {
  /** HTTP method (case-insensitive — uppercased before signing). */
  method: string;
  /** Request path; query string is stripped before signing. */
  path: string;
  /** Override `KALSHI_API_KEY_ID` from env. */
  apiKeyId?: string;
  /** Override `KALSHI_PRIVATE_KEY_PATH` from env. */
  privateKeyPath?: string;
  /** Inline PEM-encoded RSA private key. Skips PEM file load. */
  privateKeyPem?: string;
  /** Override `Date.now()` — primarily for tests. */
  timestamp?: number;
}

const pemCache = new Map<string, string>();

/**
 * Read a PEM-encoded RSA private key from disk, caching the file
 * contents per path so repeated auth calls don't re-read the file.
 */
export function loadPrivateKeyPem(path: string): string {
  const cached = pemCache.get(path);
  if (cached !== undefined) return cached;
  try {
    const pem = readFileSync(path, "utf8");
    pemCache.set(path, pem);
    return pem;
  } catch (err) {
    const cause = err instanceof Error ? err.message : String(err);
    throw new KalshiAuthError(
      `Failed to read Kalshi private key from ${path}: ${cause}`,
    );
  }
}

/** Clear the in-memory PEM cache. Test helper only. */
export function _resetKalshiAuthCacheForTests(): void {
  pemCache.clear();
}

/**
 * Sign `payload` with the given PEM-encoded RSA private key using
 * RSA-PSS / SHA-256 / saltLen=digestLen, returning a base64 signature.
 *
 * RSA-PSS uses a random salt by default, so the byte signature differs
 * across calls. Verification against the matching public key — not byte
 * equality — is the correct way to assert correctness.
 */
export function signKalshiPayload(payload: string, pem: string): string {
  const signer = createSign("sha256");
  signer.update(payload);
  signer.end();
  const signature = signer.sign({
    key: pem,
    padding: constants.RSA_PKCS1_PSS_PADDING,
    saltLength: constants.RSA_PSS_SALTLEN_DIGEST,
  });
  return signature.toString("base64");
}

/**
 * Build the `KALSHI-ACCESS-*` header trio for a single request.
 *
 * Resolves credentials in this order: explicit option → env var. Throws
 * {@link KalshiAuthError} when the API key ID or private key is missing.
 */
export function buildKalshiAuthHeaders(
  opts: BuildKalshiAuthHeadersOptions,
): KalshiAuthHeaders {
  const apiKeyId = opts.apiKeyId ?? process.env["KALSHI_API_KEY_ID"];
  if (!apiKeyId) {
    throw new KalshiAuthError(
      "KALSHI_API_KEY_ID is required for authenticated Kalshi requests",
    );
  }

  let pem = opts.privateKeyPem;
  if (pem === undefined) {
    const path = opts.privateKeyPath ?? process.env["KALSHI_PRIVATE_KEY_PATH"];
    if (!path) {
      throw new KalshiAuthError(
        "KALSHI_PRIVATE_KEY_PATH is required for authenticated Kalshi requests",
      );
    }
    pem = loadPrivateKeyPem(path);
  }

  const timestamp = opts.timestamp ?? Date.now();
  const timestampStr = String(timestamp);
  const pathOnly = opts.path.split("?")[0] ?? "";
  const method = opts.method.toUpperCase();

  const payload = `${timestampStr}${method}${pathOnly}`;
  const signature = signKalshiPayload(payload, pem);

  return {
    "KALSHI-ACCESS-KEY": apiKeyId,
    "KALSHI-ACCESS-TIMESTAMP": timestampStr,
    "KALSHI-ACCESS-SIGNATURE": signature,
  };
}
