import { Box, Text, useStdout } from "ink";
import type { LogEntry, LogLevel } from "./types.js";

interface LogPanelProps {
  readonly logs: readonly LogEntry[];
}

const LEVEL_COLORS: Record<LogLevel, string> = {
  info: "blue",
  warn: "yellow",
  error: "red",
  debug: "gray",
};

/** Rows consumed by StatusBar (4) + MetricsPanel (~4) + padding. */
const CHROME_ROWS = 9;

function formatTime(ts: string): string {
  const date = new Date(ts);
  if (Number.isNaN(date.getTime())) {
    return ts.slice(0, 8);
  }
  return date.toLocaleTimeString("en-GB", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}

export function LogPanel({ logs }: LogPanelProps) {
  const { stdout } = useStdout();
  const termRows = stdout?.rows ?? 24;
  // Allow ~1.5 lines per entry to account for wrapping
  const visibleCount = Math.max(1, Math.floor((termRows - CHROME_ROWS) * 0.7));
  const visible = logs.slice(-visibleCount);

  return (
    <Box
      flexDirection="column"
      flexGrow={1}
      borderStyle="single"
      borderTop={false}
      paddingX={1}
    >
      {visible.length === 0 ? (
        <Text dimColor>No log entries yet</Text>
      ) : (
        visible.map((entry, idx) => (
          <Box key={`${entry.ts}-${idx}`} gap={1}>
            <Text dimColor>{formatTime(entry.ts)}</Text>
            <Text color={LEVEL_COLORS[entry.level]}>
              {entry.level.padEnd(5)}
            </Text>
            <Text>{entry.msg}</Text>
          </Box>
        ))
      )}
    </Box>
  );
}
