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

/** Progress snapshot for a plan in the master registry. */
export interface PlanProgress {
  readonly total: number;
  readonly done: number;
  readonly running: number;
  readonly failed: number;
}

/** Status of a plan in the master registry. */
export type PlanStatus = "running" | "completed" | "failed";

/** Single plan entry in the master state registry. */
export interface PlanEntry {
  readonly slug: string;
  readonly status: PlanStatus;
  /** Relative path from `.orchestrator/` to the plan's state file. */
  readonly statePath: string;
  readonly tmuxSession: string;
  /** Relative path from `.orchestrator/` to the plan's worktree. */
  readonly worktree: string;
  /** ISO 8601 — when the plan was started. */
  readonly startedAt: string;
  /** ISO 8601 — last update to this entry. */
  readonly updatedAt: string;
  /** Denormalized progress snapshot, updated each poll cycle. */
  readonly progress: PlanProgress;
}

/** Master state registry (`.orchestrator/master.json`). */
export interface MasterState {
  readonly version: 1;
  readonly plans: readonly PlanEntry[];
  /** ISO 8601 — last master state write. */
  readonly updatedAt: string;
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

/** Path to master state file relative to project root. */
export const ORCH_MASTER_FILE = `${ORCH_STATE_DIR}/master.json`;

/** Path to per-plan directory relative to project root. */
export const ORCH_PLANS_DIR = `${ORCH_STATE_DIR}/plans`;

/** Path to worktrees directory relative to project root. */
export const ORCH_WORKTREES_DIR = `${ORCH_STATE_DIR}/worktrees`;

/** Build path to a plan's state file relative to project root. */
export function orchPlanStateFile(slug: string): string {
  return `${ORCH_PLANS_DIR}/${slug}/state.json`;
}

/** Build path to a plan's done-files directory relative to project root. */
export function orchPlanDoneDir(slug: string): string {
  return `${ORCH_PLANS_DIR}/${slug}/done`;
}

/** Build path to a plan's reviews directory relative to project root. */
export function orchPlanReviewsDir(slug: string): string {
  return `${ORCH_PLANS_DIR}/${slug}/reviews`;
}

/** Build path to a plan's log directory relative to project root. */
export function orchPlanLogDir(slug: string): string {
  return `${ORCH_PLANS_DIR}/${slug}/logs`;
}

/** Build path to a plan's worktree relative to project root. */
export function orchPlanWorktree(slug: string): string {
  return `${ORCH_WORKTREES_DIR}/${slug}`;
}

/**
 * @deprecated Use `orchPlanStateFile(slug)` for per-plan state.
 * Kept temporarily for migration — will be removed.
 */
export const ORCH_STATE_FILE = `${ORCH_STATE_DIR}/state.json`;
