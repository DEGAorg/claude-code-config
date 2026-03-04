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

export function StatusBar({ phase, status }: StatusBarProps) {
  const color = STATUS_COLORS[status];

  return (
    <Box borderStyle="single" borderBottom={false} paddingX={1}>
      <Box flexGrow={1}>
        <Text bold>Phase: </Text>
        <Text>{phase}</Text>
      </Box>
      <Text color={color} bold>
        {"● "}
        {status.toUpperCase()}
      </Text>
    </Box>
  );
}
