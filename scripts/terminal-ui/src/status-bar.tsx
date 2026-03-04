import { Box, Text, useStdout } from "ink";
import type { Status } from "./types.js";

interface StatusBarProps {
  readonly phase: string;
  readonly status: Status;
}

const STATUS_COLORS: Record<Status, string> = {
  running: "green",
  automating: "cyan",
  executing: "magenta",
  paused: "yellow",
  idle: "gray",
  complete: "greenBright",
  error: "red",
};

const PHASE_COLORS: Record<string, string> = {
  init: "gray",
  scaffold: "blue",
  strategy: "yellow",
  develop: "cyan",
  run: "green",
};

export function StatusBar({ phase, status }: StatusBarProps) {
  const statusColor = STATUS_COLORS[status];
  const phaseColor = PHASE_COLORS[phase] ?? "white";
  const { stdout } = useStdout();
  const cols = stdout?.columns ?? 80;

  const phaseLabel = ` ${phase.toUpperCase()} `;
  const statusLabel = ` ${status.toUpperCase()} `;
  const gap = Math.max(
    0,
    cols - phaseLabel.length - statusLabel.length - 12,
  );

  return (
    <Box
      borderStyle="double"
      borderBottom={false}
      paddingX={1}
      height={3}
      alignItems="center"
    >
      <Text backgroundColor={phaseColor} color="black" bold>
        {phaseLabel}
      </Text>
      <Box flexGrow={1} />
      <Text backgroundColor={statusColor} color="black" bold>
        {statusLabel}
      </Text>
    </Box>
  );
}
