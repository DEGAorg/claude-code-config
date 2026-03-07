import { Box, Text, useStdout } from "ink";
import type { OrchestratorItem } from "./orch-types.js";

interface SessionDetailProps {
  readonly item: OrchestratorItem | null;
  /** Last N lines captured from the worker's tmux pane. */
  readonly outputLines: readonly string[];
}

export function SessionDetail({ item, outputLines }: SessionDetailProps) {
  const { stdout } = useStdout();
  const termRows = stdout?.rows ?? 24;

  // Reserve ~60% of terminal for the table above; detail gets the rest
  const maxLines = Math.max(3, Math.floor(termRows * 0.35));
  const visible = outputLines.slice(-maxLines);

  if (!item) {
    return (
      <Box
        flexDirection="column"
        borderStyle="single"
        borderTop={false}
        paddingX={1}
      >
        <Text dimColor>Select an item to view worker output</Text>
      </Box>
    );
  }

  const headerColor =
    item.status === "running"
      ? "green"
      : item.status === "failed"
        ? "red"
        : "cyan";

  return (
    <Box
      flexDirection="column"
      borderStyle="single"
      borderTop={false}
      paddingX={1}
    >
      <Box gap={1}>
        <Text color={headerColor} bold>
          worker {item.tmuxPane ?? `item-${item.id}`}:
        </Text>
        <Text>
          item {item.id} — {item.description}
        </Text>
        <Box flexGrow={1} />
        <Text dimColor>
          iter {item.iteration}/{item.maxIterations}
        </Text>
      </Box>

      {visible.length === 0 ? (
        <Text dimColor>No output captured</Text>
      ) : (
        visible.map((line, idx) => (
          <Text key={idx} wrap="truncate">
            {line}
          </Text>
        ))
      )}
    </Box>
  );
}
