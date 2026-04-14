/**
 * Strategy runner — configurable poll loop that integrates strategy
 * signal generation, risk checks, order execution, position management,
 * and structured execution logging.
 *
 * Stub: tests in __tests__/runner.test.ts define the contract.
 * Implementation: plan item 12.
 */

import type { TradeSignal } from "./types/TradeSignal.js";
import type { RiskInterface, Portfolio } from "./types/RiskInterface.js";
import type { ExecutionLogEntry } from "./execution-log.js";

/** Runner configuration. */
export interface RunnerConfig {
  /** Milliseconds between poll cycles. */
  pollIntervalMs: number;
  /** When true, signals are logged but orders are not submitted. */
  dryRun: boolean;
  /** Base directory for execution log files. */
  baseDir: string;
  /** Path to the local JSON state file. */
  statePath: string;
}

/** Order executor dependency — submits signals as orders. */
export interface ExecutorDeps {
  submit(
    signal: TradeSignal,
  ): Promise<{ id: string; status: string }>;
}

/** Position manager dependency — reconciles and exposes portfolio. */
export interface PositionDeps {
  reconcile(): Promise<Portfolio>;
  getPortfolio(): Portfolio;
}

/** All injectable dependencies for the runner. */
export interface RunnerDeps {
  /** Strategy function — returns signals for the current cycle. */
  strategy: () => Promise<TradeSignal[]>;
  /** Risk interface — approves or rejects signals. */
  risk: RiskInterface;
  /** Order executor — submits approved signals. */
  executor: ExecutorDeps;
  /** Position manager — provides portfolio state. */
  positions: PositionDeps;
  /** Execution log — records every pipeline decision. */
  log: (entry: ExecutionLogEntry) => void;
}

/** Strategy runner instance. */
export interface Runner {
  /** Start the poll loop. Resolves when the runner stops. */
  start(): Promise<void>;
  /** Signal the runner to stop after the current cycle. */
  stop(): void;
  /** Whether the poll loop is currently running. */
  readonly isRunning: boolean;
}

/**
 * Create a new strategy runner.
 *
 * The runner polls the strategy function at `config.pollIntervalMs`,
 * passes each signal through `deps.risk.preTradeCheck`, submits
 * approved signals via `deps.executor.submit` (skipped in dry-run),
 * and logs every decision via `deps.log`.
 *
 * Registers a SIGINT handler for graceful shutdown.
 */
export function createRunner(
  _config: RunnerConfig,
  _deps: RunnerDeps,
): Runner {
  throw new Error("Not implemented — see plan item 12");
}
