import { useState, useEffect, useRef, useCallback } from "react";
import { Box, Text, useInput, useStdin } from "ink";
import { watch } from "chokidar";
import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import type { OrchestratorState, MasterState } from "./orch-types.js";
import { SessionTable } from "./session-table.js";
import { SessionDetail } from "./session-detail.js";
import { MasterView } from "./master-view.js";

interface OrchestratorAppProps {
  readonly statePath: string;
}

interface MasterOrchestratorAppProps {
  readonly masterPath: string;
}

export function OrchestratorApp({ statePath }: OrchestratorAppProps) {
  const [state, setState] = useState<OrchestratorState | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const [outputLines, setOutputLines] = useState<readonly string[]>([]);
  const lastValidRef = useRef<OrchestratorState | null>(null);

  const loadState = useCallback(async () => {
    try {
      const raw = await readFile(statePath, "utf-8");
      const parsed = JSON.parse(raw) as OrchestratorState;
      lastValidRef.current = parsed;
      setState(parsed);
      setWarning(null);
    } catch (err: unknown) {
      const isNotFound =
        err instanceof Error &&
        "code" in err &&
        (err as { code: unknown }).code === "ENOENT";

      if (isNotFound) {
        setState(null);
        setWarning(null);
        return;
      }

      if (lastValidRef.current) {
        setState(lastValidRef.current);
      }
      setWarning(err instanceof Error ? err.message : String(err));
    }
  }, [statePath]);

  useEffect(() => {
    void loadState();

    const watcher = watch(statePath, {
      persistent: true,
      ignoreInitial: true,
    });

    watcher.on("change", () => void loadState());
    watcher.on("add", () => void loadState());
    watcher.on("unlink", () => {
      setState(null);
      setWarning(null);
    });

    return () => {
      void watcher.close();
    };
  }, [statePath, loadState]);

  // Watch the selected item's log file for live output
  const hasState = state !== null;
  const selectedReviewStatus =
    selectedId !== null && state !== null
      ? (state.items.find((i) => i.id === selectedId)?.reviewStatus ?? "pending")
      : "pending";

  useEffect(() => {
    if (selectedId === null || !hasState) {
      setOutputLines([]);
      return;
    }

    const logDir = resolve(dirname(statePath), "logs");
    const logPrefix = selectedReviewStatus === "reviewing" ? "reviewer" : "worker";
    const logPath = resolve(logDir, `${logPrefix}-${selectedId}.log`);

    const readTail = async () => {
      try {
        const content = await readFile(logPath, "utf-8");
        const lines = content.split("\n");
        setOutputLines(lines.slice(-200));
      } catch {
        // File may not exist yet if worker hasn't started
      }
    };

    void readTail();

    const logWatcher = watch(logPath, {
      persistent: true,
      ignoreInitial: true,
    });

    logWatcher.on("change", () => void readTail());
    logWatcher.on("add", () => void readTail());

    return () => {
      void logWatcher.close();
    };
  }, [selectedId, hasState, statePath, selectedReviewStatus]);

  // Keyboard navigation: j/k or arrows to select items
  // Only enable when raw mode is supported (requires TTY stdin)
  const { isRawModeSupported } = useStdin();
  useInput(
    (input, key) => {
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

  const selectedItem =
    selectedId !== null
      ? (state.items.find((i) => i.id === selectedId) ?? null)
      : null;

  const finalReview = state.finalReview ?? { status: "pending", result: null };

  const runningCount = state.items.filter((i) => i.status === "running").length;
  const doneCount = state.items.filter((i) => i.status === "done").length;
  const failedCount = state.items.filter((i) => i.status === "failed").length;

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
    <Box flexDirection="column">
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
        <Box flexDirection="column">
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
    <Box flexDirection="column">
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
