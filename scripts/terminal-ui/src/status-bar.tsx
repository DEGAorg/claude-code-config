import { Box, Text } from "ink";
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

  return (
    <Box
      borderStyle="single"
      borderBottom={false}
      paddingX={1}
      height={3}
      alignItems="center"
    >
      <Text color={phaseColor} bold>
        {phase.toUpperCase()}
      </Text>
      <Box flexGrow={1} />
      <Text backgroundColor={statusColor} color="black" bold>
        {` ${status.toUpperCase()} `}
      </Text>
    </Box>
  );
}
