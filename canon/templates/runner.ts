/**
 * Strategy runner — configurable poll loop that integrates strategy
 * signal generation, risk checks, order execution, position management,
 * and structured execution logging.
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
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

/**
 * Outcome of a submitted order, fed into strategy-level outcome
 * tracking (e.g. consecutive-loss circuit breakers).
 *
 * NOTE: For ARB-01 / MINT / market-resolved strategies, "win" vs "loss"
 * cannot be determined from the order-submit response alone — final
 * P&L resolves at market settlement. The current contract reports a
 * synchronous `submitted | rejected | error` summary; richer P&L
 * tracking is deferred. See docs/reviews/261-open-questions.md.
 */
export interface OrderOutcome {
  signal: TradeSignal;
  /** Coarse status from the executor: "submitted" / "rejected" / "error". */
  status: "submitted" | "rejected" | "error";
  /** Order ID when the exchange returned one. */
  orderId?: string;
  /** Error message when `status === "error"`. */
  error?: string;
}

/**
 * Optional outcome callback — invoked after every executor.submit
 * attempt (success or failure). Strategies use this to feed
 * `risk.recordOutcome` or maintain bookkeeping.
 */
export type OnOutcome = (outcome: OrderOutcome) => void;

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
  /** Optional outcome callback fired after every submission attempt. */
  onOutcome?: OnOutcome;
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

function logEntry(
  type: ExecutionLogEntry["type"],
  automationId: string,
  marketId: string,
  data: Record<string, unknown>,
): ExecutionLogEntry {
  return {
    timestamp: new Date().toISOString(),
    type,
    automation_id: automationId,
    market_id: marketId,
    data,
  };
}

/**
 * Update the runner's `flow.json` with the current `active` step and
 * `completed` step list, and stamp `active_since` with an ISO 8601 UTC
 * timestamp whenever `active` transitions to a new non-empty value.
 *
 * Idempotent: a repeat call with the same `active` preserves the existing
 * `active_since`. When `active === ""`, `active_since` is omitted entirely
 * so the TUI's `.get("active_since", "")` reader treats the field as absent.
 *
 * All other fields in the file are preserved verbatim — the seeds carry
 * `nodes`/`edges` DAG metadata that the canon-tui automation panel reads,
 * so the write spreads the existing flow rather than rebuilding it from a
 * fixed key set.
 */
export function updateFlow(
  flowPath: string,
  active: string,
  completed: string[],
): void {
  if (!existsSync(flowPath)) return;
  try {
    const flow = JSON.parse(readFileSync(flowPath, "utf-8")) as Record<
      string,
      unknown
    > & { active?: string; active_since?: string };

    const activeSince =
      active === ""
        ? undefined
        : active === flow.active
          ? flow.active_since
          : new Date().toISOString();

    const next: Record<string, unknown> = { ...flow, active, completed };
    if (activeSince === undefined) {
      delete next["active_since"];
    } else {
      next["active_since"] = activeSince;
    }

    writeFileSync(flowPath, JSON.stringify(next, null, 2) + "\n");
  } catch {
    // flow.json missing or malformed — skip silently
  }
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
  config: RunnerConfig,
  deps: RunnerDeps,
): Runner {
  let running = false;
  let stopRequested = false;
  let sigintHandler: (() => void) | null = null;
  let cycleCount = 0;
  let signalCount = 0;
  let errorCount = 0;

  function out(tag: string, msg: string): void {
    process.stdout.write(`${tag} ${msg}\n`);
  }

  const flowPath = join(config.baseDir, "flow.json");

  async function processSignal(
    signal: TradeSignal,
    portfolio: Portfolio,
  ): Promise<void> {
    deps.log(
      logEntry("signal", signal.automation_id, signal.market.market_id, {
        direction: signal.direction,
        size: signal.size,
        confidence: signal.confidence,
      }),
    );

    signalCount++;
    out(
      "SIGNAL",
      `${signal.automation_id} ${signal.market.market_id} ` +
        `${signal.direction} confidence=${String(signal.confidence)}`,
    );

    const decision = deps.risk.preTradeCheck(signal, portfolio);

    deps.log(
      logEntry(
        "risk_check",
        signal.automation_id,
        signal.market.market_id,
        {
          approved: decision.approved,
          rejection_reason: decision.rejection_reason,
          modified_size: decision.modified_size,
        },
      ),
    );

    if (!decision.approved) {
      return;
    }

    const submittable =
      decision.modified_size !== undefined
        ? { ...signal, size: decision.modified_size }
        : signal;

    if (config.dryRun) {
      return;
    }

    updateFlow(flowPath, "execute", ["scan", "signal", "risk"]);
    try {
      const result = await deps.executor.submit(submittable);
      deps.log(
        logEntry(
          "order_submit",
          signal.automation_id,
          signal.market.market_id,
          { order_id: result.id, status: result.status },
        ),
      );
      const submitStatus: OrderOutcome["status"] =
        result.status === "rejected" ? "rejected" : "submitted";
      deps.onOutcome?.({
        signal: submittable,
        status: submitStatus,
        orderId: result.id,
      });
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : String(err);
      deps.log(
        logEntry(
          "error",
          signal.automation_id,
          signal.market.market_id,
          { error: message, stage: "order_submit" },
        ),
      );
      deps.onOutcome?.({
        signal: submittable,
        status: "error",
        error: message,
      });
    }
  }

  async function cycle(): Promise<void> {
    cycleCount++;
    updateFlow(flowPath, "scan", []);
    out("SCAN", `#${String(cycleCount)}`);

    const portfolio = await deps.positions.reconcile();

    updateFlow(flowPath, "signal", ["scan"]);
    const signals = await deps.strategy();

    for (const signal of signals) {
      updateFlow(flowPath, "risk", ["scan", "signal"]);
      await processSignal(signal, portfolio);
    }

    updateFlow(flowPath, "log", ["scan", "signal", "risk", "execute"]);

    if (signals.length === 0) {
      out(
        "NO_EDGE",
        `#${String(cycleCount)} — 0 signals, no edges`,
      );
    }

    updateFlow(flowPath, "", ["scan", "signal", "risk", "execute", "log"]);
  }

  function stop(): void {
    stopRequested = true;
  }

  async function start(): Promise<void> {
    running = true;
    stopRequested = false;

    sigintHandler = () => {
      out(
        "STOP",
        `Shutting down — ${String(cycleCount)} iterations, ` +
          `${String(signalCount)} signals, ${String(errorCount)} errors`,
      );
      stop();
    };
    process.on("SIGINT", sigintHandler);

    try {
      while (!stopRequested) {
        try {
          await cycle();
        } catch (err: unknown) {
          errorCount++;
          const message =
            err instanceof Error ? err.message : String(err);
          out("SCAN_ERROR", `#${String(cycleCount)} — ${message}`);
          deps.log(
            logEntry("error", "runner", "", {
              error: message,
              stage: "cycle",
            }),
          );
        }

        if (stopRequested) {
          break;
        }

        await new Promise<void>((resolve) => {
          setTimeout(resolve, config.pollIntervalMs);
        });
      }
    } finally {
      running = false;
      if (sigintHandler) {
        process.removeListener("SIGINT", sigintHandler);
        sigintHandler = null;
      }
    }
  }

  return {
    start,
    stop,
    get isRunning() {
      return running;
    },
  };
}
