import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { Box, Text, useApp, useInput, useStdin } from "ink";
import { watch } from "chokidar";
import { readFile } from "node:fs/promises";
import { resolve, dirname, join } from "node:path";
import type { OrchestratorState, MasterState } from "./orch-types.js";
import { LocalStateSource, type StateSource } from "./state-source.js";
import { SessionTable } from "./session-table.js";
import { SessionDetail } from "./session-detail.js";
import { MasterView } from "./master-view.js";

/** Max lines retained in the tailed-log window. */
const TAIL_BUFFER_LINES = 200;

/** Threshold in seconds after which heartbeat is considered stale. */
const HEARTBEAT_STALE_THRESHOLD = 300; // 5 minutes

function formatHeartbeatAge(epochSecs: number): {
  text: string;
  stale: boolean;
} {
  const ageSecs = Math.max(
    0,
    Math.floor(Date.now() / 1000) - epochSecs,
  );
  const stale = ageSecs > HEARTBEAT_STALE_THRESHOLD;
  if (ageSecs < 60) {
    return { text: `${ageSecs}s ago`, stale };
  }
  const mins = Math.floor(ageSecs / 60);
  const secs = ageSecs % 60;
  return { text: `${mins}m${secs}s ago`, stale };
}

interface OrchestratorAppProps {
  readonly statePath: string;
  /** Optional injected source — defaults to `LocalStateSource`. */
  readonly source?: StateSource;
}

interface MasterOrchestratorAppProps {
  readonly masterPath: string;
}

export function OrchestratorApp({ statePath, source }: OrchestratorAppProps) {
  const [state, setState] = useState<OrchestratorState | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const [outputLines, setOutputLines] = useState<readonly string[]>([]);
  const [heartbeat, setHeartbeat] = useState<number | null>(null);
  const [, setHeartbeatTick] = useState(0);
  const lastValidRef = useRef<OrchestratorState | null>(null);

  const ownsSource = source === undefined;
  const stateSource = useMemo<StateSource>(
    () => source ?? new LocalStateSource({ statePath }),
    [source, statePath],
  );

  useEffect(() => {
    let cancelled = false;

    void stateSource
      .readState()
      .then((initial) => {
        if (cancelled) return;
        if (initial) {
          lastValidRef.current = initial;
          setState(initial);
        }
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setWarning(err instanceof Error ? err.message : String(err));
      });

    const unsubscribe = stateSource.watchState((parsed) => {
      lastValidRef.current = parsed;
      setState(parsed);
      setWarning(null);
    });

    return () => {
      cancelled = true;
      unsubscribe();
      if (ownsSource) void stateSource.dispose();
    };
  }, [stateSource, ownsSource]);

  // Read heartbeat file and poll for age updates
  const heartbeatPath = join(dirname(statePath), "heartbeat");

  const loadHeartbeat = useCallback(async () => {
    try {
      const raw = await readFile(heartbeatPath, "utf-8");
      const epoch = parseInt(raw.trim(), 10);
      if (!Number.isNaN(epoch)) {
        setHeartbeat(epoch);
      }
    } catch {
      // Heartbeat file may not exist yet
    }
  }, [heartbeatPath]);

  useEffect(() => {
    void loadHeartbeat();

    const watcher = watch(heartbeatPath, {
      persistent: true,
      ignoreInitial: true,
    });

    watcher.on("change", () => void loadHeartbeat());
    watcher.on("add", () => void loadHeartbeat());

    return () => {
      void watcher.close();
    };
  }, [heartbeatPath, loadHeartbeat]);

  // Tick every 1s to keep "Xs ago" display fresh
  useEffect(() => {
    const interval = setInterval(() => {
      setHeartbeatTick((t) => t + 1);
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  // Tail the selected item's log file via the state source.
  const selectedLogPath =
    selectedId !== null && state !== null
      ? (state.items.find((i) => i.id === selectedId)?.logPath ?? null)
      : null;

  useEffect(() => {
    if (selectedId === null || selectedLogPath === null) {
      setOutputLines([]);
      return;
    }

    setOutputLines([]);
    const unsub = stateSource.tailLog(selectedLogPath, (line) => {
      setOutputLines((prev) => {
        const next = prev.length >= TAIL_BUFFER_LINES ? prev.slice(1) : prev;
        return [...next, line];
      });
    });

    return () => {
      unsub();
    };
  }, [selectedId, selectedLogPath, stateSource]);

  // Keyboard navigation: j/k or arrows to select items, q to quit on terminal screens
  const { isRawModeSupported } = useStdin();
  const { exit } = useApp();
  useInput(
    (input, key) => {
      // q exits on terminal screens (completed/failed)
      if (input === "q" && state && (state.status === "completed" || state.status === "failed")) {
        exit();
        return;
      }

      if (!state || state.items.length === 0) return;

      const ids = state.items.map((i) => i.id);
      const currentIdx = selectedId !== null ? ids.indexOf(selectedId) : -1;

      if (input === "j" || key.downArrow) {
        const nextIdx =
          currentIdx < 0 ? 0 : Math.min(currentIdx + 1, ids.length - 1);
        setSelectedId(ids[nextIdx] ?? null);
        setOutputLines([]);
      } else if (input === "k" || key.upArrow) {
        const prevIdx =
          currentIdx < 0 ? 0 : Math.max(currentIdx - 1, 0);
        setSelectedId(ids[prevIdx] ?? null);
        setOutputLines([]);
      } else if (key.escape) {
        setSelectedId(null);
        setOutputLines([]);
      }
    },
    { isActive: isRawModeSupported },
  );

  if (!state) {
    return (
      <Box flexDirection="column" padding={1}>
        <Text bold>ORCHESTRATOR</Text>
        <Text dimColor>Waiting for state file…</Text>
        <Text dimColor>{statePath}</Text>
      </Box>
    );
  }

  // Render final/transitional screens based on state.status
  if (state.status === "verifying") {
    const total = state.items.length;
    const done = state.items.filter((i) => i.status === "done").length;
    return (
      <Box flexDirection="column" padding={1}>
        <Box>
          <Text bold color="cyanBright" inverse>
            {" VERIFYING "}
          </Text>
          <Text bold>{" "}{state.plan}</Text>
        </Box>
        <Text>
          All {total} items passed review ({done} done). Checking completion criteria...
        </Text>
      </Box>
    );
  }

  if (state.status === "completed") {
    const total = state.items.length;
    const done = state.items.filter((i) => i.status === "done").length;
    return (
      <Box flexDirection="column" padding={1}>
        <Box>
          <Text bold color="greenBright" inverse>
            {" DONE "}
          </Text>
          <Text bold>{" "}{state.plan}</Text>
        </Box>
        <Text>
          All {total} items completed ({done} done). Plan shipped and archived.
        </Text>
        <Text dimColor>Press q or close the terminal window to exit.</Text>
      </Box>
    );
  }

  if (state.status === "failed") {
    const failed = state.items.filter((i) => i.status === "failed").length;
    return (
      <Box flexDirection="column" padding={1}>
        <Box>
          <Text bold color="red" inverse>
            {" FAILED "}
          </Text>
          <Text bold>{" "}{state.plan}</Text>
        </Box>
        <Text>{failed} item(s) failed. Check engine log for details.</Text>
        <Text dimColor>Press q or close the terminal window to exit.</Text>
      </Box>
    );
  }

  const selectedItem =
    selectedId !== null
      ? (state.items.find((i) => i.id === selectedId) ?? null)
      : null;

  const finalReview = state.finalReview ?? { status: "pending", result: null };

  const runningCount = state.items.filter((i) => i.status === "running").length;
  const doneCount = state.items.filter((i) => i.status === "done").length;
  const failedCount = state.items.filter((i) => i.status === "failed").length;

  // Status badge — only reached for "running" states (terminal screens return early)
  const statusBadge = (() => {
    if (finalReview.status === "done" && finalReview.result === "SHIP") {
      return { label: " SHIP ", color: "greenBright" } as const;
    }
    if (finalReview.status === "done" && finalReview.result === "REVISE") {
      return { label: " REVISE ", color: "red" } as const;
    }
    if (finalReview.status === "running") {
      return { label: " REVIEWING ", color: "cyanBright" } as const;
    }
    if (runningCount > 0) {
      return { label: " RUNNING ", color: "greenBright" } as const;
    }
    return { label: " IDLE ", color: "yellow" } as const;
  })();

  return (
    <Box flexDirection="column" height="100%">
      <Box
        borderStyle="single"
        borderBottom={false}
        paddingX={1}
        height={3}
        alignItems="center"
      >
        <Text bold>ORCHESTRATOR</Text>
        <Text bold color={statusBadge.color} inverse>
          {statusBadge.label}
        </Text>
        <Box flexGrow={1} />
        <Text color="greenBright" bold>
          {doneCount}
        </Text>
        <Text dimColor>/</Text>
        <Text>{state.items.length}</Text>
        <Text dimColor> done</Text>
        {runningCount > 0 ? (
          <Text>
            {"  "}
            <Text color="greenBright" bold>
              {runningCount}
            </Text>
            <Text dimColor> running</Text>
          </Text>
        ) : null}
        {failedCount > 0 ? (
          <Text>
            {"  "}
            <Text color="red" bold>
              {failedCount}
            </Text>
            <Text dimColor> failed</Text>
          </Text>
        ) : null}
        <Text dimColor>
          {"  "}max {state.maxParallelWorkers}w
        </Text>
        {heartbeat !== null ? (
          (() => {
            const { text, stale } = formatHeartbeatAge(heartbeat);
            return (
              <Text color={stale ? "red" : "green"} bold={stale}>
                {"  "}Last heartbeat: {text}
              </Text>
            );
          })()
        ) : null}
      </Box>

      {warning ? <Text color="yellow">⚠ {warning}</Text> : null}

      <SessionTable
        plan={state.plan}
        items={state.items}
        selectedId={selectedId}
      />

      <SessionDetail
        item={selectedItem}
        outputLines={outputLines}
        reviewStatus={selectedItem?.reviewStatus ?? "pending"}
        reservedRows={3 + state.items.length + 4 + 1 + (warning ? 1 : 0)}
      />

      <Box paddingX={1}>
        <Text dimColor>j/k: navigate  esc: deselect</Text>
      </Box>
    </Box>
  );
}

/** Watches master.json and renders all-plans view with drill-down. */
export function MasterOrchestratorApp({
  masterPath,
}: MasterOrchestratorAppProps) {
  const [master, setMaster] = useState<MasterState | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
  const [drillSlug, setDrillSlug] = useState<string | null>(null);
  const lastValidRef = useRef<MasterState | null>(null);

  const loadMaster = useCallback(async () => {
    try {
      const raw = await readFile(masterPath, "utf-8");
      const parsed = JSON.parse(raw) as MasterState;
      lastValidRef.current = parsed;
      setMaster(parsed);
      setWarning(null);
    } catch (err: unknown) {
      const isNotFound =
        err instanceof Error &&
        "code" in err &&
        (err as { code: unknown }).code === "ENOENT";

      if (isNotFound) {
        setMaster(null);
        setWarning(null);
        return;
      }

      if (lastValidRef.current) {
        setMaster(lastValidRef.current);
      }
      setWarning(err instanceof Error ? err.message : String(err));
    }
  }, [masterPath]);

  useEffect(() => {
    void loadMaster();

    const watcher = watch(masterPath, {
      persistent: true,
      ignoreInitial: true,
    });

    watcher.on("change", () => void loadMaster());
    watcher.on("add", () => void loadMaster());
    watcher.on("unlink", () => {
      setMaster(null);
      setWarning(null);
    });

    return () => {
      void watcher.close();
    };
  }, [masterPath, loadMaster]);

  const { isRawModeSupported } = useStdin();
  useInput(
    (input, key) => {
      if (drillSlug) {
        if (key.escape) {
          setDrillSlug(null);
        }
        return;
      }

      if (!master || master.plans.length === 0) return;

      const count = master.plans.length;

      if (input === "j" || key.downArrow) {
        setSelectedIdx((prev) => {
          if (prev === null) return 0;
          return Math.min(prev + 1, count - 1);
        });
      } else if (input === "k" || key.upArrow) {
        setSelectedIdx((prev) => {
          if (prev === null) return 0;
          return Math.max((prev ?? 0) - 1, 0);
        });
      } else if (key.return && selectedIdx !== null) {
        const plan = master.plans[selectedIdx];
        if (plan) {
          setDrillSlug(plan.slug);
        }
      } else if (key.escape) {
        setSelectedIdx(null);
      }
    },
    { isActive: isRawModeSupported },
  );

  if (drillSlug && master) {
    const plan = master.plans.find((p) => p.slug === drillSlug);
    if (plan) {
      const orchDir = dirname(masterPath);
      const statePath = resolve(orchDir, plan.statePath);
      return (
        <Box flexDirection="column" height="100%">
          <Box paddingX={1}>
            <Text dimColor>esc: back to all plans</Text>
            <Box flexGrow={1} />
            <Text bold color="blueBright">
              {plan.slug}
            </Text>
          </Box>
          <OrchestratorApp statePath={statePath} />
        </Box>
      );
    }
    setDrillSlug(null);
  }

  if (!master) {
    return (
      <Box flexDirection="column" padding={1}>
        <Text bold>ORCHESTRATOR MASTER</Text>
        <Text dimColor>Waiting for master state file...</Text>
        <Text dimColor>{masterPath}</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column" height="100%">
      <Box
        borderStyle="single"
        borderBottom={false}
        paddingX={1}
        height={3}
        alignItems="center"
      >
        <Text bold>ORCHESTRATOR MASTER</Text>
        <Box flexGrow={1} />
        <Text dimColor>
          {master.plans.length} plan
          {master.plans.length !== 1 ? "s" : ""}
        </Text>
      </Box>

      {warning ? <Text color="yellow">warning: {warning}</Text> : null}

      <MasterView state={master} selectedIdx={selectedIdx} />

      <Box paddingX={1}>
        <Text dimColor>
          j/k: navigate  enter: drill down  esc: deselect
        </Text>
      </Box>
    </Box>
  );
}
