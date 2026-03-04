import { Box, Text, useStdout } from "ink";
import type { LogEntry, LogLevel } from "./types.js";

interface LogPanelProps {
  readonly logs: readonly LogEntry[];
  /** How many rows MetricsPanel occupies (border + content). */
  readonly metricsRows: number;
}

const LEVEL_COLORS: Record<LogLevel, string> = {
  info: "blue",
  warn: "yellow",
  error: "red",
  debug: "gray",
};

/**
 * Rows consumed by chrome outside the log entries themselves:
 * StatusBar (3) + LogPanel border-bottom (1) + paddingX side borders (2 cols,
 * but 0 rows) + MetricsPanel is passed in as prop.
 */
const STATUS_BAR_ROWS = 3;
const LOG_BORDER_ROWS = 1;

/** Prefix width: "HH:MM:SS " + "info  " = 8+1+5+1 = 15 chars. */
const PREFIX_WIDTH = 15;

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

export function LogPanel({ logs, metricsRows }: LogPanelProps) {
  const { stdout } = useStdout();
  const termRows = stdout?.rows ?? 24;
  const termCols = stdout?.columns ?? 80;

  // Available rows for log entries (1 entry = 1 row, no wrapping)
  const chrome = STATUS_BAR_ROWS + LOG_BORDER_ROWS + metricsRows;
  const visibleCount = Math.max(1, termRows - chrome);
  const visible = logs.slice(-visibleCount);

  // Max message chars before truncation (account for border + padding)
  const innerCols = termCols - 4; // 2 border + 2 paddingX
  const maxMsg = Math.max(10, innerCols - PREFIX_WIDTH);

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
        visible.map((entry, idx) => {
          const msg =
            entry.msg.length > maxMsg
              ? entry.msg.slice(0, maxMsg - 1) + "…"
              : entry.msg;
          return (
            <Box key={`${entry.ts}-${idx}`} gap={1}>
              <Text dimColor>{formatTime(entry.ts)}</Text>
              <Text color={LEVEL_COLORS[entry.level]}>
                {entry.level.padEnd(5)}
              </Text>
              <Text>{msg}</Text>
            </Box>
          );
        })
      )}
    </Box>
  );
}
