/**
 * StateSource interface — abstracts reading orchestrator state and
 * tailing per-item logs for the Ink TUI.
 *
 * The default (local) implementation watches `.orchestrator/plans/<slug>/state.json`
 * via chokidar and tails per-item log files via a Node tailer. A future
 * remote/cloud implementation can substitute without view-code changes.
 */

import type { OrchestratorState } from "./orch-types.js";

/** Callback invoked whenever the state file is read or changes. */
export type StateListener = (state: OrchestratorState) => void;

/** Callback invoked whenever a log file gains new lines. */
export type LogLineListener = (line: string) => void;

/** Unsubscribe from a watch or tail. Idempotent. */
export type Unsubscribe = () => void;

/**
 * Source of orchestrator state for the TUI. Views depend on this
 * interface, not on concrete file-watching machinery.
 */
export interface StateSource {
  /**
   * Read the current state snapshot. Resolves to `null` if the state
   * file does not yet exist — views render an empty shell in that case.
   */
  readState(): Promise<OrchestratorState | null>;

  /**
   * Subscribe to state changes. The listener fires once with the
   * initial value (if the file exists) and again on every write.
   * Returns an unsubscribe function.
   */
  watchState(listener: StateListener): Unsubscribe;

  /**
   * Tail a per-item log file. The listener fires for each appended
   * line; if the file does not yet exist, the tailer waits for it.
   * Returns an unsubscribe function.
   */
  tailLog(logPath: string, listener: LogLineListener): Unsubscribe;

  /** Release any watchers and file handles held by this source. */
  dispose(): Promise<void>;
}

/**
 * Stub implementation — throws on every call. Item 7 replaces this with
 * a real `LocalStateSource` backed by chokidar + a Node tailer.
 */
export class LocalStateSource implements StateSource {
  constructor(_opts: { readonly statePath: string }) {
    // intentionally empty — stub
  }

  readState(): Promise<OrchestratorState | null> {
    throw new Error("LocalStateSource.readState not implemented");
  }

  watchState(_listener: StateListener): Unsubscribe {
    throw new Error("LocalStateSource.watchState not implemented");
  }

  tailLog(_logPath: string, _listener: LogLineListener): Unsubscribe {
    throw new Error("LocalStateSource.tailLog not implemented");
  }

  dispose(): Promise<void> {
    throw new Error("LocalStateSource.dispose not implemented");
  }
}
