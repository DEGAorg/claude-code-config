/**
 * StateSource interface — abstracts reading orchestrator state and
 * tailing per-item logs for the Ink TUI.
 *
 * The default (local) implementation watches `.orchestrator/plans/<slug>/state.json`
 * via chokidar and tails per-item log files via incremental positional
 * reads. A future remote/cloud implementation can substitute without
 * view-code changes.
 */

import { open, readFile, stat } from "node:fs/promises";
import { watch, type FSWatcher } from "chokidar";

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

function isNotFound(err: unknown): boolean {
  return (
    err instanceof Error &&
    "code" in err &&
    (err as { code: unknown }).code === "ENOENT"
  );
}

async function readAllJson(
  path: string,
): Promise<OrchestratorState | null> {
  try {
    const raw = await readFile(path, "utf-8");
    return JSON.parse(raw) as OrchestratorState;
  } catch (err) {
    if (isNotFound(err)) return null;
    throw err;
  }
}

/**
 * Local `StateSource` backed by chokidar watchers on `state.json` and
 * per-item log files. Holds open watchers until `dispose()` is called.
 */
export class LocalStateSource implements StateSource {
  private readonly statePath: string;
  private readonly watchers = new Set<FSWatcher>();

  constructor(opts: { readonly statePath: string }) {
    this.statePath = opts.statePath;
  }

  readState(): Promise<OrchestratorState | null> {
    return readAllJson(this.statePath);
  }

  watchState(listener: StateListener): Unsubscribe {
    let active = true;

    const emit = async () => {
      if (!active) return;
      const state = await readAllJson(this.statePath).catch(() => null);
      if (active && state !== null) listener(state);
    };

    const watcher = watch(this.statePath, {
      persistent: true,
      ignoreInitial: false,
    });
    watcher.on("add", () => void emit());
    watcher.on("change", () => void emit());
    this.watchers.add(watcher);

    return () => {
      active = false;
      this.watchers.delete(watcher);
      void watcher.close();
    };
  }

  tailLog(logPath: string, listener: LogLineListener): Unsubscribe {
    let active = true;
    let position = 0;
    let pending: Promise<void> = Promise.resolve();
    let buffered = "";

    // Prime position — if the file exists at subscription time, skip
    // to EOF so existing content is not replayed. If it does not exist,
    // read from byte 0 once it is created.
    pending = pending.then(async () => {
      try {
        const s = await stat(logPath);
        position = s.size;
      } catch {
        position = 0;
      }
    });

    const readFrom = async () => {
      if (!active) return;
      let size: number;
      try {
        const s = await stat(logPath);
        size = s.size;
      } catch {
        return;
      }
      if (size < position) position = 0;
      if (size === position) return;

      const fh = await open(logPath, "r").catch(() => null);
      if (!fh) return;
      try {
        const len = size - position;
        const buf = Buffer.alloc(len);
        await fh.read(buf, 0, len, position);
        position = size;
        buffered += buf.toString("utf-8");
        const parts = buffered.split("\n");
        buffered = parts.pop() ?? "";
        for (const line of parts) {
          if (!active) return;
          listener(line);
        }
      } finally {
        await fh.close();
      }
    };

    const enqueue = () => {
      pending = pending.then(readFrom).catch(() => undefined);
    };

    const watcher = watch(logPath, {
      persistent: true,
      ignoreInitial: true,
    });
    watcher.on("add", enqueue);
    watcher.on("change", enqueue);
    this.watchers.add(watcher);

    return () => {
      active = false;
      this.watchers.delete(watcher);
      void watcher.close();
    };
  }

  async dispose(): Promise<void> {
    const closing: Promise<void>[] = [];
    for (const w of this.watchers) closing.push(w.close());
    this.watchers.clear();
    await Promise.all(closing);
  }
}
