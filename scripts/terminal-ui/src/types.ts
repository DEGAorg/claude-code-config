/**
 * Terminal UI state file schema.
 *
 * Source of truth for the JSON blackboard that the Ink dashboard watches.
 * Writers (shell, TS, Python) produce this shape; the dashboard consumes it.
 */

export type Status =
  | "running"
  | "automating"
  | "executing"
  | "paused"
  | "idle"
  | "complete"
  | "error";

export type LogLevel = "info" | "warn" | "error" | "debug";

/** Single structured log entry (aligns with log-server.py events). */
export interface LogEntry {
  /** ISO 8601 timestamp. */
  readonly ts: string;
  /** Severity level. */
  readonly level: LogLevel;
  /** Human-readable message. */
  readonly msg: string;
}

/**
 * Core terminal UI state.
 *
 * Generic base shape — Canon and Ralph Loop extend via `metrics`
 * without modifying Core.
 */
export interface TerminalUIState {
  /** Current pipeline phase (e.g., "init", "scaffold", "run"). */
  readonly phase: string;
  /** Session status. */
  readonly status: Status;
  /** ISO 8601 — when the session started. */
  readonly startedAt: string;
  /** ISO 8601 — last state write timestamp. */
  readonly updatedAt: string;
  /** Recent log entries (ring buffer, max 50). */
  readonly logs: readonly LogEntry[];
  /** Error message when status is "error", null otherwise. */
  readonly error: string | null;
  /** Domain-specific key-value pairs. Dashboard renders all keys it finds. */
  readonly metrics: Readonly<Record<string, unknown>>;
}

/** Fields accepted by the atomic writer for partial updates. */
export type TerminalUIStateUpdate = Partial<
  Omit<TerminalUIState, "logs" | "updatedAt">
> & {
  /** New log entries to append (writer caps the buffer at 50). */
  readonly appendLogs?: readonly LogEntry[];
};

/** Max entries retained in the logs ring buffer. */
export const LOG_BUFFER_MAX = 50;
