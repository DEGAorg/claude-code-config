import { useState, useEffect, useRef } from "react";
import { Box, Text } from "ink";
import { watch } from "chokidar";
import { readFile } from "node:fs/promises";
import type { TerminalUIState } from "./types.js";
import { StatusBar } from "./status-bar.js";
import { LogPanel } from "./log-panel.js";
import { MetricsPanel } from "./metrics-panel.js";

interface AppProps {
  readonly statePath: string;
}

export function App({ statePath }: AppProps) {
  const [state, setState] = useState<TerminalUIState | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const lastValidRef = useRef<TerminalUIState | null>(null);

  useEffect(() => {
    async function loadState(): Promise<void> {
      try {
        const raw = await readFile(statePath, "utf-8");
        const parsed = JSON.parse(raw) as TerminalUIState;
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
        setWarning(
          err instanceof Error ? err.message : String(err),
        );
      }
    }

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
  }, [statePath]);

  if (!state) {
    return (
      <Box flexDirection="column" padding={1}>
        <Text dimColor>Waiting for state file…</Text>
        <Text dimColor>{statePath}</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <StatusBar phase={state.phase} status={state.status} />
      {warning ? <Text color="yellow">⚠ {warning}</Text> : null}
      <LogPanel logs={state.logs} />
      <MetricsPanel metrics={state.metrics} />
    </Box>
  );
}
