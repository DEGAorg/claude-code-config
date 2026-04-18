/**
 * Direct HTTP helper for the pmxt sidecar.
 *
 * Bypasses the pmxtjs SDK to work around the header-clobbering bug
 * in the generated OpenAPI client (pmxtjs v2.22.1).
 * Affected methods: fetchOHLCV, watchOrderBook, watchTrades.
 */

import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

/** Shape of ~/.pmxt/server.lock written by the pmxt-core sidecar. */
export interface SidecarLockData {
  port: number;
  pid: number;
  accessToken: string;
}

/** The pmxt sidecar is not running (lock file missing or unreadable). */
export class SidecarNotRunningError extends Error {
  constructor(cause: unknown) {
    super(
      "pmxt sidecar is not running — lock file not found at ~/.pmxt/server.lock",
      { cause },
    );
    this.name = "SidecarNotRunningError";
  }
}

/** The sidecar returned a non-OK HTTP response. */
export class SidecarRequestError extends Error {
  readonly status: number;
  readonly method: string;

  constructor(method: string, status: number, body: string) {
    super(`Sidecar ${method} failed (${String(status)}): ${body}`);
    this.name = "SidecarRequestError";
    this.status = status;
    this.method = method;
  }
}

async function readLockFile(): Promise<SidecarLockData> {
  const lockPath = join(homedir(), ".pmxt", "server.lock");

  let raw: string;
  try {
    raw = await readFile(lockPath, "utf-8");
  } catch (err: unknown) {
    throw new SidecarNotRunningError(err);
  }

  const data: unknown = JSON.parse(raw);

  if (
    typeof data !== "object" ||
    data === null ||
    typeof (data as Record<string, unknown>)["port"] !== "number" ||
    typeof (data as Record<string, unknown>)["accessToken"] !== "string"
  ) {
    throw new Error(
      "Invalid sidecar lock file: missing port or accessToken",
    );
  }

  return data as SidecarLockData;
}

/**
 * Call a pmxt sidecar HTTP endpoint directly.
 *
 * Reads the lock file at ~/.pmxt/server.lock, POSTs to the sidecar,
 * and returns the parsed JSON response.
 *
 * @param method - Sidecar API method name (e.g. "fetchOHLCV").
 * @param args - Arguments forwarded to the sidecar method.
 */
export async function callSidecar<T>(
  method: string,
  args: ReadonlyArray<unknown>,
  credentials?: { privateKey: string; signatureType?: string },
): Promise<T> {
  const lock = await readLockFile();

  const url = `http://localhost:${String(lock.port)}/api/polymarket/${method}`;
  const body: Record<string, unknown> = { args };
  if (credentials) body["credentials"] = credentials;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-pmxt-access-token": lock.accessToken,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new SidecarRequestError(method, response.status, body);
  }

  const json = (await response.json()) as Record<string, unknown>;

  // The sidecar wraps responses in { success, data }; unwrap if present.
  const result: unknown =
    json["success"] !== undefined ? json["data"] : json;
  return result as T;
}
