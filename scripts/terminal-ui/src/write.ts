import { readFile, rename, writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { dirname, join } from "node:path";
import {
  LOG_BUFFER_MAX,
  type LogEntry,
  type TerminalUIState,
  type TerminalUIStateUpdate,
} from "./types.js";

function isNodeError(err: unknown): err is NodeJS.ErrnoException {
  return err instanceof Error && "code" in err;
}

function createDefault(): TerminalUIState {
  const now = new Date().toISOString();
  return {
    phase: "init",
    status: "idle",
    startedAt: now,
    updatedAt: now,
    logs: [],
    error: null,
    metrics: {},
  };
}

/** Read state from disk. Returns null when the file does not exist. */
export async function readState(
  filePath: string,
): Promise<TerminalUIState | null> {
  try {
    const raw = await readFile(filePath, "utf-8");
    return JSON.parse(raw) as TerminalUIState;
  } catch (err: unknown) {
    if (isNodeError(err) && err.code === "ENOENT") {
      return null;
    }
    throw err;
  }
}

/**
 * Atomic state write with log ring buffer.
 *
 * Reads current state (or creates default), merges the update,
 * appends new log entries, and atomically renames into place.
 */
export async function writeState(
  filePath: string,
  update: TerminalUIStateUpdate,
): Promise<void> {
  const current = (await readState(filePath)) ?? createDefault();

  // Append logs and enforce ring buffer cap
  let logs: readonly LogEntry[] = current.logs;
  if (update.appendLogs !== undefined && update.appendLogs.length > 0) {
    const all = [...current.logs, ...update.appendLogs];
    logs = all.slice(-LOG_BUFFER_MAX);
  }

  // Shallow-merge metrics so callers add keys without replacing all
  const metrics: Readonly<Record<string, unknown>> =
    "metrics" in update
      ? { ...current.metrics, ...update.metrics }
      : current.metrics;

  const next: TerminalUIState = {
    phase: update.phase ?? current.phase,
    status: update.status ?? current.status,
    startedAt: update.startedAt ?? current.startedAt,
    error: "error" in update ? (update.error ?? null) : current.error,
    updatedAt: new Date().toISOString(),
    logs,
    metrics,
  };

  // Atomic write: temp file in same directory → rename
  const tmp = join(
    dirname(filePath),
    `.tmp-${randomBytes(8).toString("hex")}`,
  );
  await writeFile(tmp, JSON.stringify(next, null, 2) + "\n", "utf-8");
  await rename(tmp, filePath);
}
