/**
 * Orchestrator state types.
 *
 * Defines the shape of `.orchestrator/state.json` and per-item state
 * used by the orchestrator agent, helper scripts, and Ink dashboard.
 */

/** Item lifecycle status. */
export type ItemStatus =
  | "queued"
  | "ready"
  | "running"
  | "review"
  | "done"
  | "failed"
  | "blocked";

/** Worker execution mode. */
export type OrchestratorMode = "foreground" | "background";

/** Final review outcome. */
export type ReviewResult = "SHIP" | "REVISE";

/** Final review state after all items complete. */
export interface FinalReview {
  readonly status: "pending" | "running" | "done";
  readonly result: ReviewResult | null;
  /** Items flagged for rework when result is REVISE. */
  readonly reworkItems: readonly number[];
}

/** Single item parsed from a plan's progress log. */
export interface OrchestratorItem {
  /** 1-indexed position in the progress log. */
  readonly id: number;
  /** Item description text (without deps annotation). */
  readonly description: string;
  /** IDs of items this depends on (empty = no deps). */
  readonly deps: readonly number[];
  /** Current lifecycle status. */
  readonly status: ItemStatus;
  /** PID of the worker process, if running. */
  readonly workerPid: number | null;
  /** Tmux pane identifier in foreground mode. */
  readonly tmuxPane: string | null;
  /** Worktree path in background mode. */
  readonly worktree: string | null;
  /** Current ralph loop iteration (1-indexed). */
  readonly iteration: number;
  /** Max iterations allowed per item. */
  readonly maxIterations: number;
  /** Last review result for this item. */
  readonly lastResult: ReviewResult | null;
}

/** Top-level orchestrator state (`.orchestrator/state.json`). */
export interface OrchestratorState {
  /** Schema version for forward compat. */
  readonly version: 1;
  /** Exec-plan slug being orchestrated. */
  readonly plan: string;
  /** Max concurrent workers. */
  readonly maxParallelWorkers: number;
  /** Foreground (tmux grid) or background (detached). */
  readonly mode: OrchestratorMode;
  /** All items parsed from the plan's progress log. */
  readonly items: readonly OrchestratorItem[];
  /** Final whole-plan review state. */
  readonly finalReview: FinalReview;
  /** ISO 8601 — when orchestration started. */
  readonly startedAt: string;
  /** ISO 8601 — last state write. */
  readonly updatedAt: string;
}

/**
 * Output of `orch-parse-items.sh` — raw parsed items before
 * orchestration state is created.
 */
export interface ParsedItem {
  readonly id: number;
  readonly description: string;
  readonly deps: readonly number[];
  readonly checked: boolean;
}

/** Parsed items output from the plan parser. */
export interface ParsedPlan {
  readonly slug: string;
  readonly items: readonly ParsedItem[];
}

/** Plan summary for `orch-list.sh` output. */
export interface PlanSummary {
  readonly slug: string;
  readonly status: "active" | "completed" | "blocked";
  readonly totalItems: number;
  readonly doneItems: number;
  readonly activeWorkers: number;
}

/**
 * Default values for new orchestrator state.
 * Scripts use these when creating `.orchestrator/state.json`.
 */
export const ORCH_DEFAULTS = {
  version: 1 as const,
  maxParallelWorkers: 4,
  maxIterationsPerItem: 3,
} as const;

/** Path to orchestrator state dir relative to project root. */
export const ORCH_STATE_DIR = ".orchestrator";

/** Path to state file relative to project root. */
export const ORCH_STATE_FILE = `${ORCH_STATE_DIR}/state.json`;
