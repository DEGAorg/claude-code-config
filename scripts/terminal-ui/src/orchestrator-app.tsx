import { useState, useEffect, useRef, useCallback } from "react";
import { Box, Text, useInput } from "ink";
import { watch } from "chokidar";
import { readFile } from "node:fs/promises";
import type { OrchestratorState } from "./orch-types.js";
import { SessionTable } from "./session-table.js";
import { SessionDetail } from "./session-detail.js";

interface OrchestratorAppProps {
  readonly statePath: string;
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

  // Keyboard navigation: j/k or arrows to select items
  useInput((input, key) => {
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
  });

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

  const reviewDone = state.finalReview.status === "done";
  const reviewColor = state.finalReview.result === "SHIP"
    ? "greenBright"
    : "red";

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
        <Box flexGrow={1} />
        <Text dimColor>
          {state.items.length} items, max {state.maxParallelWorkers} workers
        </Text>
        {reviewDone ? (
          <Text color={reviewColor}>
            {" "}
            review: {state.finalReview.result ?? "done"}
          </Text>
        ) : state.finalReview.status === "running" ? (
          <Text dimColor> review: running</Text>
        ) : null}
      </Box>

      {warning ? <Text color="yellow">⚠ {warning}</Text> : null}

      <SessionTable
        plan={state.plan}
        items={state.items}
        selectedId={selectedId}
      />

      <SessionDetail item={selectedItem} outputLines={outputLines} />

      <Box paddingX={1}>
        <Text dimColor>j/k: navigate  esc: deselect</Text>
      </Box>
    </Box>
  );
}
